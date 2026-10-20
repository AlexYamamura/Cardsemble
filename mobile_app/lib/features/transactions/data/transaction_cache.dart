import 'dart:async';

import 'package:cardsemble/core/cache/cache.dart';
import 'package:cardsemble/features/accounts/domain/accounts_domain.dart';
import 'package:cardsemble/features/household/domain/household_domain.dart';
import 'package:cardsemble/features/transactions/domain/transactions_domain.dart';

/// One dataset inside the transaction snapshot.
class CachedSection<T> {
  const CachedSection({required this.items, this.savedAt});

  const CachedSection.empty()
      : items = const [],
        savedAt = null;

  final List<T> items;

  /// When this specific dataset was refreshed. Absent means the section was
  /// corrupt, incomplete, or never written.
  final DateTime? savedAt;

  bool get hasData => items.isNotEmpty;

  bool isFresh(DateTime now, Duration ttl) {
    final saved = savedAt;
    if (saved == null || ttl <= Duration.zero) return false;
    return now.difference(saved) < ttl;
  }
}

/// Last successfully loaded transaction data, split into independently dated
/// sections so one dataset cannot imply that another is fresh.
class TransactionCacheSnapshot {
  const TransactionCacheSnapshot({
    required this.people,
    required this.accounts,
    required this.transactions,
    required this.summaryTransactions,
  });

  const TransactionCacheSnapshot.empty()
      : people = const CachedSection<HouseholdPerson>.empty(),
        accounts = const CachedSection<StatementAccount>.empty(),
        transactions = const CachedSection<CardTransaction>.empty(),
        summaryTransactions = const CachedSection<CardTransaction>.empty();

  final CachedSection<HouseholdPerson> people;
  final CachedSection<StatementAccount> accounts;
  final CachedSection<CardTransaction> transactions;
  final CachedSection<CardTransaction> summaryTransactions;

  DateTime? get latestSavedAt {
    final dates = <DateTime?>[
      people.savedAt,
      accounts.savedAt,
      transactions.savedAt,
      summaryTransactions.savedAt,
    ];
    DateTime? latest;
    for (final date in dates) {
      if (date == null) continue;
      if (latest == null || date.isAfter(latest)) latest = date;
    }
    return latest;
  }
}

/// First-frame cache for the transaction surface.
///
/// The snapshot is stored as one JSON document per authenticated user. A single
/// key means a write cannot leave the four datasets half-updated, while each
/// section carries its own timestamp so a people/accounts refresh does not make
/// the ledger look freshly loaded.
///
/// Writes are serialized through an in-process queue. Each write performs a
/// read-modify-write of the one snapshot key and updates only the supplied
/// sections.
class TransactionCache {
  TransactionCache({
    required CacheStore store,
    CacheClock? clock,
    CacheScopeProvider? scopeProvider,
    Duration ttl = kDefaultCacheTtl,
  })  : _store = store,
        _clock = clock ?? DateTime.now,
        _scopeProvider = scopeProvider ?? _noScope,
        _ttl = ttl;

  static const String namespace = 'transactions';
  static const String snapshotKey = 'snapshot';
  static const int _snapshotSchemaVersion = 2;

  /// Cache keys written by the previous, unscoped implementation. They cannot
  /// be attributed to a user, so they are discarded rather than migrated.
  static const Set<String> legacyKeys = {
    'tx_cache_people_v1',
    'tx_cache_accounts_v1',
    'tx_cache_transactions_v1',
    'tx_cache_summary_v1',
    'tx_cache_saved_at_v1',
  };

  final CacheStore _store;
  final CacheClock _clock;
  final CacheScopeProvider _scopeProvider;
  final Duration _ttl;

  Future<void> _pendingWrite = Future<void>.value();

  Duration get ttl => _ttl;

  String? get currentScope => _scopeProvider();

  /// Current time according to the injected clock, used by hydration so tests
  /// and production share the same freshness calculation.
  DateTime now() => _clock();

  /// Reads the snapshot for the active identity.
  ///
  /// Sections that are corrupt or missing are returned empty with a `null`
  /// timestamp. Expired sections retain their data and original timestamp;
  /// callers enforce TTL through [CachedSection.isFresh] and may keep the data
  /// as a stale fallback.
  Future<TransactionCacheSnapshot> read() async {
    final scope = currentScope;
    if (scope == null) return const TransactionCacheSnapshot.empty();

    try {
      await _pendingWrite;
    } catch (_) {
      // A previous write failed; the stored snapshot is still whatever was
      // last persisted successfully.
    }

    final key = _cacheKey(scope);
    final record = await _store.read(key, scope: scope);
    if (record == null) return const TransactionCacheSnapshot.empty();

    final raw = record.value;
    if (raw is! Map<String, dynamic>) {
      await _store.remove(key);
      return const TransactionCacheSnapshot.empty();
    }
    if (raw['schema_version'] != _snapshotSchemaVersion) {
      await _store.remove(key);
      return const TransactionCacheSnapshot.empty();
    }

    final sectionsRaw = raw['sections'];
    if (sectionsRaw is! Map) {
      await _store.remove(key);
      return const TransactionCacheSnapshot.empty();
    }

    Map<String, dynamic> sections;
    try {
      sections = Map<String, dynamic>.from(sectionsRaw);
    } catch (_) {
      await _store.remove(key);
      return const TransactionCacheSnapshot.empty();
    }

    return TransactionCacheSnapshot(
      people: _decodeSection<HouseholdPerson>(
        sections['people'],
        HouseholdPerson.fromJson,
      ),
      accounts: _decodeSection<StatementAccount>(
        sections['accounts'],
        StatementAccount.fromJson,
      ),
      transactions: _decodeSection<CardTransaction>(
        sections['transactions'],
        CardTransaction.fromJson,
      ),
      summaryTransactions: _decodeSection<CardTransaction>(
        sections['summary_transactions'],
        CardTransaction.fromJson,
      ),
    );
  }

