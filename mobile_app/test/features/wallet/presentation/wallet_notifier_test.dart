import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cardsemble/core/core.dart';
import 'package:cardsemble/features/accounts/domain/accounts_domain.dart';
import 'package:cardsemble/features/accounts/presentation/accounts_notifier.dart';
import 'package:cardsemble/features/card_catalog/data/card_catalog_repository.dart';
import 'package:cardsemble/features/card_catalog/domain/card_catalog_source.dart';
import 'package:cardsemble/features/card_catalog/domain/entities/card_catalog_card.dart';
import 'package:cardsemble/features/household/domain/household_domain.dart';
import 'package:cardsemble/features/transactions/domain/transactions_domain.dart';
import 'package:cardsemble/features/transactions/presentation/transactions_notifier.dart';
import 'package:cardsemble/features/wallet/presentation/wallet_notifier.dart';
import '../../../core/cache/fake_cache_store.dart';

class FakeCardCatalogSource implements CardCatalogSource {
  FakeCardCatalogSource(this.cards);
  final List<CardCatalogCard> cards;

  @override
  Future<Result<List<CardCatalogCard>>> fetchCards(Set<String> ids) async {
    return Success(cards.where((card) => ids.contains(card.id)).toList(growable: false));
  }

  @override
  Future<Result<List<CardCatalogCard>>> fetchAllCards() async =>
      Success(List<CardCatalogCard>.from(cards));
}

class FakePlaidLinkLauncher implements PlaidLinkLauncher {
  @override
  Future<PlaidLinkResult> launch({required String linkToken}) async =>
      const PlaidLinkResult.failed('not used in wallet tests');
}

/// Minimal fake repos so [FakeTransactionsNotifier] can be constructed.
class _FakeTransactionRepository implements TransactionRepository {
  @override
  Future<Result<TransactionPage>> loadTransactions(TransactionQuery query) =>
      Future.value(const Success(TransactionPage(items: [], hasMore: false)));

  @override
  Future<Result<List<StatementAccount>>> loadAccounts() async =>
      const Success(<StatementAccount>[]);

  @override
  Future<Result<TransactionAssignment>> assignTransaction(
    String transactionId,
    String? personId,
  ) async {
    return Success(
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
  ) async =>
      const Success(null);

  @override
  Future<Result<List<TransactionSplit>>> fetchTransactionSplits(
    String transactionId,
  ) async =>
      const Success(<TransactionSplit>[]);

  @override
  Future<Result<void>> setHouseholdVisible(String transactionId, bool visible) async =>
      const Success(null);
}

class _FakeHouseholdRepository implements HouseholdRepository {
  @override
  Future<Result<List<HouseholdPerson>>> loadPeople() async =>
      const Success(<HouseholdPerson>[]);

  @override
  Future<Result<HouseholdPerson>> createPerson(
    String displayName, {
    bool isDefault = false,
  }) async {
    return Success(HouseholdPerson(id: 'p1', displayName: displayName, isDefault: isDefault));
  }

  @override
  Future<Result<void>> updatePerson(
    String personId,
    String displayName, {
    bool? isDefault,
  }) async =>
      const Success(null);

  @override
  Future<Result<void>> deletePerson(String personId) async =>
      const Success(null);

  @override
  Future<Result<List<HouseholdMember>>> loadMembers() async =>
      const Success(<HouseholdMember>[]);

  @override
  Future<Result<void>> addMember(String userId) async =>
      const Success(null);

  @override
  Future<Result<JoinHouseholdResult>> joinByInviteCode(String inviteCode) async =>
      const Success(JoinHouseholdResult(householdId: ''));
}

class FakeTransactionsNotifier extends TransactionsNotifier {
  FakeTransactionsNotifier({List<CardTransaction> transactions = const []})
      : _injectedTransactions = transactions,
        super(
          transactionRepository: _FakeTransactionRepository(),
          householdRepository: _FakeHouseholdRepository(),
        );

  final List<CardTransaction> _injectedTransactions;

