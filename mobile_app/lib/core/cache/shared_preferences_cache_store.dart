import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:cardsemble/core/cache/cache_store.dart';

/// [CacheStore] backed by a single JSON envelope per key in SharedPreferences.
///
/// The legacy SharedPreferences API is kept intentionally: the existing app
/// already depends on it, unit tests can seed it with
/// `SharedPreferences.setMockInitialValues`, and one `setString` per key gives
/// the transaction snapshot an atomic write without adding a dependency.
///
/// Each envelope contains its own schema version, scope, and timestamp, so a
/// stale or foreign entry can never be mistaken for a fresh one.
class SharedPreferencesCacheStore implements CacheStore {
  SharedPreferencesCacheStore({
    Future<SharedPreferences> Function()? prefsProvider,
  }) : _prefsProvider = prefsProvider ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _prefsProvider;

  Future<SharedPreferences>? _prefs;

  Future<SharedPreferences> _instance() {
    return _prefs ??= _prefsProvider();
  }

  @override
  Future<CacheRecord<Object?>?> read(String key, {required String scope}) async {
    try {
      final prefs = await _instance();
      final raw = prefs.getString(key);
      if (raw == null) return null;

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        await _discard(prefs, key);
        return null;
      }
      if (decoded['schema_version'] != kCacheEnvelopeSchemaVersion) {
        await _discard(prefs, key);
        return null;
      }
      if (decoded['scope'] != scope) {
        await _discard(prefs, key);
        return null;
      }

      final savedAtRaw = decoded['saved_at'];
      final savedAt = savedAtRaw is String ? DateTime.tryParse(savedAtRaw) : null;
      if (savedAt == null) {
        await _discard(prefs, key);
        return null;
      }

      if (!decoded.containsKey('value')) {
        await _discard(prefs, key);
        return null;
      }

      return CacheRecord<Object?>(
        value: decoded['value'],
        savedAt: savedAt,
        scope: scope,
      );
    } catch (_) {
      // Never let corrupt local data or a platform failure break the app.
      return null;
    }
  }

  @override
  Future<bool> write(
    String key,
    Object? value, {
    required String scope,
    DateTime? savedAt,
  }) async {
    try {
      final prefs = await _instance();
      final envelope = <String, dynamic>{
        'schema_version': kCacheEnvelopeSchemaVersion,
        'scope': scope,
        'saved_at': (savedAt ?? DateTime.now()).toIso8601String(),
        'value': value,
      };
      return await prefs.setString(key, jsonEncode(envelope));
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> remove(String key) async {
    try {
      final prefs = await _instance();
      return await prefs.remove(key);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<int> removeWhere(bool Function(String key) test) async {
    try {
      final prefs = await _instance();
      final matches = prefs.getKeys().where(test).toList(growable: false);
      var removed = 0;
      for (final key in matches) {
        if (await prefs.remove(key)) removed++;
      }
      return removed;
    } catch (_) {
      return -1;
    }
  }

  Future<void> _discard(SharedPreferences prefs, String key) async {
    try {
      await prefs.remove(key);
    } catch (_) {
      // Best-effort recovery; the read already returns a miss.
    }
  }
}
