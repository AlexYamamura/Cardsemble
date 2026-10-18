import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:cardsemble/core/core.dart';
import 'package:cardsemble/features/accounts/domain/accounts_domain.dart';
import 'package:cardsemble/features/household/domain/household_domain.dart';
import 'package:cardsemble/features/transactions/domain/transactions_domain.dart';
import 'package:cardsemble/features/transactions/presentation/transactions_notifier.dart';
import 'package:cardsemble/features/transactions/presentation/transactions_screen.dart';
import 'package:cardsemble/features/transactions/presentation/widgets/unified_split_slider.dart';

/// Formats today's date the way the transaction list expects (yyyy-MM-dd), so
/// the seeded transaction falls inside the default current-month range.
String _today() {
  final now = DateTime.now();
  final month = now.month.toString().padLeft(2, '0');
  final day = now.day.toString().padLeft(2, '0');
  return '${now.year.toString().padLeft(4, '0')}-$month-$day';
}

class _FakeTransactionRepository implements TransactionRepository {
  _FakeTransactionRepository({
    required this.transactions,
    Map<String, List<TransactionSplit>>? splitsMap,
  }) : splitsMap = splitsMap ?? {};

  final List<CardTransaction> transactions;
  final Map<String, List<TransactionSplit>> splitsMap;

  @override
  Future<Result<TransactionPage>> loadTransactions(TransactionQuery query) async {
    return Success(TransactionPage(items: transactions, hasMore: false));
  }

  @override
  Future<Result<List<StatementAccount>>> loadAccounts() async {
    return Success(const <StatementAccount>[]);
  }

  @override
  Future<Result<TransactionAssignment>> assignTransaction(
    String transactionId,
    String? personId,
  ) async {
    return Success(
      TransactionAssignment(personId: personId, assignmentSource: 'manual'),
    );
  }

  @override
  Future<Result<void>> assignTransactionSplit(
    String transactionId,
    List<TransactionSplit> splits,
  ) async {
    return const Success(null);
  }

  @override
  Future<Result<List<TransactionSplit>>> fetchTransactionSplits(
    String transactionId,
  ) async {
    return Success(splitsMap[transactionId] ?? const <TransactionSplit>[]);
  }

  @override
  Future<Result<void>> setHouseholdVisible(
    String transactionId,
    bool visible,
  ) async {
    return const Success(null);
  }

