import 'dart:convert';

import 'package:cardsemble/features/card_catalog/domain/entities/card_catalog_card.dart';
import 'package:cardsemble/features/card_optimizer/domain/entities/optimized_result.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists per-card-type multipliers and computes the best card per rewards
/// category across a set of selected cards.
///
/// Multipliers are stored as a JSON map keyed by reward type (for example
/// `{ "points": 1.5, "cash": 1.0 }`). Unknown or corrupt values are treated as
/// `1.0`. Values <= 0 are coerced to `1.0`.
class CardOptimizerRepository {
  CardOptimizerRepository({SharedPreferences? prefs}) : _prefs = prefs;

  static const String _multipliersKey = 'card_optimizer.type_multipliers.v1';

  SharedPreferences? _prefs;

  /// Resolve the reward program type for a card.
  ///
  /// Resolution order:
  ///   1. Explicit `card.type` when it is exactly `points`, `cash`, or `travel`
  ///   2. `rewards.currency` / `rewards.currencyLabel` mapping:
  ///      - `usd` / `cash*` / `cash_back` → `cash`
  ///      - `*mile*` / `travel*` → `travel`
  ///      - `*point*` / `*reward*` / `membership_rewards` → `points`
  ///   3. Fall back to `card.type` (`credit` / `charge`) → `other`
  String rewardTypeFor(CardCatalogCard card) {
    final type = card.type?.toLowerCase();
    if (type != null && (type == 'points' || type == 'cash' || type == 'travel')) {
      return type;
    }

    final rewards = card.rewards;
    if (rewards != null) {
      final currency = (rewards.currency ?? rewards.currencyLabel ?? '')
          .toLowerCase();
      if (currency.contains('cash') ||
          currency.contains('usd') ||
          currency == 'cash_back' ||
          currency.contains('dollar')) {
        return 'cash';
      }
      if (currency.contains('mile') ||
          currency.contains('travel') ||
          currency.contains('airline')) {
        return 'travel';
      }
      if (currency.contains('point') ||
          currency.contains('reward') ||
          currency.contains('membership')) {
        return 'points';
      }
    }

    return 'other';
  }

  /// Normalize a free-text category label into a stable grouping key.
  ///
  /// Common synonyms map to canonical buckets; anything else falls back to the
  /// exact lowercased label. Original labels are preserved for display.
  String categoryKeyFor(String label) {
    final key = label.trim().toLowerCase();
    final aliases = {
      'dining': [
        'dining',
        'restaurants',
        'food',
        'eating',
        'bars',
        'nightlife',
      ],
      'groceries': ['groceries', 'grocery stores', 'supermarkets'],
      'gas': ['gas', 'gas stations', 'fuel', 'petrol', 'ev charging'],
      'travel': [
        'travel',
        'hotels',
        'airlines',
        'airfare',
        'flights',
        'transportation',
        'rideshare',
      ],
      'online_retail': ['online', 'retail', 'shopping', 'amazon', 'ebay'],
      'drugstores': ['drugstores', 'pharmacy', 'pharmacies', 'drugstore'],
      'streaming': ['streaming', 'netflix', 'spotify', 'subscription'],
      'transit': ['transit', 'commuter', 'toll', 'parking'],
    };

    for (final entry in aliases.entries) {
      if (entry.value.any((a) => key.contains(a))) {
        return entry.key;
      }
    }
    return key;
  }

  /// Compute the effective rate for a category given the card's multiplier.
  double effectiveRate(
    double basePointsPerDollar, {
    required double multiplier,
  }) {
    return basePointsPerDollar * multiplier;
  }

  /// Format a cap description from the catalog `cap` field.
  String? describeCap(Object? cap) {
    if (cap == null) return null;
    if (cap is String) return cap.isEmpty ? null : cap;
    if (cap is Map<String, dynamic>) {
      final amount = cap['amount'];
      final currency = cap['currency'] ?? '';
      final period = cap['period'];
      if (amount == null) return null;
      final formatted = amount is int
          ? amount.toString()
          : amount.toStringAsFixed(2);
      final parts = <String>[];
      if (currency is String && currency.isNotEmpty) {
        parts.add(currency);
      }
      parts.add(formatted);
      final periodStr = period is String && period.isNotEmpty
          ? ' per $period'
          : '';
      return '${parts.join(' ')}$periodStr';
    }
    return cap.toString();
  }