  @override
  List<CardTransaction> get transactions => _injectedTransactions;

  @override
  bool get hasLoadedTransactions => true;
}

void main() {
  /// Polls [check] until it returns true or a 1-second timeout elapses.
  /// Used to await the completion of `unawaited(...)` callbacks that the
  /// WalletNotifier fires from its listener — deterministic and faster than
  /// a fixed delay.
  Future<void> waitFor(
    bool Function() check, {
    Duration timeout = const Duration(seconds: 1),
    Duration pollInterval = const Duration(milliseconds: 5),
  }) async {
    final sw = Stopwatch()..start();
    while (!check()) {
      if (sw.elapsed > timeout) {
        throw StateError('Timed out after ${sw.elapsed}');
      }
      await Future.delayed(pollInterval);
    }
  }

  late AccountsNotifier accounts;
  late CardCatalogRepository catalog;
  late TransactionsNotifier transactions;
  late WalletNotifier notifier;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});

    final repo = FakeAccountRepository(
      connectionsResult: Success(<PlaidConnection>[
        PlaidConnection(itemId: 'item-chase', institutionName: 'Chase', status: 'connected'),
        PlaidConnection(itemId: 'item-amex', institutionName: 'American Express', status: 'connected'),
        PlaidConnection(itemId: 'item-local', institutionName: 'Some Local Bank', status: 'connected'),
      ]),
      statementCyclesResult: Success(
        StatementCycleSummary(
          status: 'READY',
          total: null,
          currency: null,
          accountCount: 2,
          accounts: <StatementAccount>[
            StatementAccount(
              accountId: 'acct-chase',
              accountName: 'Chase Card',
              mask: '1234',
              itemId: 'item-chase',
              institutionName: 'Chase',
              nextPaymentDueDate: DateTime(2026, 11, 15),
            ),
            StatementAccount(
              accountId: 'acct-amex',
              accountName: 'Amex Card',
              mask: '5678',
              itemId: 'item-amex',
              institutionName: 'American Express',
            ),
          ],
        ),
      ),
    );
    accounts = AccountsNotifier(
      accountRepository: repo,
      linkLauncher: FakePlaidLinkLauncher(),
    );

    final source = FakeCardCatalogSource(<CardCatalogCard>[
      CardCatalogCard(
        id: 'cat-chase',
        name: 'Chase Sapphire Preferred',
        issuer: 'Chase',
        network: 'Visa',
        benefits: <CardBenefit>[
          CardBenefit(id: 'b1', title: 'Travel credit', category: 'Travel'),
          CardBenefit(id: 'b2', title: 'Purchase protection', category: 'Insurance'),
        ],
        signupBonus: CardSignupBonus(
          amount: 60000,
          unit: 'points',
          spendRequired: 4000,
          spendCurrency: 'USD',
          months: 3,
          description: '60k points',
        ),
      ),
      CardCatalogCard(
        id: 'cat-amex',
        name: 'American Express Gold',
        issuer: 'American Express',
        network: 'Visa',
        benefits: <CardBenefit>[
          CardBenefit(id: 'b3', title: 'Dining credit', category: 'Dining'),
        ],
        signupBonus: CardSignupBonus(
          amount: 60000,
          unit: 'points',
          spendRequired: 8000,
          spendCurrency: 'USD',
          months: 3,
          description: '60k points',
        ),
      ),
    ]);
    catalog = CardCatalogRepository(
      store: FakeCacheStore(),
      source: source,
    );

    transactions = FakeTransactionsNotifier();

    notifier = WalletNotifier(
      accounts: accounts,
      catalog: catalog,
      transactions: transactions,
    );
  });

  test('assembles connected cards and matches them to catalog entries', () async {
    await notifier.load();

    expect(notifier.isLoading, isFalse);
    expect(notifier.error, isNull);
    expect(notifier.yourCards.length, 3);

    final chase = notifier.yourCards.firstWhere((c) => c.id == 'acct-chase');
    expect(chase.displayName, 'Chase Sapphire Preferred');
    expect(chase.issuer, 'Chase');
    expect(chase.network, 'Visa');
    expect(chase.lastFour, '1234');
    expect(chase.catalogCard?.id, 'cat-chase');
    expect(chase.benefits.length, 2);
    expect(chase.welcomeBonus?.spendRequiredUnits, 4000);
    expect(chase.welcomeBonus?.progress, 0.0);

    final amex = notifier.yourCards.firstWhere((c) => c.id == 'acct-amex');
    expect(amex.displayName, 'American Express Gold');
    expect(amex.catalogCard?.id, 'cat-amex');
    expect(amex.welcomeBonus?.spendRequiredUnits, 8000);

    final local = notifier.yourCards.firstWhere((c) => c.id == 'item-local');
    expect(local.displayName, 'Some Local Bank');
    expect(local.catalogCard, isNull);
    expect(local.benefits, isEmpty);
    expect(local.welcomeBonus, isNull);
  });

  test('payment due date is surfaced from the statement account', () async {
    await notifier.load();

    final chase =
        notifier.yourCards.firstWhere((c) => c.id == 'acct-chase');
    expect(chase.paymentDueDate, DateTime(2026, 11, 15));
    expect(chase.hasPaymentDue, isTrue);

    final amex = notifier.yourCards.firstWhere((c) => c.id == 'acct-amex');
    expect(amex.paymentDueDate, isNull);
    expect(amex.hasPaymentDue, isFalse);
  });

  test('household cards are empty until backend data exists', () async {
    await notifier.load();
    expect(notifier.householdCards, isEmpty);
  });

  test('toggleBenefit flips usage and notifies', () async {
    await notifier.load();
    final chase = notifier.yourCards.firstWhere((c) => c.id == 'acct-chase');
    expect(chase.benefits.firstWhere((b) => b.id == 'b1').used, isFalse);

    var notifyCount = 0;
    notifier.addListener(() => notifyCount++);

    await notifier.toggleBenefit('acct-chase', 'b1', true);

    final updated = notifier.yourCards.firstWhere((c) => c.id == 'acct-chase');
    expect(updated.benefits.firstWhere((b) => b.id == 'b1').used, isTrue);
    expect(notifyCount, greaterThan(0));
  });

  test('setBonusSpend updates progress and notifies', () async {
    await notifier.load();
    final chase = notifier.yourCards.firstWhere((c) => c.id == 'acct-chase');
    expect(chase.welcomeBonus?.progress, 0.0);

    await notifier.setBonusSpend('acct-chase', 1000);

    final updated = notifier.yourCards.firstWhere((c) => c.id == 'acct-chase');
    expect(updated.welcomeBonus?.spentUnits, 1000);
    expect(updated.welcomeBonus?.progress, 0.25);
  });

  test('persisted benefit usage and bonus spend survive a reload', () async {
    // Seed persisted state for the Chase card before loading.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'wallet.benefit_usage.v1.acct-chase',
      jsonEncode(<String, bool>{'b1': true}),
    );
    await prefs.setString('wallet.bonus_spend.v1.acct-chase', '1000');

    await notifier.load();

    final chase = notifier.yourCards.firstWhere((c) => c.id == 'acct-chase');
    // Benefit 'b1' was marked used in persisted state.
    expect(chase.benefits.firstWhere((b) => b.id == 'b1').used, isTrue);
    // Benefit 'b2' was not persisted, so it stays unused.
    expect(chase.benefits.firstWhere((b) => b.id == 'b2').used, isFalse);
    // Bonus spend was persisted as 1000 of 4000 required = 25%.
    expect(chase.welcomeBonus?.spentUnits, 1000);
    expect(chase.welcomeBonus?.progress, 0.25);
  });

  test('isSyncing mirrors AccountsNotifier during sync', () async {
    final repo = FakeAccountRepository(
      connectionsResult: const Success(<PlaidConnection>[]),
      statementCyclesResult: const Success(StatementCycleSummary(
        status: 'READY',
        total: null,
        currency: null,
        accountCount: 0,
        accounts: [],
      )),
    );
    final accounts = AccountsNotifier(accountRepository: repo, linkLauncher: FakePlaidLinkLauncher());
    final wallet = WalletNotifier(
      accounts: accounts,
      catalog: catalog,
      transactions: FakeTransactionsNotifier(),
    );

    expect(wallet.isSyncing, isFalse);

    final syncFuture = accounts.syncConnections();
    // isSyncing is set synchronously before the first await in syncConnections.
    expect(wallet.isSyncing, isTrue);

    await syncFuture;
    expect(wallet.isSyncing, isFalse);
  });

  test('cards rebuild after sync via the accounts listener without extra repo reads', () async {
    final repo = FakeAccountRepository(
      connectionsResult: const Success(<PlaidConnection>[
        PlaidConnection(itemId: 'item-chase', institutionName: 'Chase', status: 'connected'),
      ]),
      statementCyclesResult: const Success(StatementCycleSummary(
        status: 'READY',
        total: null,
        currency: null,
        accountCount: 1,
        accounts: <StatementAccount>[
          StatementAccount(
            accountId: 'acct-chase',
            accountName: 'Chase Card',
            mask: '1234',
            itemId: 'item-chase',
            institutionName: 'Chase',
          ),
        ],
      )),
    );
    final accounts = AccountsNotifier(accountRepository: repo, linkLauncher: FakePlaidLinkLauncher());
    final wallet = WalletNotifier(
      accounts: accounts,
      catalog: catalog,
      transactions: FakeTransactionsNotifier(),
    );

    await wallet.load();

    final connectionLoadsBefore = repo.connectionLoads;
    final statementCycleLoadsBefore = repo.statementCycleLoads;

    // Sync reloads the accounts notifier which triggers the listener.
    await accounts.syncConnections();

    // The listener should have used _applyAccountsSnapshot (reads only from
    // already-fetched AccountsNotifier state), not load() (which would add 2
    // more repo reads). Only the reloads inside syncConnections should have
    // occurred. _applyAccountsSnapshot does no repo reads, so the counters are
    // final immediately after syncConnections returns.
    expect(repo.connectionLoads, connectionLoadsBefore + 1);
    expect(repo.statementCycleLoads, statementCycleLoadsBefore + 1);
  });

  test('card data does not update mid-sync, only after sync completes', () async {
    final repo = FakeAccountRepository(
      connectionsResult: const Success(<PlaidConnection>[
        PlaidConnection(itemId: 'item-chase', institutionName: 'Chase', status: 'connected'),
      ]),
      statementCyclesResult: const Success(StatementCycleSummary(
        status: 'READY',
        total: null,
        currency: null,
        accountCount: 1,
        accounts: <StatementAccount>[
          StatementAccount(
            accountId: 'acct-chase',
            accountName: 'Chase Card',
            mask: '1234',
            itemId: 'item-chase',
            institutionName: 'Chase',
          ),
        ],
      )),
    );
    final accounts = AccountsNotifier(accountRepository: repo, linkLauncher: FakePlaidLinkLauncher());
    final wallet = WalletNotifier(
      accounts: accounts,
      catalog: catalog,
      transactions: FakeTransactionsNotifier(),
    );

    await wallet.load();
    expect(wallet.yourCards.length, 1);
    expect(wallet.yourCards.first.hasPaymentDue, isFalse);

    // Update statement data with a payment due date.
    repo.statementCyclesResult = Success(StatementCycleSummary(
      status: 'READY',
      total: null,
      currency: null,
      accountCount: 1,
      accounts: <StatementAccount>[
        StatementAccount(
          accountId: 'acct-chase',
          accountName: 'Chase Card',
          mask: '1234',
          itemId: 'item-chase',
          institutionName: 'Chase',
          nextPaymentDueDate: DateTime(2026, 11, 15),
        ),
      ],
    ));

    // Start a gated sync.
    repo.syncGate = Completer<void>();
    final syncFuture = accounts.syncConnections();

    // Sync started: isSyncing is true, card data should not yet reflect the
    // updated statement cycles.
    expect(wallet.isSyncing, isTrue);
    expect(wallet.yourCards.first.hasPaymentDue, isFalse);

    // Release the sync.
    repo.syncGate!.complete();
    await syncFuture;

    // After sync, the listener's _applyAccountsSnapshot updates the card data.
    await waitFor(() => wallet.yourCards.first.hasPaymentDue);
    expect(wallet.yourCards.first.paymentDueDate, DateTime(2026, 11, 15));
  });

  test('load() during sync is deferred and runs when sync completes', () async {
    final repo = FakeAccountRepository(
      connectionsResult: const Success(<PlaidConnection>[
        PlaidConnection(itemId: 'item-chase', institutionName: 'Chase', status: 'connected'),
      ]),
      statementCyclesResult: const Success(StatementCycleSummary(
        status: 'READY',
        total: null,
        currency: null,
        accountCount: 1,
        accounts: <StatementAccount>[
          StatementAccount(
            accountId: 'acct-chase',
            accountName: 'Chase Card',
            mask: '1234',
            itemId: 'item-chase',
            institutionName: 'Chase',
          ),
        ],
      )),
    );
    final accounts = AccountsNotifier(accountRepository: repo, linkLauncher: FakePlaidLinkLauncher());
    final wallet = WalletNotifier(
      accounts: accounts,
      catalog: catalog,
      transactions: FakeTransactionsNotifier(),
    );

    // Start a gated sync.
    repo.syncGate = Completer<void>();
    final syncFuture = accounts.syncConnections();
    expect(wallet.isSyncing, isTrue);

    // Calling load() during sync should be deferred — no repo reads.
    await wallet.load();
    expect(wallet.isLoading, isTrue);
    expect(repo.connectionLoads, 0);
    expect(repo.statementCycleLoads, 0);

    // Release the sync gate.
    repo.syncGate!.complete();
    await syncFuture;

    // The deferred load() (triggered by the listener after sync completes)
    // reassembles cards from the shared AccountsNotifier state that syncConnections
    // already populated. It does not fetch accounts again, so the repo counters
    // stay at 1 (sync reload only).
    await waitFor(() => wallet.yourCards.isNotEmpty);
    expect(repo.connectionLoads, 1);
    expect(repo.statementCycleLoads, 1);
  });

  test('listener is removed on dispose and does not rebuild after sync', () async {
    final repo = FakeAccountRepository(
      connectionsResult: const Success(<PlaidConnection>[
        PlaidConnection(itemId: 'item-chase', institutionName: 'Chase', status: 'connected'),
      ]),
      statementCyclesResult: Success(StatementCycleSummary(
        status: 'READY',
        total: null,
        currency: null,
        accountCount: 1,
        accounts: <StatementAccount>[
          StatementAccount(
            accountId: 'acct-chase',
            accountName: 'Chase Card',
            mask: '1234',
            itemId: 'item-chase',
            institutionName: 'Chase',
            nextPaymentDueDate: DateTime(2026, 11, 15),
          ),
        ],
      )),
    );
    final accounts = AccountsNotifier(accountRepository: repo, linkLauncher: FakePlaidLinkLauncher());
    final wallet = WalletNotifier(
      accounts: accounts,
      catalog: catalog,
      transactions: FakeTransactionsNotifier(),
    );

    await wallet.load();
    expect(wallet.yourCards.length, 1);
    expect(wallet.yourCards.first.hasPaymentDue, isTrue);

    final cardsBefore = wallet.yourCards.length;
    final hasPaymentDueBefore = wallet.yourCards.first.hasPaymentDue;

    wallet.dispose();

    // Change statement data after dispose (clear the payment due date).
    repo.statementCyclesResult = Success(StatementCycleSummary(
      status: 'READY',
      total: null,
      currency: null,
      accountCount: 1,
      accounts: <StatementAccount>[
        StatementAccount(
          accountId: 'acct-chase',
          accountName: 'Chase Card',
          mask: '1234',
          itemId: 'item-chase',
          institutionName: 'Chase',
        ),
      ],
    ));

    // Sync after dispose should not rebuild the wallet notifier.
    await accounts.syncConnections();

    // No listener means no rebuild — the wallet's card data is unchanged.
    expect(wallet.yourCards.length, cardsBefore);
    expect(wallet.yourCards.first.hasPaymentDue, hasPaymentDueBefore);
  });

  group('highestCostTransaction', () {
    late AccountsNotifier accounts;
    late CardCatalogRepository catalog;
    late WalletNotifier notifier;

    setUp(() {
      final repo = FakeAccountRepository(
        connectionsResult: const Success(<PlaidConnection>[]),
        statementCyclesResult: const Success(StatementCycleSummary(
          status: 'WAITING_FOR_STATEMENTS',
          total: null,
          currency: null,
          accountCount: 0,
          accounts: <StatementAccount>[],
        )),
      );
      accounts = AccountsNotifier(
        accountRepository: repo,
        linkLauncher: FakePlaidLinkLauncher(),
      );
      final source = FakeCardCatalogSource(const []);
      catalog = CardCatalogRepository(store: FakeCacheStore(), source: source);
    });

    CardTransaction tx({
      required String id,
      required String amount,
      required String currency,
      required String date,
      String? merchant,
      String? name,
      String? transactionCode,
      bool pending = false,
    }) {
      return CardTransaction(
        id: id,
        accountId: 'acct-1',
        accountName: 'My Card',
        displayName: 'My Card',
        amount: amount,
        currency: currency,
        date: date,
        name: name ?? merchant ?? 'Charge',
        merchant: merchant,
        pending: pending,
        transactionCode: transactionCode,
        assignmentSource: 'default',
      );
    }

    String recentIso(int daysAgo) =>
        DateTime.now().subtract(Duration(days: daysAgo)).toIso8601String().split('T').first;

    test('returns null when transactions list is empty', () {
      final fakeTx = FakeTransactionsNotifier(transactions: const []);
      notifier = WalletNotifier(
        accounts: accounts,
        catalog: catalog,
        transactions: fakeTx,
      );
      expect(notifier.highestCostTransaction, isNull);
    });

    test('returns the largest positive charge', () {
      final fakeTx = FakeTransactionsNotifier(transactions: <CardTransaction>[
        tx(id: 't1', amount: '42.50', currency: 'USD', date: recentIso(5), name: 'Dinner'),
        tx(id: 't2', amount: '128.00', currency: 'USD', date: recentIso(3), name: 'Concert'),
        tx(id: 't3', amount: '12.99', currency: 'USD', date: recentIso(1), name: 'Coffee'),
      ]);
      notifier = WalletNotifier(
        accounts: accounts,
        catalog: catalog,
        transactions: fakeTx,
      );

      final result = notifier.highestCostTransaction;
      expect(result, isNotNull);
      expect(result!.transactionId, 't2');
      expect(result.amountCents, 12800);
      expect(result.currency, 'USD');
      expect(result.name, 'Concert');
    });

    test('ignores negative amounts (payments)', () {
      final fakeTx = FakeTransactionsNotifier(transactions: <CardTransaction>[
        tx(id: 't1', amount: '42.50', currency: 'USD', date: recentIso(5), name: 'Dinner'),
        tx(id: 'pay1', amount: '-500.00', currency: 'USD', date: recentIso(2), name: 'Payment'),
        tx(id: 'pay2', amount: '-1200.00', currency: 'USD', date: recentIso(1), name: 'Big Payment'),
      ]);
      notifier = WalletNotifier(
        accounts: accounts,
        catalog: catalog,
        transactions: fakeTx,
      );

      final result = notifier.highestCostTransaction;
      expect(result, isNotNull);
      expect(result!.transactionId, 't1');
      expect(result.amountCents, 4250);
    });

    test('ignores rows with transaction_code == payment even if amount is positive', () {
      final fakeTx = FakeTransactionsNotifier(transactions: <CardTransaction>[
        tx(id: 't1', amount: '42.50', currency: 'USD', date: recentIso(5), name: 'Dinner'),
        tx(id: 'pay1', amount: '10.00', currency: 'USD', date: recentIso(2), name: 'Payment', transactionCode: 'payment'),
      ]);
      notifier = WalletNotifier(
        accounts: accounts,
        catalog: catalog,
        transactions: fakeTx,
      );

      final result = notifier.highestCostTransaction;
      expect(result, isNotNull);
      expect(result!.transactionId, 't1');
    });

    test('ignores pending transactions', () {
      final fakeTx = FakeTransactionsNotifier(transactions: <CardTransaction>[
        tx(id: 't1', amount: '42.50', currency: 'USD', date: recentIso(5), name: 'Dinner', pending: false),
        tx(id: 'pending1', amount: '9999.99', currency: 'USD', date: recentIso(1), name: 'Pending', pending: true),
      ]);
      notifier = WalletNotifier(
        accounts: accounts,
        catalog: catalog,
        transactions: fakeTx,
      );

      final result = notifier.highestCostTransaction;
      expect(result, isNotNull);
      expect(result!.transactionId, 't1');
    });

    test('ignores transactions older than 30 days', () {
      final fakeTx = FakeTransactionsNotifier(transactions: <CardTransaction>[
        tx(id: 't1', amount: '42.50', currency: 'USD', date: recentIso(5), name: 'Dinner'),
        tx(id: 'old', amount: '5000.00', currency: 'USD', date: recentIso(45), name: 'Old charge'),
      ]);
      notifier = WalletNotifier(
        accounts: accounts,
        catalog: catalog,
        transactions: fakeTx,
      );

      final result = notifier.highestCostTransaction;
      expect(result, isNotNull);
      expect(result!.transactionId, 't1');
    });

    test('ignores transactions with unparseable dates', () {
      final fakeTx = FakeTransactionsNotifier(transactions: <CardTransaction>[
        tx(id: 't1', amount: '42.50', currency: 'USD', date: recentIso(5), name: 'Dinner'),
        tx(id: 'bad', amount: '5000.00', currency: 'USD', date: 'not-a-date', name: 'Bad date'),
      ]);
      notifier = WalletNotifier(
        accounts: accounts,
        catalog: catalog,
        transactions: fakeTx,
      );

      final result = notifier.highestCostTransaction;
      expect(result, isNotNull);
      expect(result!.transactionId, 't1');
    });

    test('ignores zero-amount transactions', () {
      final fakeTx = FakeTransactionsNotifier(transactions: <CardTransaction>[
        tx(id: 't1', amount: '42.50', currency: 'USD', date: recentIso(5), name: 'Dinner'),
        tx(id: 'zero', amount: '0', currency: 'USD', date: recentIso(1), name: 'Zero'),
      ]);
      notifier = WalletNotifier(
        accounts: accounts,
        catalog: catalog,
        transactions: fakeTx,
      );

      final result = notifier.highestCostTransaction;
      expect(result, isNotNull);
      expect(result!.transactionId, 't1');
    });

    test('returns null when only payments/negatives exist', () {
      final fakeTx = FakeTransactionsNotifier(transactions: <CardTransaction>[
        tx(id: 'pay1', amount: '-500.00', currency: 'USD', date: recentIso(2), name: 'Payment'),
        tx(id: 'pay2', amount: '-1200.00', currency: 'USD', date: recentIso(1), name: 'Big Payment'),
      ]);
      notifier = WalletNotifier(
        accounts: accounts,
        catalog: catalog,
        transactions: fakeTx,
      );

      expect(notifier.highestCostTransaction, isNull);
    });

    test('maps all fields correctly', () {
      final fakeTx = FakeTransactionsNotifier(transactions: <CardTransaction>[
        tx(
          id: 'big',
          amount: '250.00',
          currency: 'EUR',
          date: recentIso(3),
          merchant: 'Amazon',
          name: 'Amazon purchase',
        ),
      ]);
      notifier = WalletNotifier(
        accounts: accounts,
        catalog: catalog,
        transactions: fakeTx,
      );

      final result = notifier.highestCostTransaction;
      expect(result, isNotNull);
      expect(result!.transactionId, 'big');
      expect(result.accountId, 'acct-1');
      expect(result.accountName, 'My Card');
      expect(result.amountCents, 25000);
      expect(result.currency, 'EUR');
      expect(result.name, 'Amazon purchase');
      expect(result.merchantName, 'Amazon');
      expect(result.date, isNotNull);
    });

    test('scans the selected date range, so an old month still shows its highest cost', () {
      final old = DateTime.now().subtract(const Duration(days: 60));
      final oldIso = old.toIso8601String().split('T').first;
      final range = DateTimeRange(
        start: DateTime(old.year, old.month, 1),
        end: DateTime(old.year, old.month + 1, 0),
      );

      final fakeTx = FakeTransactionsNotifier(transactions: <CardTransaction>[
        tx(id: 't1', amount: '42.50', currency: 'USD', date: recentIso(5), name: 'Dinner'),
        tx(id: 'old', amount: '5000.00', currency: 'USD', date: oldIso, name: 'Old charge'),
      ]);
      notifier = WalletNotifier(
        accounts: accounts,
        catalog: catalog,
        transactions: fakeTx,
      );

      // Default range is the current month, so the 60-day-old charge is
      // excluded and Dinner wins.
      expect(notifier.highestCostTransaction?.transactionId, 't1');

      // Selecting the old month brings the old charge back into view.
      fakeTx.setDateRange(range);
      expect(notifier.highestCostTransaction?.transactionId, 'old');
      expect(notifier.highestCostTransaction?.amountCents, 500000);
      expect(
        notifier.highestCostWindow,
        '${DateFormat.MMMd().format(range.start)} – ${DateFormat.MMMd().format(range.end)}',
      );
    });
  });
}