  @override
  Future<Result<CsvImportPreview>> previewCsvImport(
    String accountId,
    String csvText,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<Result<CsvImportResult>> confirmCsvImport(
    String accountId,
    List<CsvImportRow> rows,
    String filename,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<Result<List<CsvImportHistory>>> loadCsvImportHistory() async {
    throw UnimplementedError();
  }
}

class _FakeHouseholdRepository implements HouseholdRepository {
  _FakeHouseholdRepository({required this.people});

  final List<HouseholdPerson> people;

  @override
  Future<Result<List<HouseholdPerson>>> loadPeople() async {
    return Success(people);
  }

  @override
  Future<Result<HouseholdPerson>> createPerson(
    String displayName, {
    bool isDefault = false,
  }) async {
    return Success(
      HouseholdPerson(id: 'new', displayName: displayName, isDefault: isDefault),
    );
  }

  @override
  Future<Result<void>> updatePerson(
    String personId,
    String displayName, {
    bool? isDefault,
  }) async {
    return const Success(null);
  }

  @override
  Future<Result<void>> deletePerson(String personId) async {
    return const Success(null);
  }

  @override
  Future<Result<List<HouseholdMember>>> loadMembers() async {
    return Success(const <HouseholdMember>[]);
  }

  @override
  Future<Result<void>> addMember(String userId) async {
    return const Success(null);
  }

  @override
  Future<Result<JoinHouseholdResult>> joinByInviteCode(String inviteCode) async {
    return Success(JoinHouseholdResult(householdId: 'household', member: null));
  }
}

Future<void> _pumpTransactionsScreen(
    WidgetTester tester, {
    required List<HouseholdPerson> people,
    required CardTransaction transaction,
  }) async {
    final emptySplitsMap = <String, List<TransactionSplit>>{};
    final notifier = TransactionsNotifier(
      transactionRepository: _FakeTransactionRepository(
        transactions: [transaction],
        splitsMap: emptySplitsMap,
      ),
      householdRepository: _FakeHouseholdRepository(people: people),
      loadTransactionSplitDraft: LoadTransactionSplitDraft(
        _FakeTransactionRepository(
          transactions: [transaction],
          splitsMap: emptySplitsMap,
        ),
      ),
      saveTransactionSplit: SaveTransactionSplit(
        _FakeTransactionRepository(
          transactions: [transaction],
          splitsMap: emptySplitsMap,
        ),
      ),
    );
    await notifier.loadAll();

    await tester.pumpWidget(
      ChangeNotifierProvider<TransactionsNotifier>.value(
        value: notifier,
        child: const MaterialApp(home: TransactionsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

void main() {
  // A narrow but realistic phone width. The ListTile.trailing contract only
  // breaks when a growable child saturates to the tile width, which happens
  // exactly when the assignee name is long enough to be truncated.
  const Size phoneSize = Size(360, 800);

  CardTransaction longNameTransaction({required String personId}) {
    return CardTransaction(
      id: 'tx-1',
      amount: '-42.50',
      currency: 'USD',
      date: _today(),
      name: 'Coffee Shop',
      merchant: 'Blue Bottle Coffee',
      pending: false,
      assignmentSource: 'manual',
      assignedPersonId: personId,
    );
  }

  testWidgets(
    'transaction tile trailing does not overflow with a long assignee name',
    (tester) async {
      tester.view.physicalSize = phoneSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const longName = 'Konstantinos Papadopoulos';
      const people = [
        HouseholdPerson(id: 'p1', displayName: longName, isDefault: true),
      ];

      await _pumpTransactionsScreen(
        tester,
        people: people,
        transaction: longNameTransaction(personId: 'p1'),
      );

      // The key regression guard: the ListTile "trailing widget consumes the
      // entire tile width" assertion (and any RenderFlex overflow) must not fire.
      expect(tester.takeException(), isNull);

      // The long name is actually rendered in the subtitular assignee selector,
      // so the layout path under test was exercised.
      expect(find.text(longName), findsWidgets);
      expect(find.text('Blue Bottle Coffee'), findsWidgets);
    },
  );

  testWidgets(
    'transaction tile trailing survives a very long multi-word assignee name',
    (tester) async {
      tester.view.physicalSize = phoneSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const veryLongName = 'Grandmothers Retirement Trust Fund';
      const people = [
        HouseholdPerson(id: 'p1', displayName: veryLongName, isDefault: true),
      ];

      await _pumpTransactionsScreen(
        tester,
        people: people,
        transaction: longNameTransaction(personId: 'p1'),
      );

      expect(tester.takeException(), isNull);
      expect(find.text(veryLongName), findsWidgets);
    },
  );

  testWidgets(
    'expanded split section lays 3 participants side-by-side with a unified slider',
    (tester) async {
      tester.view.physicalSize = phoneSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const people = [
        HouseholdPerson(id: 'p1', displayName: 'Alice', isDefault: true),
        HouseholdPerson(id: 'p2', displayName: 'Bob', isDefault: false),
        HouseholdPerson(id: 'p3', displayName: 'Cara', isDefault: false),
      ];

      await _pumpTransactionsScreen(
        tester,
        people: people,
        transaction: longNameTransaction(personId: 'p1'),
      );

      // Req 4: the assignee is selectable from the collapsed main row.
      expect(find.text('Alice'), findsWidgets);

      await tester.tap(find.byType(ExpansionTile).first);
      await tester.pumpAndSettle();

      // Req 1: each participant renders a single-line, ellipsizing name column
      // laid out horizontally (equal top, strictly increasing left).
      final alice = find.byKey(const ValueKey('split-name-p1'));
      final bob = find.byKey(const ValueKey('split-name-p2'));
      final cara = find.byKey(const ValueKey('split-name-p3'));
      expect(alice, findsOneWidget);
      expect(bob, findsOneWidget);
      expect(cara, findsOneWidget);

      final rAlice = tester.getRect(alice);
      final rBob = tester.getRect(bob);
      final rCara = tester.getRect(cara);
      expect(rBob.top, moreOrLessEquals(rAlice.top, epsilon: 0.5));
      expect(rCara.top, moreOrLessEquals(rAlice.top, epsilon: 0.5));
      expect(rBob.left, greaterThan(rAlice.left));
      expect(rCara.left, greaterThan(rBob.left));

      for (final finder in [alice, bob, cara]) {
        final text = tester.widget<Text>(finder);
        expect(text.maxLines, 1);
        expect(text.overflow, TextOverflow.ellipsis);
      }

      // Req 2: the unified split slider is rendered.
      expect(find.byType(UnifiedSplitSlider), findsOneWidget);

      // Req 4: the old assignee control is gone from the expanded dropdown.
      expect(find.text('ASSIGNED TO'), findsNothing);

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'expanded split section fits 4 long participant names without overflow',
    (tester) async {
      tester.view.physicalSize = phoneSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const people = [
        HouseholdPerson(
          id: 'p1',
          displayName: 'Alexandria Konstantinopoulos',
          isDefault: true,
        ),
        HouseholdPerson(
          id: 'p2',
          displayName: 'Bartholomew Featherstonehaugh',
          isDefault: false,
        ),
        HouseholdPerson(
          id: 'p3',
          displayName: 'Clementine Van Der Berg',
          isDefault: false,
        ),
        HouseholdPerson(
          id: 'p4',
          displayName: 'Dimitrios Papadopoulos',
          isDefault: false,
        ),
      ];

      await _pumpTransactionsScreen(
        tester,
        people: people,
        transaction: longNameTransaction(personId: 'p1'),
      );

      await tester.tap(find.byType(ExpansionTile).first);
      await tester.pumpAndSettle();

      // All four long names stay single-line + ellipsizing and share one row.
      final ids = ['p1', 'p2', 'p3', 'p4'];
      final finders = [
        for (final id in ids) find.byKey(ValueKey('split-name-$id')),
      ];
      final rects = [for (final f in finders) tester.getRect(f)];

      for (var i = 0; i < finders.length; i++) {
        final text = tester.widget<Text>(finders[i]);
        expect(text.maxLines, 1);
        expect(text.overflow, TextOverflow.ellipsis);
        if (i > 0) {
          expect(rects[i].top, moreOrLessEquals(rects[0].top, epsilon: 0.5));
          expect(rects[i].left, greaterThan(rects[i - 1].left));
        }
      }

       expect(find.byType(UnifiedSplitSlider), findsOneWidget);
       expect(tester.takeException(), isNull);
     },
   );

  testWidgets(
    'shows the current-month date chip on first load',
    (tester) async {
      tester.view.physicalSize = phoneSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const people = [
        HouseholdPerson(id: 'p1', displayName: 'Me', isDefault: true),
      ];
      final transaction = CardTransaction(
        id: 'tx-1',
        amount: '-42.50',
        currency: 'USD',
        date: _today(),
        name: 'Coffee',
        merchant: 'Cafe',
        pending: false,
        assignmentSource: 'manual',
        assignedPersonId: 'p1',
      );

      await _pumpTransactionsScreen(
        tester,
        people: people,
        transaction: transaction,
      );

      // The shared notifier defaults to the current month, so the date filter
      // is active from the first frame and the date chip / Clear all control
      // renders without the user touching any filter.
      expect(find.text('Clear all'), findsOneWidget);
      expect(find.byType(InputChip), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );


}
