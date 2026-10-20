import 'package:cardsemble/core/cache/cache.dart';

/// In-memory [CacheStore] with failure switches for cache lifecycle tests.
class FakeCacheStore implements CacheStore {
  FakeCacheStore({
    this.failReads = false,
    this.failWrites = false,
    this.failRemoveWhere = false,
  });

  final Map<String, CacheRecord<Object?>> entries = {};
  bool failReads;
  bool failWrites;
  bool failRemoveWhere;
  int writeCalls = 0;

  @override
  Future<CacheRecord<Object?>?> read(String key, {required String scope}) async {
    if (failReads) return null;
    final record = entries[key];
    if (record == null || record.scope != scope) return null;
    return record;
  }

  @override
  Future<bool> write(
    String key,
    Object? value, {
    required String scope,
    DateTime? savedAt,
  }) async {
    writeCalls++;
    if (failWrites) return false;
    entries[key] = CacheRecord<Object?>(
      value: value,
      savedAt: savedAt ?? DateTime.now(),
      scope: scope,
    );
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    return entries.remove(key) != null;
  }

  @override
  Future<int> removeWhere(bool Function(String key) test) async {
    if (failRemoveWhere) return -1;
    final matches = entries.keys.where(test).toList(growable: false);
    for (final key in matches) {
      entries.remove(key);
    }
    return matches.length;
  }
}