  /// Updates only the supplied sections.
  ///
  /// Returns `false` when [scope] is no longer the active identity, nothing was
  /// supplied, or persistence failed. A section that is omitted keeps both its
  /// data and its original timestamp.
  Future<bool> write({
    required String? scope,
    List<HouseholdPerson>? people,
    List<StatementAccount>? accounts,
    List<CardTransaction>? transactions,
    List<CardTransaction>? summaryTransactions,
  }) {
    if (scope == null || currentScope != scope) {
      return Future<bool>.value(false);
    }
    if (people == null &&
        accounts == null &&
        transactions == null &&
        summaryTransactions == null) {
      return Future<bool>.value(false);
    }

    final operation = _pendingWrite.then(
      (_) => _writeNow(
        scope: scope,
        people: people,
        accounts: accounts,
        transactions: transactions,
        summaryTransactions: summaryTransactions,
      ),
    );
    _pendingWrite = operation.then<void>(
      (_) {},
      onError: (Object _) {},
    );
    return operation.catchError((_) => false);
  }

  /// Removes the active identity's snapshot.
  Future<bool> clearCurrentScope() {
    final scope = currentScope;
    if (scope == null) return Future<bool>.value(false);
    return clearScope(scope);
  }

  /// Removes one identity's snapshot.
  ///
  /// The scope is explicit so sign-out can clear the session that just ended
  /// even after the active user has already changed.
  Future<bool> clearScope(String scope) {
    final operation = _pendingWrite.then(
      (_) => _store.remove(_cacheKey(scope)),
    );
    _pendingWrite = operation.then<void>(
      (_) {},
      onError: (Object _) {},
    );
    return operation.catchError((_) => false);
  }

  /// Removes the five unscoped keys written by the old cache implementation.
  Future<void> purgeLegacyKeys() async {
    try {
      await _store.removeWhere(legacyKeys.contains);
    } catch (_) {
      // Legacy cleanup is best-effort.
    }
  }

  Future<bool> _writeNow({
    required String scope,
    required List<HouseholdPerson>? people,
    required List<StatementAccount>? accounts,
    required List<CardTransaction>? transactions,
    required List<CardTransaction>? summaryTransactions,
  }) async {
    try {
      if (currentScope != scope) return false;

      final key = _cacheKey(scope);
      final existing = await _readExistingSections(key, scope);
      final now = _clock();

      if (people != null) {
        existing['people'] = _encodeSection(people, (e) => e.toJson(), now);
      }
      if (accounts != null) {
        existing['accounts'] = _encodeSection(accounts, (e) => e.toJson(), now);
      }
      if (transactions != null) {
        existing['transactions'] =
            _encodeSection(transactions, (e) => e.toJson(), now);
      }
      if (summaryTransactions != null) {
        existing['summary_transactions'] =
            _encodeSection(summaryTransactions, (e) => e.toJson(), now);
      }

      if (existing.isEmpty) return false;

      return await _store.write(
        key,
        <String, dynamic>{
          'schema_version': _snapshotSchemaVersion,
          'sections': existing,
        },
        scope: scope,
        savedAt: now,
      );
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> _readExistingSections(
    String key,
    String scope,
  ) async {
    try {
      final record = await _store.read(key, scope: scope);
      final raw = record?.value;
      if (raw is! Map<String, dynamic>) return <String, dynamic>{};
      if (raw['schema_version'] != _snapshotSchemaVersion) {
        return <String, dynamic>{};
      }
      final sections = raw['sections'];
      if (sections is! Map) return <String, dynamic>{};
      return Map<String, dynamic>.from(sections);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  CachedSection<T> _decodeSection<T>(
    Object? raw,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (raw is! Map) return CachedSection<T>.empty();

    final savedAtRaw = raw['saved_at'];
    final savedAt =
        savedAtRaw is String ? DateTime.tryParse(savedAtRaw) : null;
    final itemsRaw = raw['items'];
    if (savedAt == null || itemsRaw is! List) {
      return CachedSection<T>.empty();
    }

    try {
      final items = <T>[];
      for (final item in itemsRaw) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('Cached item is not an object.');
        }
        items.add(fromJson(item));
      }
      return CachedSection<T>(
        items: List<T>.unmodifiable(items),
        savedAt: savedAt,
      );
    } catch (_) {
      // One malformed item invalidates the whole section. Returning a partial
      // ledger would make corrupt data look complete.
      return CachedSection<T>.empty();
    }
  }

  Map<String, dynamic> _encodeSection<T>(
    List<T> items,
    Map<String, dynamic> Function(T) toJson,
    DateTime now,
  ) {
    return <String, dynamic>{
      'saved_at': now.toIso8601String(),
      'items': items.map(toJson).toList(growable: false),
    };
  }

  String _cacheKey(String scope) {
    return 'cardsemble.cache.v2.$namespace.'
        '${Uri.encodeComponent(scope)}.$snapshotKey';
  }

  static String? _noScope() => null;
}
