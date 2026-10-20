import 'package:cardsemble/core/cache/cache_store.dart';
import 'package:cardsemble/core/error/failure.dart';

/// Result of a batched cache read.
///
/// [failure] describes a remote refresh that could not complete. It is not a
/// failure of the whole read when [values] contains cached entries.
class CacheBatchResult<K, V> {
  const CacheBatchResult({
    required this.values,
    this.staleKeys = const {},
    this.missingKeys = const {},
    this.failure,
  });

  final Map<K, V> values;

  /// Keys served from an expired cache entry after a refresh failure.
  final Set<K> staleKeys;

  /// Keys that could not be served from cache or remote.
  final Set<K> missingKeys;

  final Failure? failure;
}

/// Reusable parent for repositories that read remote entities through a local
/// cache.
///
/// Responsibilities are deliberately narrow:
/// - cache-first reads with a configurable TTL (24 hours by default);
/// - batching only the keys that are missing or expired;
/// - writing successful remote values back to cache;
/// - serving stale cache when a refresh fails, if enabled;
/// - refusing to read or write when the cache scope changes mid-flight.
///
/// Entity-specific remote queries, mapping, and domain behavior stay in
/// concrete repositories. Persistence and envelope validation stay in
/// [CacheStore]. This class has no Supabase or Flutter dependency.
abstract class CachedRepository<K, V> {
  CachedRepository({
    required this.store,
    this.ttl = kDefaultCacheTtl,
    CacheClock? clock,
    CacheScopeProvider? scopeProvider,
    this.allowStaleOnError = true,
  })  : clock = clock ?? DateTime.now,
        scopeProvider = scopeProvider ?? _noScope;

  final CacheStore store;

  /// Per-repository lifetime. Override for repositories with different data
  /// volatility; the default is 24 hours.
  final Duration ttl;

  /// Injectable clock so tests can exercise TTL boundaries without delays.
  final CacheClock clock;

  /// Resolves the active cache identity. User-scoped repositories should return
  /// the authenticated user id; global reference data may return a constant.
  final CacheScopeProvider scopeProvider;

  /// Whether expired cached values may be returned when a refresh fails.
  final bool allowStaleOnError;

  /// Cache namespace, for example `card_catalog`.
  String get namespace;

  /// Current cache identity, or `null` when reads and writes must be skipped.
  String? get currentScope => scopeProvider();

  /// Stable cache key for [key]. Override when `toString()` is not stable.
  String encodeKey(K key) => key.toString();

  /// Entity key used for write-through operations such as [put].
  K keyOf(V value);

  /// Converts an entity to JSON-compatible data for [CacheStore].
  Object? encodeValue(V value);

  /// Rebuilds an entity from cached data.
  ///
  /// Implementations should throw on malformed input; this class treats a
  /// decoding failure as a cache miss and replaces it after a remote fetch.
  V decodeValue(Object? json);

  /// Fetches the requested keys from the remote source in one batch.
  ///
  /// The returned map may omit unknown keys. Callers must not assume a value
  /// for every requested key.
  Future<Result<Map<K, V>>> fetchRemote(Set<K> keys);

  /// Returns one cached or remote value.
  Future<Result<V?>> get(K key, {bool forceRefresh = false}) async {
    final batch = await getMany(<K>[key], forceRefresh: forceRefresh);
    if (batch.values.containsKey(key)) return Success(batch.values[key]);

    final failure = batch.failure;
    if (failure != null) return FailureResult(failure);
    return Success<V?>(null);
  }

