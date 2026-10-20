import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardsemble/core/core.dart';
import 'package:cardsemble/features/accounts/domain/accounts_domain.dart';
import 'package:cardsemble/features/household/domain/household_domain.dart';
import 'package:cardsemble/features/transactions/data/transaction_cache.dart';
import 'package:cardsemble/features/transactions/domain/transactions_domain.dart';
import 'package:cardsemble/features/transactions/presentation/transactions_notifier.dart';

import '../../../core/cache/fake_cache_store.dart';


CardTransaction _tx(String id, {String? assignedPersonId}) {
  return CardTransaction(
    id: id,
    accountId: 'a1',
    amount: '-10',
    currency: 'USD',
    date: '2026-01-02',
    name: 'Coffee',
    pending: false,
    assignmentSource: 'default',
    assignedPersonId: assignedPersonId,
  );
}

class FakeTransactionRepository implements TransactionRepository {
  FakeTransactionRepository({
    this.pageBuilder,
    this.assignment,
  });

  final Future<Result<TransactionPage>> Function(TransactionQuery query)? pageBuilder;
  TransactionAssignment? assignment;
  int transactionLoads = 0;
  int accountLoads = 0;
  int splitLoads = 0;

  @override
  Future<Result<TransactionPage>> loadTransactions(TransactionQuery query) {
    transactionLoads++;
    if (pageBuilder != null) return pageBuilder!(query);
    return Future.value(const Success(TransactionPage(items: [], hasMore: false)));
  }

  @override
  Future<Result<List<StatementAccount>>> loadAccounts() async {
    accountLoads++;
    return const Success(<StatementAccount>[]);
  }

  @override
  Future<Result<TransactionAssignment>> assignTransaction(
    String transactionId,
    String? personId,
  ) async {
    return Success(
      assignment ??
          TransactionAssignment(
            personId: personId,
            assignmentSource: personId == null ? 'default' : 'manual',
          ),
    );
  }

  @override
  Future<Result<void>> assignTransactionSplit(
    String transactionId,
    List<TransactionSplit> splits,
  ) async {
    return const Success<void>(null);
  }

  @override
  Future<Result<List<TransactionSplit>>> fetchTransactionSplits(String transactionId) async {
    splitLoads++;
    return const Success(<TransactionSplit>[]);
  }

  @override
  Future<Result<void>> setHouseholdVisible(String transactionId, bool visible) async {
    return const Success<void>(null);
  }

  @override
  Future<Result<CsvImportPreview>> previewCsvImport(String accountId, String csvText) {
    throw UnimplementedError();
  }

  @override
  Future<Result<CsvImportResult>> confirmCsvImport(
    String accountId,
    List<CsvImportRow> rows,
    String filename,
  ) async {
    return const Success(CsvImportResult(inserted: 0, duplicates: 0, errors: []));
  }

  @override
  Future<Result<List<CsvImportHistory>>> loadCsvImportHistory() async {
    return const Success(<CsvImportHistory>[]);
  }
}

class FakeHouseholdRepository implements HouseholdRepository {
  @override
  Future<Result<List<HouseholdPerson>>> loadPeople() async {
    return const Success(<HouseholdPerson>[
      HouseholdPerson(id: 'default-person', displayName: 'Me', isDefault: true),
    ]);
  }

  @override
  Future<Result<HouseholdPerson>> createPerson(String displayName, {bool isDefault = false}) {
    throw UnimplementedError();
  }

  @override
  Future<Result<void>> updatePerson(String personId, String displayName, {bool? isDefault}) {
    throw UnimplementedError();
  }

  @override
  Future<Result<void>> deletePerson(String personId) {
    throw UnimplementedError();
  }

  @override
  Future<Result<List<HouseholdMember>>> loadMembers() {
    throw UnimplementedError();
  }

  @override
  Future<Result<void>> addMember(String userId) {
    throw UnimplementedError();
  }

  @override
  Future<Result<JoinHouseholdResult>> joinByInviteCode(String inviteCode) {
    throw UnimplementedError();
  }
}

