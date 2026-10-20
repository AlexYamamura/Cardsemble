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

  /// Searches the catalog and writes returned cards through to the per-card
  /// cache.
  ///
  /// The query result list itself is not cached: searches can be unbounded and
  /// selection combinations must not become cache keys.
  Future<Result<List<CardCatalogCard>>> search(String query) async {
    final result = await _source.searchCards(query);
    if (result.isSuccess) {
      await putAll(result.value);
    }
    return result;
  }
}