class FakeAccountRepository implements AccountRepository {
  FakeAccountRepository({
    this.connectionsResult,
    this.statementCyclesResult,
  });

  Result<List<PlaidConnection>>? connectionsResult;
  Result<StatementCycleSummary>? statementCyclesResult;

  int connectionLoads = 0;
  int statementCycleLoads = 0;
  Completer<void>? syncGate;

  @override
  Future<Result<List<PlaidConnection>>> loadPlaidConnections() async {
    connectionLoads++;
    return connectionsResult ?? const Success(<PlaidConnection>[]);
  }

  @override
  Future<Result<String>> createPlaidLinkToken(String platform) async =>
      const Success('token');

  @override
  Future<Result<String>> createPlaidLinkTokenForItem(String platform, String itemId) async =>
      const Success('token');

  @override
  Future<Result<PlaidSyncOutcome>> syncPlaidConnections() async {
    await syncGate?.future;
    syncGate = null;
    return const Success(PlaidSyncOutcome());
  }

  @override
  Future<Result<PlaidSyncOutcome>> syncPlaidItem(String itemId) async =>
      const Success(PlaidSyncOutcome());

  @override
  Future<Result<PlaidSyncOutcome>> exchangePlaidPublicToken({
    required String publicToken,
    required String? institutionId,
    required String? institutionName,
    required String platform,
  }) async =>
      const Success(PlaidSyncOutcome());

  @override
  Future<Result<void>> updateCreditCardDisplayName(String accountId, String? displayName) async =>
      const Success(null);

  @override
  Future<Result<StatementCycleSummary>> loadStatementCycles() async {
    statementCycleLoads++;
    return statementCyclesResult ??
        const Success(
          StatementCycleSummary(
            status: 'WAITING_FOR_STATEMENTS',
            total: null,
            currency: null,
            accountCount: 0,
            accounts: [],
          ),
        );
  }

  @override
  Future<Result<WalletSummary>> loadWalletSummary() async {
    return const Success(
      WalletSummary(
        cardCount: 0,
        currencies: [],
      ),
    );
  }
}