void main() {
  test('coalesces concurrent loadAll calls into a single fetch', () async {
    final repository = FakeTransactionRepository(
      pageBuilder: (query) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return const Success(TransactionPage(items: [], hasMore: false));
      },
    );
    final notifier = TransactionsNotifier(
      transactionRepository: repository,
      householdRepository: FakeHouseholdRepository(),
    );

    final first = notifier.loadAll();
    final second = notifier.loadAll();
    await Future.wait([first, second]);

    expect(repository.transactionLoads, 1);
    expect(repository.accountLoads, 1);
  });

  test('does not let an older response overwrite a newer one', () async {
    final firstCompleter = Completer<Result<TransactionPage>>();
    final secondCompleter = Completer<Result<TransactionPage>>();
    var call = 0;
    final repository = FakeTransactionRepository(
      pageBuilder: (query) {
        call++;
        return call == 1 ? firstCompleter.future : secondCompleter.future;
      },
    );
    final notifier = TransactionsNotifier(
      transactionRepository: repository,
      householdRepository: FakeHouseholdRepository(),
    );

    final firstLoad = notifier.loadTransactions(reset: true);
    final secondLoad = notifier.loadTransactions(reset: true);

    secondCompleter.complete(
      Success(TransactionPage(items: [_tx('newer')], hasMore: false)),
    );
    await secondLoad;
    firstCompleter.complete(
      Success(TransactionPage(items: [_tx('older')], hasMore: false)),
    );
    await firstLoad;

    expect(notifier.transactions.map((tx) => tx.id), ['newer']);
  });

  test('uses the server default person when unassigning', () async {
    final repository = FakeTransactionRepository(
      pageBuilder: (query) async =>
          Success(TransactionPage(items: [_tx('t1', assignedPersonId: 'p9')], hasMore: false)),
      assignment: const TransactionAssignment(
        personId: 'default-person',
        assignmentSource: 'default',
      ),
    );
    final notifier = TransactionsNotifier(
      transactionRepository: repository,
      householdRepository: FakeHouseholdRepository(),
    );

    await notifier.loadTransactions(reset: true);
    final ok = await notifier.assignTransaction('t1', null);

    expect(ok, isTrue);
    expect(notifier.transactions.single.assignedPersonId, 'default-person');
    expect(notifier.transactions.single.assignmentSource, 'default');
  });

  test('awaits the reload after saving a split', () async {
    final repository = FakeTransactionRepository(
      pageBuilder: (query) async =>
          Success(TransactionPage(items: [_tx('t1')], hasMore: false)),
    );
    final notifier = TransactionsNotifier(
      transactionRepository: repository,
      householdRepository: FakeHouseholdRepository(),
    );

    await notifier.loadTransactions(reset: true);
    final before = repository.transactionLoads;
     final ok = await notifier.saveTransactionSplit(
       transactionId: 't1',
       totalAmount: 10.0,
       percentages: const {'p1': 50.0, 'p2': 50.0},
       orderedPersonIds: const ['p1', 'p2'],
     );

    expect(ok, isTrue);
    expect(repository.transactionLoads, before + 1);
  });

  test('loadSplitDraft serves the second call from cache without a network hit', () async {
    final repository = FakeTransactionRepository(
      pageBuilder: (query) async =>
          Success(TransactionPage(items: [_tx('t1')], hasMore: false)),
    );
    final notifier = TransactionsNotifier(
      transactionRepository: repository,
      householdRepository: FakeHouseholdRepository(),
    );

    final first = await notifier.loadSplitDraft(
      transactionId: 't1',
      totalAmount: 10.0,
      participantIds: const ['p1', 'p2'],
    );
    expect(first.isSuccess, isTrue);
    expect(repository.splitLoads, 1);

    // Same transaction again: should be served from the local cache.
    final second = await notifier.loadSplitDraft(
      transactionId: 't1',
      totalAmount: 10.0,
      participantIds: const ['p1', 'p2'],
    );
    expect(second.isSuccess, isTrue);
    expect(repository.splitLoads, 1); // no additional network hit
  });

  test('saveTransactionSplit rewrites the split draft cache', () async {
    final repository = FakeTransactionRepository(
      pageBuilder: (query) async =>
          Success(TransactionPage(items: [_tx('t1')], hasMore: false)),
    );
    final notifier = TransactionsNotifier(
      transactionRepository: repository,
      householdRepository: FakeHouseholdRepository(),
    );

    // Prime the cache with equal splits.
    await notifier.loadSplitDraft(
      transactionId: 't1',
      totalAmount: 10.0,
      participantIds: const ['p1', 'p2'],
    );
    expect(repository.splitLoads, 1);

    // Saving a different allocation rewrites the cache.
    final ok = await notifier.saveTransactionSplit(
      transactionId: 't1',
      totalAmount: 10.0,
      percentages: const {'p1': 70.0, 'p2': 30.0},
      orderedPersonIds: const ['p1', 'p2'],
    );
    expect(ok, isTrue);

    // Re-loading the draft returns the saved percentages, no network hit.
    final reloaded = await notifier.loadSplitDraft(
      transactionId: 't1',
      totalAmount: 10.0,
      participantIds: const ['p1', 'p2'],
    );
    expect(reloaded.isSuccess, isTrue);
    expect(reloaded.value.length, 2);
    expect(reloaded.value['p1'], 70.0);
    expect(reloaded.value['p2'], 30.0);
    expect(repository.splitLoads, 1); // still no additional network hit
  });

  test('rolls back an optimistic household visibility change on failure', () async {
    final repository = FakeTransactionRepository(
      pageBuilder: (query) async =>
          Success(TransactionPage(items: [_tx('t1')], hasMore: false)),
    );
    repository.assignment = null;
    // Force setHouseholdVisible to fail via a throwing repository.
    final failing = _FailingVisibilityRepository(repository);
    final notifier = TransactionsNotifier(
      transactionRepository: failing,
      householdRepository: FakeHouseholdRepository(),
    );

    await notifier.loadTransactions(reset: true);
    final ok = await notifier.setHouseholdVisible('t1', false);

    expect(ok, isFalse);
    expect(notifier.transactions.single.householdVisible, isTrue);
  });

  test('defaults the shared date filter to current month-to-date', () {
    final notifier = TransactionsNotifier(
      transactionRepository: FakeTransactionRepository(),
      householdRepository: FakeHouseholdRepository(),
    );

    final today = dateOnly(DateTime.now());

    expect(notifier.dateRange, isNotNull);
    expect(notifier.dateRange!.start, DateTime(today.year, today.month));
    expect(notifier.dateRange!.end, today);
    expect(notifier.hasActiveFilters, isTrue);
  });

  test('hydrates a fresh transaction snapshot before the network completes', () async {
    final store = FakeCacheStore();
    final now = DateTime(2026, 1, 2, 12);
    final cache = TransactionCache(
      store: store,
      clock: () => now,
      scopeProvider: () => 'user-a',
    );
    await cache.write(
      scope: 'user-a',
      transactions: [_tx('cached')],
    );
    final completer = Completer<Result<TransactionPage>>();
    final repository = FakeTransactionRepository(
      pageBuilder: (query) => completer.future,
    );
    final notifier = TransactionsNotifier(
      transactionRepository: repository,
      householdRepository: FakeHouseholdRepository(),
      cache: cache,
    );

    final load = notifier.loadAll();
    await pumpEventQueue();

    expect(notifier.transactions.single.id, 'cached');

    completer.complete(
      const Success(TransactionPage(items: [], hasMore: false)),
    );
    await load;

    expect(notifier.transactions, isEmpty);
  });

  test('assignment works on a freshly hydrated snapshot', () async {
    final store = FakeCacheStore();
    final cache = TransactionCache(
      store: store,
      clock: () => DateTime(2026, 1, 2, 12),
      scopeProvider: () => 'user-a',
    );
    await cache.write(scope: 'user-a', transactions: [_tx('cached')]);
    final completer = Completer<Result<TransactionPage>>();
    final repository = FakeTransactionRepository(
      pageBuilder: (query) => completer.future,
    );
    final notifier = TransactionsNotifier(
      transactionRepository: repository,
      householdRepository: FakeHouseholdRepository(),
      cache: cache,
    );

    final load = notifier.loadAll();
    await pumpEventQueue();
    expect(notifier.transactions.single.id, 'cached');

    final assigned = await notifier.assignTransaction('cached', 'person-9');

    expect(assigned, isTrue);
    expect(notifier.transactions.single.assignedPersonId, 'person-9');

    completer.complete(
      const Success(TransactionPage(items: [], hasMore: false)),
    );
    await load;
  });

  test('visibility works on a freshly hydrated snapshot', () async {
    final store = FakeCacheStore();
    final cache = TransactionCache(
      store: store,
      clock: () => DateTime(2026, 1, 2, 12),
      scopeProvider: () => 'user-a',
    );
    await cache.write(scope: 'user-a', transactions: [_tx('cached')]);
    final completer = Completer<Result<TransactionPage>>();
    final repository = FakeTransactionRepository(
      pageBuilder: (query) => completer.future,
    );
    final notifier = TransactionsNotifier(
      transactionRepository: repository,
      householdRepository: FakeHouseholdRepository(),
      cache: cache,
    );

    final load = notifier.loadAll();
    await pumpEventQueue();
    expect(notifier.transactions.single.id, 'cached');

    final updated = await notifier.setHouseholdVisible('cached', false);

    expect(updated, isTrue);
    expect(notifier.transactions.single.householdVisible, isFalse);

    completer.complete(
      const Success(TransactionPage(items: [], hasMore: false)),
    );
    await load;
  });

  test('does not hydrate a transaction snapshot older than the TTL', () async {
    final store = FakeCacheStore();
    final writtenAt = DateTime(2026, 1, 1, 12);
    var now = writtenAt;
    final cache = TransactionCache(
      store: store,
      clock: () => now,
      scopeProvider: () => 'user-a',
    );
    await cache.write(scope: 'user-a', transactions: [_tx('cached')]);
    now = writtenAt.add(kDefaultCacheTtl + const Duration(hours: 1));

    final completer = Completer<Result<TransactionPage>>();
    final repository = FakeTransactionRepository(
      pageBuilder: (query) => completer.future,
    );
    final notifier = TransactionsNotifier(
      transactionRepository: repository,
      householdRepository: FakeHouseholdRepository(),
      cache: cache,
    );

    final load = notifier.loadAll();
    await pumpEventQueue();

    expect(notifier.transactions, isEmpty);

    completer.complete(
      const Success(TransactionPage(items: [], hasMore: false)),
    );
    await load;
  });

  test('serves an expired snapshot on refresh failure without re-stamping it', () async {
    final store = FakeCacheStore();
    final writtenAt = DateTime(2026, 1, 1, 12);
    var now = writtenAt;
    final cache = TransactionCache(
      store: store,
      clock: () => now,
      scopeProvider: () => 'user-a',
    );
    await cache.write(scope: 'user-a', transactions: [_tx('cached')]);
    now = writtenAt.add(kDefaultCacheTtl + const Duration(hours: 1));

    final repository = FakeTransactionRepository(
      pageBuilder: (query) async =>
          const FailureResult(NetworkFailure('offline')),
    );
    final notifier = TransactionsNotifier(
      transactionRepository: repository,
      householdRepository: FakeHouseholdRepository(),
      cache: cache,
    );

    await notifier.loadAll();

    expect(notifier.transactions.single.id, 'cached');
    expect(notifier.isShowingStaleData, isTrue);

    // A successful local edit must not make the old snapshot look fresh.
    final assigned = await notifier.assignTransaction('cached', 'person-9');
    expect(assigned, isTrue);
    expect(notifier.transactions.single.assignedPersonId, 'person-9');
    final snapshot = await cache.read();

    expect(snapshot.transactions.items.single.id, 'cached');
    expect(snapshot.transactions.savedAt!.isAtSameMomentAs(writtenAt), isTrue);
    expect(snapshot.transactions.isFresh(now, cache.ttl), isFalse);
  });

  test('a successful empty load replaces the stale fallback', () async {
    final store = FakeCacheStore();
    final cache = TransactionCache(
      store: store,
      clock: () => DateTime(2026, 1, 2, 12),
      scopeProvider: () => 'user-a',
    );
    await cache.write(scope: 'user-a', transactions: [_tx('cached')]);

    var fail = false;
    final repository = FakeTransactionRepository(
      pageBuilder: (query) async {
        if (fail) {
          return const FailureResult(NetworkFailure('offline'));
        }
        return const Success(TransactionPage(items: [], hasMore: false));
      },
    );
    final notifier = TransactionsNotifier(
      transactionRepository: repository,
      householdRepository: FakeHouseholdRepository(),
      cache: cache,
    );

    await notifier.loadAll();
    expect(notifier.transactions, isEmpty);

    fail = true;
    await notifier.loadTransactions(reset: true);

    // Stale fallback must point at the latest known-good (empty) response.
    expect(notifier.transactions, isEmpty);
  });

  test('resetForSessionChange clears user data and filters', () async {
    final repository = FakeTransactionRepository(
      pageBuilder: (query) async =>
          const Success(TransactionPage(items: [], hasMore: false)),
    );
    final notifier = TransactionsNotifier(
      transactionRepository: repository,
      householdRepository: FakeHouseholdRepository(),
    );
    await notifier.loadTransactions(reset: true);
    notifier.setAccountFilter('a1');

    notifier.resetForSessionChange();

    expect(notifier.transactions, isEmpty);
    expect(notifier.people, isEmpty);
    expect(notifier.accounts, isEmpty);
    expect(notifier.selectedAccountId, isNull);
    expect(notifier.selectedPersonId, isNull);
    expect(notifier.isShowingStaleData, isFalse);
    expect(notifier.dateRange, isNotNull);
  });

  test('assignment writes through to the transaction cache', () async {
    final store = FakeCacheStore();
    final cache = TransactionCache(
      store: store,
      scopeProvider: () => 'user-a',
      clock: () => DateTime(2026, 1, 2),
    );
    final repository = FakeTransactionRepository(
      pageBuilder: (query) async =>
          Success(TransactionPage(items: [_tx('t1')], hasMore: false)),
    );
    final notifier = TransactionsNotifier(
      transactionRepository: repository,
      householdRepository: FakeHouseholdRepository(),
      cache: cache,
    );
    await notifier.loadTransactions(reset: true);

    final ok = await notifier.assignTransaction('t1', 'person-9');

    expect(ok, isTrue);
    final snapshot = await cache.read();
    expect(snapshot.transactions.items.single.assignedPersonId, 'person-9');
  });

  test('visibility success writes through to the transaction cache', () async {
    final store = FakeCacheStore();
    final cache = TransactionCache(
      store: store,
      scopeProvider: () => 'user-a',
      clock: () => DateTime(2026, 1, 2),
    );
    final repository = FakeTransactionRepository(
      pageBuilder: (query) async =>
          Success(TransactionPage(items: [_tx('t1')], hasMore: false)),
    );
    final notifier = TransactionsNotifier(
      transactionRepository: repository,
      householdRepository: FakeHouseholdRepository(),
      cache: cache,
    );
    await notifier.loadTransactions(reset: true);

    expect(await notifier.setHouseholdVisible('t1', false), isTrue);
    final snapshot = await cache.read();
    expect(snapshot.transactions.items.single.householdVisible, isFalse);
  });

  test('discards a late response after the cache scope changes', () async {
    final store = FakeCacheStore();
    var scope = 'user-a';
    final cache = TransactionCache(
      store: store,
      scopeProvider: () => scope,
      clock: () => DateTime(2026, 1, 2),
    );
    final completer = Completer<Result<TransactionPage>>();
    final repository = FakeTransactionRepository(
      pageBuilder: (query) => completer.future,
    );
    final notifier = TransactionsNotifier(
      transactionRepository: repository,
      householdRepository: FakeHouseholdRepository(),
      cache: cache,
    );

    final load = notifier.loadTransactions(reset: true);
    await pumpEventQueue();
    scope = 'user-b';
    completer.complete(
      Success(TransactionPage(items: [_tx('late')], hasMore: false)),
    );
    await load;

    expect(notifier.transactions, isEmpty);
    expect(store.entries, isEmpty);
  });
}

class _FailingVisibilityRepository extends FakeTransactionRepository {
  _FailingVisibilityRepository(this.inner);

  final FakeTransactionRepository inner;

  @override
  Future<Result<TransactionPage>> loadTransactions(TransactionQuery query) =>
      inner.loadTransactions(query);

  @override
  Future<Result<void>> setHouseholdVisible(String transactionId, bool visible) async {
    return const FailureResult<void>(NetworkFailure('nope'));
  }
}