  /// Returns cached values for [keys] and refreshes only missing or expired
  /// entries.
  ///
  /// Remote values that are not requested are ignored. A partial remote
  /// response leaves the absent keys in [CacheBatchResult.missingKeys] rather
  /// than fabricating values.
  Future<CacheBatchResult<K, V>> getMany(
    Iterable<K> keys, {
    bool forceRefresh = false,
  }) async {
    final uniqueByEncoded = <String, K>{};
    for (final key in keys) {
      uniqueByEncoded.putIfAbsent(encodeKey(key), () => key);
    }
    final uniqueKeys = uniqueByEncoded.values.toList(growable: false);
    if (uniqueKeys.isEmpty) {
      return CacheBatchResult<K, V>(values: <K, V>{});
    }

    final scope = currentScope;
    if (scope == null) {
      return CacheBatchResult<K, V>(
        values: <K, V>{},
        missingKeys: uniqueKeys.toSet(),
        failure: const AuthFailure(
          'No signed-in user is available for cached data.',
        ),
      );
    }

    final now = clock();
    final fresh = <K, V>{};
    final stale = <K, V>{};
    final missing = <K>{};

    for (final key in uniqueKeys) {
      final cacheKey = cacheKeyFor(key, scope);
      final record = await store.read(cacheKey, scope: scope);
      if (record == null) {
        missing.add(key);
        continue;
      }

      V value;
      try {
        value = decodeValue(record.value);
      } catch (_) {
        // Corrupt entity data: discard it and refresh from remote.
        await store.remove(cacheKey);
        missing.add(key);
        continue;
      }

      if (!forceRefresh && record.isFresh(now, ttl)) {
        fresh[key] = value;
      } else {
        stale[key] = value;
        missing.add(key);
      }
    }

    if (missing.isEmpty) {
      return CacheBatchResult<K, V>(values: fresh);
    }

    Result<Map<K, V>> fetched;
    try {
      fetched = await fetchRemote(missing);
    } catch (error) {
      fetched = FailureResult(
        UnknownFailure('Could not refresh cached data: $error'),
      );
    }

    // A late response from a previous account must never be returned or
    // written under the active identity.
    if (currentScope != scope) {
      return CacheBatchResult<K, V>(
        values: <K, V>{},
        missingKeys: uniqueKeys.toSet(),
        failure: const AuthFailure(
          'The signed-in user changed while cached data was loading.',
        ),
      );
    }

    if (fetched.isFailure) {
      final values = <K, V>{...fresh};
      final staleKeys = <K>{};
      if (allowStaleOnError) {
        for (final key in missing) {
          if (!stale.containsKey(key)) continue;
          values[key] = stale[key] as V;
          staleKeys.add(key);
        }
      }
      final missingKeys = uniqueKeys
          .where((key) => !values.containsKey(key))
          .toSet();
      return CacheBatchResult<K, V>(
        values: values,
        staleKeys: staleKeys,
        missingKeys: missingKeys,
        failure: fetched.failure,
      );
    }

    final remote = fetched.value;
    final values = <K, V>{...fresh};
    for (final key in missing) {
      if (remote.containsKey(key)) values[key] = remote[key] as V;
    }

    // Persist only the values that were refreshed. A failed cache write is
    // intentionally not treated as a failed read; use [put] when the caller
    // needs to know whether persistence succeeded.
    for (final key in missing) {
      if (!remote.containsKey(key)) continue;
      if (currentScope != scope) {
        return CacheBatchResult<K, V>(
          values: <K, V>{},
          missingKeys: uniqueKeys.toSet(),
          failure: const AuthFailure(
            'The signed-in user changed while cached data was loading.',
          ),
        );
      }
      try {
        await store.write(
          cacheKeyFor(key, scope),
          encodeValue(remote[key] as V),
          scope: scope,
          savedAt: now,
        );
      } catch (_) {
        // Ignore: persistence is best-effort for a read-path refresh.
      }
    }

    final missingKeys =
        uniqueKeys.where((key) => !values.containsKey(key)).toSet();
    return CacheBatchResult<K, V>(
      values: values,
      missingKeys: missingKeys,
    );
  }

  /// Writes one entity through to the current scope.
  ///
  /// Returns `false` when there is no scope, encoding fails, or persistence
  /// fails.
  Future<bool> put(V value) async {
    final scope = currentScope;
    if (scope == null) return false;

    try {
      final encoded = encodeValue(value);
      return await store.write(
        cacheKeyFor(keyOf(value), scope),
        encoded,
        scope: scope,
        savedAt: clock(),
      );
    } catch (_) {
      return false;
    }
  }

  /// Writes several entities through to the current scope.
  ///
  /// Returns `true` only when every write succeeded.
  Future<bool> putAll(Iterable<V> values) async {
    var success = true;
    for (final value in values) {
      if (!await put(value)) success = false;
    }
    return success;
  }

  /// Removes one cached entity from the current scope.
  Future<bool> invalidate(K key) async {
    final scope = currentScope;
    if (scope == null) return false;

    try {
      return await store.remove(cacheKeyFor(key, scope));
    } catch (_) {
      return false;
    }
  }

  /// Removes every cached entity for this repository in the current scope.
  ///
  /// Other namespaces and other identities are untouched.
  Future<bool> invalidateAll() async {
    final scope = currentScope;
    if (scope == null) return false;

    try {
      final prefix = _scopePrefix(scope);
      final removed = await store.removeWhere((key) => key.startsWith(prefix));
      return removed >= 0;
    } catch (_) {
      return false;
    }
  }

  /// Key used by this repository for [key] under [scope].
  String cacheKeyFor(K key, String scope) {
    return '${_scopePrefix(scope)}${Uri.encodeComponent(encodeKey(key))}';
  }

  String _scopePrefix(String scope) {
    return 'cardsemble.cache.v1.$namespace.${Uri.encodeComponent(scope)}.';
  }

  static String? _noScope() => null;
}
