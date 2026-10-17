import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardsemble/core/core.dart';
import 'package:cardsemble/features/accounts/domain/accounts_domain.dart';
import 'package:cardsemble/features/household/domain/household_domain.dart';
import 'package:cardsemble/features/transactions/domain/transactions_domain.dart';
import 'package:cardsemble/features/transactions/presentation/transactions_notifier.dart';


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
    return const Success(CsvImportResult(inserted: 0, errors: []));
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
