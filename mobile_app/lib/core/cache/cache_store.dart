/// Shared cache primitives used by repositories that keep local copies of
/// remote data.
///
/// A [CacheStore] owns persistence and freshness metadata. It deliberately
/// knows nothing about entities, repositories, Supabase, or business rules.
library;

/// Clock used for cache freshness. Tests inject a deterministic clock.
typedef CacheClock = DateTime Function();

/// Resolves the identity that owns the active cache.
///
/// Returning `null` means "no cacheable identity" (for example, signed out).
/// In that state cache reads and writes must be skipped rather than falling
/// back to an unscoped key.
typedef CacheScopeProvider = String? Function();

/// Default lifetime for cached remote data.
const Duration kDefaultCacheTtl = Duration(hours: 24);

/// Version of the stored envelope format. Bump when the envelope shape changes.
const int kCacheEnvelopeSchemaVersion = 1;

/// A decoded cache entry together with the metadata needed to judge freshness.
class CacheRecord<T> {
  const CacheRecord({
    required this.value,
    required this.savedAt,
    required this.scope,
  });

  final T value;
  final DateTime savedAt;

  /// Identity that owned the entry when it was written.
  final String scope;

  /// Whether this entry is still within [ttl] at [now].
  ///
  /// A missing timestamp is not modeled here: stores only return a record when
  /// the envelope and its timestamp are valid.
  bool isFresh(DateTime now, Duration ttl) {
    if (ttl <= Duration.zero) return false;
    return now.difference(savedAt) < ttl;
  }
}

/// Persistence boundary for the shared cache architecture.
///
/// Implementations must never throw. Corrupt or unreadable entries return
/// `null`; failed writes return `false` so callers cannot report persisted
/// success they did not get.
abstract interface class CacheStore {
  /// Reads [key] for [scope].
  ///
  /// Returns `null` when the key is absent, unreadable, corrupt, or belongs to
  /// another scope. Implementations may remove corrupt entries.
  Future<CacheRecord<Object?>?> read(String key, {required String scope});

  /// Writes [value] under [key] for [scope].
  ///
  /// Returns `false` without throwing when persistence or encoding fails.
  Future<bool> write(
    String key,
    Object? value, {
    required String scope,
    DateTime? savedAt,
  });

  /// Removes one key. Returns `false` when the key could not be removed.
  Future<bool> remove(String key);

  /// Removes every key matching [test].
  ///
  /// Returns the number of removed keys, or `-1` when the backing store could
  /// not be read.
  Future<int> removeWhere(bool Function(String key) test);
}
