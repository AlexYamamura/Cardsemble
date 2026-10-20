import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardsemble/core/core.dart';

import 'fake_cache_store.dart';

class _TestRepository extends CachedRepository<String, String> {
  _TestRepository({
    required super.store,
    super.ttl,
    super.clock,
    super.scopeProvider,
    super.allowStaleOnError,
  });

  final List<Set<String>> fetchCalls = [];
  Future<Result<Map<String, String>>> Function(Set<String> keys)? onFetch;

  @override
  String get namespace => 'test_namespace';

  @override
  String keyOf(String value) => value.split(':').first;

  @override
  Object? encodeValue(String value) => value;

  @override
  String decodeValue(Object? json) => json as String;

  @override
  Future<Result<Map<String, String>>> fetchRemote(Set<String> keys) async {
    fetchCalls.add(keys);
    final handler = onFetch;
    if (handler != null) return handler(keys);
    return Success(<String, String>{
      for (final key in keys) key: '$key:remote',
    });
  }
}

void main() {
  late FakeCacheStore store;
  late DateTime now;
  late String? scope;

  _TestRepository repository({
    Duration ttl = kDefaultCacheTtl,
    bool allowStaleOnError = true,
  }) {
    return _TestRepository(
      store: store,
      ttl: ttl,
      clock: () => now,
      scopeProvider: () => scope,
      allowStaleOnError: allowStaleOnError,
    );
  }

  Future<void> seed(String key, String value, {DateTime? savedAt}) {
    return store.write(
      repository().cacheKeyFor(key, scope!),
      value,
      scope: scope!,
      savedAt: savedAt ?? now,
    );
  }

  setUp(() {
    store = FakeCacheStore();
    now = DateTime(2026, 1, 1, 12);
    scope = 'user-a';
  });

  test('a cache miss fetches in one batch and persists the results', () async {
    final repo = repository();

    final batch = await repo.getMany(<String>['a']);

    expect(batch.values, {'a': 'a:remote'});
    expect(batch.missingKeys, isEmpty);
    expect(batch.failure, isNull);
    expect(repo.fetchCalls, [
      {'a'},
    ]);
    expect(store.entries.length, 1);
  });

  test('fresh cached values avoid a remote call', () async {
    final repo = repository();
    await repo.getMany(<String>['a']);
    repo.fetchCalls.clear();

    final batch = await repo.getMany(<String>['a']);

    expect(batch.values['a'], 'a:remote');
    expect(repo.fetchCalls, isEmpty);
  });

  test('expired values refresh according to the default TTL', () async {
    final repo = repository();
    await repo.getMany(<String>['a']);
    repo.fetchCalls.clear();

    now = now.add(kDefaultCacheTtl + const Duration(minutes: 1));
    final batch = await repo.getMany(<String>['a']);

    expect(batch.values['a'], 'a:remote');
    expect(repo.fetchCalls.single, {'a'});
  });

  test('different repositories can use different TTLs', () async {
    final longLived = repository();
    await longLived.getMany(<String>['a']);
    final shortLived = repository(ttl: const Duration(hours: 1));

    now = now.add(const Duration(hours: 2));
    shortLived.fetchCalls.clear();
    await shortLived.getMany(<String>['a']);

    expect(shortLived.fetchCalls.single, {'a'});
  });

  test('only missing or expired keys are fetched', () async {
    final repo = repository();
    now = now.add(const Duration(hours: 1));
    await seed('a', 'a:cached', savedAt: now);
    await seed(
      'b',
      'b:stale',
      savedAt: now.subtract(kDefaultCacheTtl + const Duration(hours: 1)),
    );

    final batch = await repo.getMany(<String>['a', 'b', 'c']);

    expect(repo.fetchCalls.single, {'b', 'c'});
    expect(batch.values['a'], 'a:cached');
    expect(batch.values['b'], 'b:remote');
    expect(batch.values['c'], 'c:remote');
  });

  test('partial remote responses leave absent keys unresolved', () async {
    final repo = repository();
    repo.onFetch = (keys) async => const Success({'a': 'a:remote'});

    final batch = await repo.getMany(<String>['a', 'b']);

    expect(batch.values, {'a': 'a:remote'});
    expect(batch.missingKeys, {'b'});
    expect(batch.failure, isNull);
  });

  test('a remote error serves stale cached data when allowed', () async {
    final repo = repository();
    await seed(
      'a',
      'a:stale',
      savedAt: now.subtract(kDefaultCacheTtl + const Duration(hours: 1)),
    );
    repo.onFetch = (keys) async => const FailureResult(NetworkFailure('offline'));

    final batch = await repo.getMany(<String>['a']);

    expect(batch.values['a'], 'a:stale');
    expect(batch.staleKeys, {'a'});
    expect(batch.failure, isA<NetworkFailure>());
  });

  test('a remote error without stale data reports the failure', () async {
    final repo = repository();
    repo.onFetch = (keys) async => const FailureResult(NetworkFailure('offline'));

    final batch = await repo.getMany(<String>['a']);

    expect(batch.values, isEmpty);
    expect(batch.missingKeys, {'a'});
    expect(batch.failure, isA<NetworkFailure>());
  });

  test('corrupt cached data is discarded and refetched', () async {
    final repo = repository();
    await store.write(
      repo.cacheKeyFor('a', scope!),
      42,
      scope: scope!,
      savedAt: now,
    );

    final batch = await repo.getMany(<String>['a']);

    expect(batch.values['a'], 'a:remote');
    expect(repo.fetchCalls.single, {'a'});
  });

  test('a failed cache write does not report persisted success', () async {
    final repo = repository();
    store.failWrites = true;

    expect(await repo.put('a:remote'), isFalse);
    expect(store.entries, isEmpty);

    // Reads still return the remote value even though persistence failed.
    final batch = await repo.getMany(<String>['a']);
    expect(batch.values['a'], 'a:remote');
  });

  test('invalidation removes one key and forces a refresh', () async {
    final repo = repository();
    await repo.getMany(<String>['a', 'b']);
    repo.fetchCalls.clear();

    expect(await repo.invalidate('a'), isTrue);
    final batch = await repo.getMany(<String>['a', 'b']);

    expect(repo.fetchCalls.single, {'a'});
    expect(batch.values['b'], 'b:remote');
  });

  test('invalidateAll removes only this namespace and scope', () async {
    final repo = repository();
    await repo.getMany(<String>['a']);
    await store.write('cardsemble.cache.v1.other.user-a.keep', 'other', scope: scope!);
    await store.write(
      repo.cacheKeyFor('b', 'user-b'),
      'b:other-user',
      scope: 'user-b',
    );

    expect(await repo.invalidateAll(), isTrue);
    expect(store.entries.containsKey('cardsemble.cache.v1.other.user-a.keep'), isTrue);
    expect(
      store.entries.containsKey(repo.cacheKeyFor('b', 'user-b')),
      isTrue,
    );
  });

  test('a scope change during fetch discards the late response and write', () async {
    final repo = repository();
    final completer = Completer<Result<Map<String, String>>>();
    repo.onFetch = (keys) => completer.future;

    final pending = repo.getMany(<String>['a']);
    scope = 'user-b';
    completer.complete(const Success({'a': 'a:remote'}));

    final batch = await pending;

    expect(batch.values, isEmpty);
    expect(batch.failure, isA<AuthFailure>());
    expect(store.entries, isEmpty);
  });

  test('a null scope performs no cache or remote writes', () async {
    final repo = repository();
    scope = null;

    final batch = await repo.getMany(<String>['a']);

    expect(batch.values, isEmpty);
    expect(batch.failure, isA<AuthFailure>());
    expect(repo.fetchCalls, isEmpty);
    expect(store.entries, isEmpty);
  });

  test('get returns a failure when neither cache nor remote can answer', () async {
    final repo = repository();
    repo.onFetch = (keys) async => const FailureResult(NetworkFailure('offline'));

    final result = await repo.get('a');

    expect(result.isFailure, isTrue);
  });
}
