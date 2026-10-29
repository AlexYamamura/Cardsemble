import 'package:cardsemble/core/cache/cache.dart';
import 'package:cardsemble/core/error/failure.dart';
import 'package:cardsemble/features/card_catalog/domain/card_catalog_source.dart';
import 'package:cardsemble/features/card_catalog/domain/entities/card_catalog_card.dart';

/// Catalog reference data cached one card at a time by stable catalog id.
///
/// Selection state is deliberately not represented: caching A+B, then A, never
/// evicts B, and selecting a new combination reuses every card that is still
/// fresh. Benefits, enrollment, usage, and redemption records are account data
/// and must not be stored by this repository.
class CardCatalogRepository extends CachedRepository<String, CardCatalogCard> {
  CardCatalogRepository({
    required super.store,
    required CardCatalogSource source,
    super.ttl = kDefaultCacheTtl,
    super.clock,
  }) : _source = source;

  final CardCatalogSource _source;

  @override
  String get namespace => 'card_catalog';

  @override
  String? get currentScope => 'global';

  @override
  String encodeKey(String key) => key;

  @override
  String keyOf(CardCatalogCard value) => value.id;

  @override
  Object? encodeValue(CardCatalogCard value) => value.toJson();

  @override
  CardCatalogCard decodeValue(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Cached card catalog entry is not an object.');
    }
    return CardCatalogCard.fromJson(json);
  }

  @override
  Future<Result<Map<String, CardCatalogCard>>> fetchRemote(Set<String> keys) async {
    final result = await _source.fetchCards(keys);
    return result.map((cards) {
      final byId = <String, CardCatalogCard>{};
      for (final card in cards) {
        byId[card.id] = card;
      }
      return byId;
    });
  }

  /// Fetches all cards from the catalog.
  ///
  /// The full catalog is served from a timestamped local snapshot when it is
  /// still fresh, so opening the wallet (or any other consumer) does not hit
  /// `/api/card-catalog` on every load. Individual cards are also written
  /// through to the per-key cache so `get`/`getMany` lookups are cached too.
  Future<Result<List<CardCatalogCard>>> getAllCards() async {
    final scope = currentScope;
    if (scope == null) {
      return const FailureResult(
        AuthFailure('No signed-in user is available for cached data.'),
      );
    }

    final now = clock();
    final snapshot = await _readAllCardsSnapshot(scope);
    if (snapshot != null && snapshot.isFresh(now, ttl)) {
      return Success(snapshot.items);
    }

    final result = await _source.fetchAllCards();
    if (result.isSuccess) {
      final cards = result.value;
      // Persist each card individually so per-card lookups are cached too.
      await putAll(cards);
      // Persist the full list as a timestamped snapshot.
      await _writeAllCardsSnapshot(scope, cards, now);
      return Success(cards);
    }

    // Degrade gracefully: serve an expired snapshot if one is available.
    if (snapshot != null) {
      return Success(snapshot.items);
    }
    return FailureResult(result.failure);
  }

  /// Reads the full-catalog snapshot for [scope], or `null` when absent or
  /// corrupt.
  Future<_AllCardsSnapshot?> _readAllCardsSnapshot(String scope) async {
    final key = _allCardsSnapshotCacheKey(scope);
    final record = await store.read(key, scope: scope);
    if (record == null) return null;
    try {
      final raw = record.value;
      if (raw is! Map<String, dynamic>) return null;
      final savedAtRaw = raw['saved_at'];
      final savedAt = savedAtRaw is String ? DateTime.tryParse(savedAtRaw) : null;
      final itemsRaw = raw['items'];
      if (savedAt == null || itemsRaw is! List) return null;
      final items = <CardCatalogCard>[];
      for (final item in itemsRaw) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('Cached catalog item is not an object.');
        }
        items.add(CardCatalogCard.fromJson(item));
      }
      return _AllCardsSnapshot(items: items, savedAt: savedAt);
    } catch (_) {
      return null;
    }
  }

  /// Writes the full-catalog snapshot for [scope] with [savedAt].
  Future<bool> _writeAllCardsSnapshot(
    String scope,
    List<CardCatalogCard> cards,
    DateTime savedAt,
  ) async {
    final key = _allCardsSnapshotCacheKey(scope);
    return await store.write(
      key,
      <String, dynamic>{
        'saved_at': savedAt.toIso8601String(),
        'items': cards.map((card) => card.toJson()).toList(growable: false),
      },
      scope: scope,
      savedAt: savedAt,
    );
  }

  /// Cache key under which the full-catalog snapshot is stored.
  String _allCardsSnapshotCacheKey(String scope) =>
      'cardsemble.cache.v1.${Uri.encodeComponent(namespace)}.'
      '${Uri.encodeComponent(scope)}.$_allCardsSnapshotKey';

  /// Key segment for the full-catalog snapshot within a scope.
  static const String _allCardsSnapshotKey = 'all_cards';
}

/// A timestamped snapshot of the full card catalog.
class _AllCardsSnapshot {
  const _AllCardsSnapshot({required this.items, required this.savedAt});

  final List<CardCatalogCard> items;
  final DateTime savedAt;

  /// Whether the snapshot is still within [ttl] at [now].
  bool isFresh(DateTime now, Duration ttl) {
    if (ttl <= Duration.zero) return false;
    return now.difference(savedAt) < ttl;
  }
}
