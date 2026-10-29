import 'package:flutter_test/flutter_test.dart';

import 'package:cardsemble/core/core.dart';
import 'package:cardsemble/features/card_catalog/data/card_catalog_repository.dart';
import 'package:cardsemble/features/card_catalog/domain/card_catalog_source.dart';
import 'package:cardsemble/features/card_catalog/domain/entities/card_catalog_card.dart';

import '../../../core/cache/fake_cache_store.dart';

class _FakeSource implements CardCatalogSource {
  _FakeSource({Map<String, CardCatalogCard>? cards})
      : cards = cards ?? <String, CardCatalogCard>{};

  final Map<String, CardCatalogCard> cards;
  int fetchCalls = 0;
  int fetchAllCalls = 0;
  Set<String> lastFetched = <String>{};
  Result<List<CardCatalogCard>>? fetchResult;
  Result<List<CardCatalogCard>>? fetchAllResult;

  @override
  Future<Result<List<CardCatalogCard>>> fetchCards(Set<String> ids) async {
    fetchCalls++;
    lastFetched = ids;
    final override = fetchResult;
    if (override != null) return override;
    return Success(<CardCatalogCard>[
      for (final id in ids)
        if (cards[id] != null) cards[id]!,
    ]);
  }

  @override
  Future<Result<List<CardCatalogCard>>> fetchAllCards() async {
    fetchAllCalls++;
    final override = fetchAllResult;
    if (override != null) return override;
    return Success(cards.values.toList(growable: false));
  }
}

CardCatalogCard _card(String id) {
  return CardCatalogCard(id: id, name: 'Card $id', issuer: 'Issuer $id');
}

void main() {
  late FakeCacheStore store;
  late _FakeSource source;
  late DateTime now;

  CardCatalogRepository repository({Duration ttl = kDefaultCacheTtl}) {
    return CardCatalogRepository(
      store: store,
      source: source,
      ttl: ttl,
      clock: () => now,
    );
  }

  setUp(() {
    store = FakeCacheStore();
    source = _FakeSource(cards: {
      'a': _card('a'),
      'b': _card('b'),
      'c': _card('c'),
    });
    now = DateTime(2026, 1, 1, 12);
  });

  test('a miss fetches one card and caches it under the global catalog scope', () async {
    final repo = repository();

    final result = await repo.get('a');

    expect(result.value!.id, 'a');
    expect(source.fetchCalls, 1);
    expect(store.entries.length, 1);
    expect(
      store.entries.keys.single,
      startsWith('cardsemble.cache.v1.card_catalog.global.'),
    );
  });

  test('a fresh card avoids another source call', () async {
    final repo = repository();
    await repo.get('a');

    await repo.get('a');

    expect(source.fetchCalls, 1);
  });

  test('a batch fetches only cards missing from the cache', () async {
    final repo = repository();
    await repo.get('a');
    source.fetchCalls = 0;

    final batch = await repo.getMany(<String>['a', 'b', 'c']);

    expect(source.lastFetched, {'b', 'c'});
    expect(batch.values.keys.toSet(), {'a', 'b', 'c'});
  });

  test('deselecting a card does not evict it or refetch it', () async {
    final repo = repository();
    await repo.getMany(<String>['a', 'b']);

    await repo.getMany(<String>['a']);
    await repo.getMany(<String>['a', 'b']);

    expect(source.fetchCalls, 1);
    expect(store.entries.length, 2);
  });

  test('a custom TTL controls catalog refresh', () async {
    final repo = repository(ttl: const Duration(hours: 1));
    await repo.get('a');
    now = now.add(const Duration(hours: 2));

    await repo.get('a');

    expect(source.fetchCalls, 2);
  });

  test('a partial source response leaves absent cards unresolved', () async {
    source.fetchResult = Success(<CardCatalogCard>[_card('a')]);
    final repo = repository();

    final batch = await repo.getMany(<String>['a', 'b']);

    expect(batch.values.keys.toSet(), {'a'});
    expect(batch.missingKeys, {'b'});
  });

  test('a failed refresh serves an expired card when available', () async {
    final repo = repository();
    await store.write(
      repo.cacheKeyFor('a', 'global'),
      _card('a').toJson(),
      scope: 'global',
      savedAt: now.subtract(const Duration(hours: 25)),
    );
    source.fetchResult = const FailureResult(NetworkFailure('offline'));

    final batch = await repo.getMany(<String>['a']);

    expect(batch.values['a']!.id, 'a');
    expect(batch.staleKeys, {'a'});
    expect(batch.failure, isA<NetworkFailure>());
  });

  test('getAllCards returns all cards from the source', () async {
    final repo = repository();
    final result = await repo.getAllCards();
    
    expect(result.isSuccess, isTrue);
    expect(result.value.length, 3);
    expect(source.fetchAllCalls, 1);
  });

  test('getAllCards serves a fresh snapshot without refetching the source', () async {
    final repo = repository();
    await repo.getAllCards();
    source.fetchAllCalls = 0;

    await repo.getAllCards();

    expect(source.fetchAllCalls, 0);
  });

  test('getAllCards refreshes from the source after the TTL expires', () async {
    final repo = repository(ttl: const Duration(hours: 1));
    await repo.getAllCards();
    source.fetchAllCalls = 0;
    now = now.add(const Duration(hours: 2));

    await repo.getAllCards();

    expect(source.fetchAllCalls, 1);
  });

  test('getAllCards serves an expired snapshot when the source fails', () async {
    final repo = repository();
    await repo.getAllCards();
    source.fetchAllCalls = 0;
    source.fetchAllResult = const FailureResult(NetworkFailure('offline'));
    now = now.add(const Duration(hours: 25));

    final result = await repo.getAllCards();

    expect(result.isSuccess, isTrue);
    expect(result.value.length, 3);
    expect(source.fetchAllCalls, 1);
  });
}