  /// Optimize all rewards categories across the given cards.
  ///
  /// Returns one `OptimizedResult` per category key, ranked by effective rate
  /// descending, then category label. Cards with no rewards/categories or a
  /// non-positive/missing points-per-dollar are skipped.
  List<OptimizedResult> optimize({
    required List<CardCatalogCard> cards,
    Map<String, double> typeMultipliers = const {},
  }) {
    // Per-category best: keep only the highest-effective-rate card per card+category.
    final perCategory = <String, List<OptimizerCandidate>>{};

    for (final card in cards) {
      final rewards = card.rewards;
      if (rewards == null || rewards.categories.isEmpty) continue;

      final rewardType = rewardTypeFor(card);
      final multiplier =
          (typeMultipliers[rewardType] ??
                  typeMultipliers[card.type ?? ''] ??
                  1.0)
              .clampDouble(0, double.infinity)
              .toDouble();
      final effectiveMultiplier = multiplier <= 0 ? 1.0 : multiplier;

      for (final category in rewards.categories) {
        final base = category.pointsPerDollar;
        if (base == null || base <= 0) continue;

        final baseD = base.toDouble();
        final key = categoryKeyFor(category.label ?? '');
        final effective = baseD * effectiveMultiplier;

        perCategory.putIfAbsent(key, () => <OptimizerCandidate>[]);
        perCategory[key]!.add(
          OptimizerCandidate(
            card: card,
            category: category,
            rewardType: rewardType,
            multiplier: effectiveMultiplier,
            basePointsPerDollar: baseD,
            effectivePointsPerDollar: effective,
            capDescription: describeCap(category.cap),
          ),
        );
      }
    }

    final results = <OptimizedResult>[];
    for (final entry in perCategory.entries) {
      final categoryKey = entry.key;
      final candidates = List<OptimizerCandidate>.from(entry.value)
        ..sort((a, b) {
          final rateCompare = b.effectivePointsPerDollar.compareTo(
            a.effectivePointsPerDollar,
          );
          if (rateCompare != 0) return rateCompare;
          // Tie-break: uncapped preferred, then larger cap, then higher base.
          final aCap = describeCap(a.category.cap);
          final bCap = describeCap(b.category.cap);
          if (aCap == null && bCap != null) return -1;
          if (bCap == null && aCap != null) return 1;
          final baseCompare = b.basePointsPerDollar.compareTo(
            a.basePointsPerDollar,
          );
          if (baseCompare != 0) return baseCompare;
          return a.card.name.compareTo(b.card.name);
        });

      final best = candidates.first;
      final capDesc = describeCap(best.category.cap);
      results.add(
        OptimizedResult(
          categoryKey: categoryKey,
          category: best.category,
          bestCard: best.card,
          rewardType: best.rewardType,
          multiplier: best.multiplier,
          basePointsPerDollar: best.basePointsPerDollar,
          effectivePointsPerDollar: best.effectivePointsPerDollar,
          capDescription: capDesc,
          candidates: candidates,
        ),
      );
    }

    results.sort((a, b) {
      final rateCompare = b.effectivePointsPerDollar.compareTo(
        a.effectivePointsPerDollar,
      );
      if (rateCompare != 0) return rateCompare;
      return a.categoryKey.compareTo(b.categoryKey);
    });

    return results;
  }

  /// Default multipliers for the given cards' observed types, all `1.0`.
  Map<String, double> defaultsFor(Iterable<CardCatalogCard> cards) {
    final types = <String>{};
    for (final card in cards) {
      types.add(rewardTypeFor(card));
    }
    return {for (final t in types) t: 1.0};
  }

  /// Load saved multipliers from SharedPreferences.
  Future<Map<String, double>> loadTypeMultipliers() async {
    final prefs = await _loadPrefs();
    final raw = prefs.getString(_multipliersKey);
    if (raw == null) return const {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final result = <String, double>{};
      for (final entry in decoded.entries) {
        if (entry.value is! num) continue;
        final value = entry.value.toDouble();
        result[entry.key] = value <= 0 || !value.isFinite ? 1.0 : value;
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  /// Persist multipliers to SharedPreferences.
  Future<bool> saveTypeMultipliers(Map<String, double> multipliers) async {
    final prefs = await _loadPrefs();
    final cleaned = <String, double>{};
    for (final entry in multipliers.entries) {
      cleaned[entry.key] = entry.value > 0 && entry.value.isFinite
          ? entry.value
          : 1.0;
    }
    return prefs.setString(_multipliersKey, jsonEncode(cleaned));
  }

  Future<SharedPreferences> _loadPrefs() async {
    if (_prefs != null) return _prefs!;
    _prefs = await SharedPreferences.getInstance();
    return _prefs!;
  }
}

extension _ClampDouble on double {
  double clampDouble(double min, double max) {
    if (this < min) return min;
    if (this > max) return max;
    return this;
  }
}
