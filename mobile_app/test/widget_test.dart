import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cardsemble/ledger_api.dart';
import 'package:cardsemble/ledger_screen.dart';

void main() {
  testWidgets('opens capture setup once on first launch', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = _FakeLedgerApi();
    await tester.pumpWidget(
      MaterialApp(
        home: LedgerScreen(api: api, onSignOut: () async {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Plaid card connections'), findsOneWidget);
    expect(find.text('Link another card'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    await tester.tap(find.byTooltip('Close settings'));
    await tester.pumpAndSettle();

    expect(find.text('Household spending'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('capture_settings_reviewed'), isTrue);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    await tester.tap(find.byTooltip('Close settings'));
    await tester.pumpAndSettle();
  });

  testWidgets('shows transactions and captured card events', (tester) async {
    SharedPreferences.setMockInitialValues({'capture_settings_reviewed': true});
    final api = _FakeLedgerApi();
    await tester.pumpWidget(
      MaterialApp(
        home: LedgerScreen(api: api, onSignOut: () async {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Household spending'), findsOneWidget);
    expect(find.text('By credit card'), findsOneWidget);
    expect(find.text('By household member'), findsOneWidget);
    expect(find.text('Credit card ••8912'), findsOneWidget);
    expect(find.text('USD 42.50'), findsNWidgets(3));

    final previousMonth = DateTime(
      DateTime.now().year,
      DateTime.now().month - 1,
    );
    final previousMonthLabel =
        "${_monthAbbreviation(previousMonth.month)} "
        "'${previousMonth.year.toString().substring(2)}";
    await tester.tap(find.text(previousMonthLabel));
    await tester.pumpAndSettle();
    expect(
      find.text('No posted card charges in this date range.'),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(
        ValueKey('quick-month-${DateTime.now().year}-${DateTime.now().month}'),
      ),
    );
    await tester.pumpAndSettle();

    final cardSummaryRow = find.byKey(const ValueKey('summary-row-card-1'));
    await tester.ensureVisible(cardSummaryRow);
    await tester.tap(cardSummaryRow);
    await tester.pumpAndSettle();
    expect(find.text('Transactions'), findsNWidgets(2));
    expect(find.text('Credit card ••8912'), findsOneWidget);
    expect(find.text('Corner Market'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear summary filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transactions').last);
    await tester.pumpAndSettle();
    expect(find.text('Corner Market'), findsOneWidget);
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('USD 42.50'), findsNWidgets(2));

    await tester.tap(find.text('Events'));
    await tester.pumpAndSettle();

    expect(find.text('Corner Market notification'), findsOneWidget);
    expect(find.textContaining('iPhone Shortcut'), findsNWidgets(2));
  });

  testWidgets('saves a manual transaction assignment', (tester) async {
    SharedPreferences.setMockInitialValues({'capture_settings_reviewed': true});
    final api = _FakeLedgerApi();
    await tester.pumpWidget(
      MaterialApp(
        home: LedgerScreen(api: api, onSignOut: () async {}),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Transactions'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sam').last);
    await tester.pumpAndSettle();

    expect(api.lastAssignedTransactionId, 'tx-1');
    expect(api.lastAssignedPersonId, 'sam-id');
    expect(find.text('Manual override'), findsOneWidget);
    final assignee = tester.widget<Text>(
      find.byKey(const ValueKey('assignee-name-tx-1')),
    );
    expect(assignee.style?.fontSize, greaterThanOrEqualTo(20));
    expect(assignee.style?.color, const Color(0xFF4F46A5));
  });

  testWidgets('renames a card using a household display name', (tester) async {
    SharedPreferences.setMockInitialValues({'capture_settings_reviewed': true});
    final api = _FakeLedgerApi();
    await tester.pumpWidget(
      MaterialApp(
        home: LedgerScreen(api: api, onSignOut: () async {}),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Edit card name'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Plaid names: Ultimate Rewards'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('credit-card-display-name-field')),
      'Chase Freedom Unlimited',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(api.savedCardDisplayName, 'Chase Freedom Unlimited');
    expect(find.text('Chase Freedom Unlimited'), findsOneWidget);
  });

  testWidgets('adds a household person for later assignment', (tester) async {
    SharedPreferences.setMockInitialValues({'capture_settings_reviewed': true});
    final api = _FakeLedgerApi();
    await tester.pumpWidget(
      MaterialApp(
        home: LedgerScreen(api: api, onSignOut: () async {}),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('People'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add person'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Taylor');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(find.text('Taylor'), findsOneWidget);
    expect(api.people.last.displayName, 'Taylor');
  });
}

String _monthAbbreviation(int month) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return months[month - 1];
}

class _FakeLedgerApi implements LedgerApi {
  @override
  String get apiBaseUrl => 'https://example.test';

  String? lastAssignedTransactionId;
  String? lastAssignedPersonId;
  String? savedCardDisplayName;
  String assignmentSource = 'default';
  final Map<String, List<TransactionSplit>> savedSplits = {};
  final List<HouseholdPerson> people = [
    const HouseholdPerson(id: 'alex-id', displayName: 'Alex', isDefault: true),
    const HouseholdPerson(id: 'sam-id', displayName: 'Sam', isDefault: false),
  ];

  @override
  Future<void> assignTransaction(String transactionId, String? personId) async {
    lastAssignedTransactionId = transactionId;
    lastAssignedPersonId = personId;
    assignmentSource = personId == null ? 'default' : 'manual';
  }

  @override
  Future<void> assignTransactionSplit(String transactionId, List<TransactionSplit> splits) async {
    savedSplits[transactionId] = List.from(splits);
  }

  @override
  Future<List<TransactionSplit>> fetchTransactionSplits(String transactionId) async {
    return savedSplits[transactionId] ?? [];
  }

  @override
  Future<void> updateCreditCardDisplayName(
    String accountId,
    String? displayName,
  ) async {
    savedCardDisplayName = displayName;
  }

  @override
  Future<String> createPlaidLinkToken(String platform) async => 'link-token';

  @override
  Future<void> exchangePlaidPublicToken({
    required String publicToken,
    required String? institutionId,
    required String? institutionName,
    required String platform,
  }) async {}

  @override
  Future<List<PlaidConnection>> loadPlaidConnections() async => const [];

  @override
  Future<void> syncPlaidConnections() async {}

  @override
  Future<DeviceCaptureCredentials> createGooglePayDeviceToken(
    String personId,
  ) async => const DeviceCaptureCredentials(id: 'device-id', token: 'secret');

  @override
  Future<void> createPerson(String displayName) async {
    people.add(
      HouseholdPerson(
        id: 'new-person-id',
        displayName: displayName,
        isDefault: false,
      ),
    );
  }

  @override
  Future<void> revokeDeviceToken(String deviceId) async {}

  @override
  Future<List<CardEventRecord>> loadCardEvents() async => const [
    CardEventRecord(
      id: 'event-1',
      amount: '42.50',
      currency: 'USD',
      occurredAt: '2026-10-09T12:00:00Z',
      merchant: 'Corner Market notification',
      cardLabel: 'Shared Visa',
      paymentLabel: 'purchase',
      source: 'ios_shortcut',
      personId: 'alex-id',
    ),
  ];

  @override
  Future<List<HouseholdPerson>> loadPeople() async => people;

  @override
  Future<StatementCycleSummary> loadStatementCycles() async =>
      StatementCycleSummary(
        status: 'READY',
        total: '42.50',
        currency: 'USD',
        accountCount: 1,
        accounts: [
          StatementAccount(
            accountId: 'card-1',
            accountName: savedCardDisplayName ?? 'Credit card ••8912',
            displayName: savedCardDisplayName,
            plaidName: 'CREDIT CARD',
            officialName: 'Ultimate Rewards�',
            mask: '8912',
          ),
        ],
      );

  @override
  Future<List<CardTransaction>> loadTransactions() async => [
    CardTransaction(
      id: 'tx-1',
      accountId: 'card-1',
      accountName: savedCardDisplayName ?? 'Credit card ••8912',
      displayName: savedCardDisplayName,
      plaidName: 'CREDIT CARD',
      officialName: 'Ultimate Rewards�',
      accountMask: '8912',
      amount: '42.50',
      currency: 'USD',
      date: DateTime.now().toIso8601String().substring(0, 10),
      name: 'Corner Market',
      merchant: 'Corner Market',
      pending: false,
      transactionCode: 'purchase',
      assignedPersonId: lastAssignedPersonId ?? 'alex-id',
      assignmentSource: assignmentSource,
    ),
  ];
}
