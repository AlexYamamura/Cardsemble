import 'package:cardsemble/features/card_catalog/domain/entities/card_catalog_card.dart';

/// The result of optimizing one rewards category across selected cards.
///
/// [category] is the original catalog category row, [categoryKey] is the
/// normalized grouping key used to compare across cards, [bestCard] is the
/// card with the highest effective rate, [rewardType] is the resolved reward
/// program type for [bestCard], and [multiplier] is the type-specific
/// multiplier applied when comparing.
class OptimizedResult {
  const OptimizedResult({
    required this.categoryKey,
    required this.category,
    required this.bestCard,
    required this.rewardType,
    required this.multiplier,
    required this.basePointsPerDollar,
    required this.effectivePointsPerDollar,
    required this.capDescription,
    required this.candidates,
  });

  /// Normalized category key used for grouping (for example `dining`).
  final String categoryKey;

  /// Original category row from the winning card (may fall back to any card
  /// offering this category).
  final CardRewardCategory category;

  /// Card offering the highest effective rate for this category.
  final CardCatalogCard bestCard;

  /// Resolved reward program type of the winning card.
  final String rewardType;

  /// Multiplier applied to [rewardType] when comparing cards.
  final double multiplier;

  /// Base points-per-dollar from the catalog category.
  final double basePointsPerDollar;

  /// Effective rate after applying [multiplier]: base × multiplier.
  final double effectivePointsPerDollar;

  /// Human readable cap description, or null when uncapped.
  final String? capDescription;

  /// All eligible cards ranked by effective rate for this category.
  final List<OptimizerCandidate> candidates;

  /// True when the winning card has no cap (cap == null).
  bool get isUncapped => capDescription == null;

  /// True when a tie-break was needed to pick [bestCard] over another card
  /// with the same effective rate.
  bool get hasTieBreak => candidates.length > 1 &&
      candidates[0].effectivePointsPerDollar ==
          candidates[1].effectivePointsPerDollar;

  OptimizedResult copyWith({
    String? categoryKey,
    CardRewardCategory? category,
    CardCatalogCard? bestCard,
    String? rewardType,
    double? multiplier,
    double? basePointsPerDollar,
    double? effectivePointsPerDollar,
    String? capDescription,
    List<OptimizerCandidate>? candidates,
  }) {
    return OptimizedResult(
      categoryKey: categoryKey ?? this.categoryKey,
      category: category ?? this.category,
      bestCard: bestCard ?? this.bestCard,
      rewardType: rewardType ?? this.rewardType,
      multiplier: multiplier ?? this.multiplier,
      basePointsPerDollar: basePointsPerDollar ?? this.basePointsPerDollar,
      effectivePointsPerDollar:
          effectivePointsPerDollar ?? this.effectivePointsPerDollar,
      capDescription: capDescription ?? this.capDescription,
      candidates: candidates ?? this.candidates,
    );
  }
}

/// One candidate card for a category, ranked by effective rate.
class OptimizerCandidate {
  const OptimizerCandidate({
    required this.card,
    required this.category,
    required this.rewardType,
    required this.multiplier,
    required this.basePointsPerDollar,
    required this.effectivePointsPerDollar,
    required this.capDescription,
  });

  final CardCatalogCard card;
  final CardRewardCategory category;
  final String rewardType;
  final double multiplier;
  final double basePointsPerDollar;
  final double effectivePointsPerDollar;
  final String? capDescription;
}
