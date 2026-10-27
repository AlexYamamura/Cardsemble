import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cardsemble/core/core.dart';
import 'package:cardsemble/features/accounts/domain/accounts_domain.dart';
import 'package:cardsemble/features/accounts/presentation/accounts_notifier.dart';
import 'package:cardsemble/features/card_catalog/data/card_catalog_repository.dart';
import 'package:cardsemble/features/card_catalog/domain/card_catalog_source.dart';
import 'package:cardsemble/features/card_catalog/domain/entities/card_catalog_card.dart';
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

void main() {
  late AccountsNotifier accounts;
  late CardCatalogRepository catalog;
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

    notifier = WalletNotifier(accounts: accounts, catalog: catalog);
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
      walletSummaryResult: const Success(WalletSummary(cardCount: 0, currencies: [])),
    );
    final accounts = AccountsNotifier(accountRepository: repo, linkLauncher: FakePlaidLinkLauncher());
    final wallet = WalletNotifier(accounts: accounts, catalog: catalog);

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
      walletSummaryResult: const Success(WalletSummary(cardCount: 1, currencies: [])),
    );
    final accounts = AccountsNotifier(accountRepository: repo, linkLauncher: FakePlaidLinkLauncher());
    final wallet = WalletNotifier(accounts: accounts, catalog: catalog);

    await wallet.load();
    final chase = wallet.yourCards.firstWhere((c) => c.id == 'acct-chase');
    expect(chase.balanceCents, isNull);
    expect(chase.creditLimitCents, isNull);

    final connectionLoadsBefore = repo.connectionLoads;
    final statementCycleLoadsBefore = repo.statementCycleLoads;
    final walletSummaryLoadsBefore = repo.walletSummaryLoads;

    // Update the statement data with balance/limit info.
    repo.statementCyclesResult = const Success(StatementCycleSummary(
      status: 'READY',
      total: null,
      currency: 'USD',
      accountCount: 1,
      accounts: <StatementAccount>[
        StatementAccount(
          accountId: 'acct-chase',
          accountName: 'Chase Card',
          mask: '1234',
          itemId: 'item-chase',
          institutionName: 'Chase',
          creditLimitCents: 50000,
          currentBalanceCents: 1234,
          currency: 'USD',
        ),
      ],
    ));

    await accounts.syncConnections();
    // Let the unawaited _applyAccountsSnapshot() from the listener complete.
    await Future.delayed(const Duration(milliseconds: 100));

    final updatedChase = wallet.yourCards.firstWhere((c) => c.id == 'acct-chase');
    expect(updatedChase.balanceCents, 1234);
    expect(updatedChase.creditLimitCents, 50000);
    expect(updatedChase.currency, 'USD');

    // The listener should have used _applyAccountsSnapshot (reads only from
    // already-fetched AccountsNotifier state), not load() (which would add 3
    // more repo reads). Only the 3 reloads inside syncConnections should have
    // occurred.
    expect(repo.connectionLoads, connectionLoadsBefore + 1);
    expect(repo.statementCycleLoads, statementCycleLoadsBefore + 1);
    expect(repo.walletSummaryLoads, walletSummaryLoadsBefore + 1);
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
      walletSummaryResult: const Success(WalletSummary(cardCount: 1, currencies: [])),
    );
    final accounts = AccountsNotifier(accountRepository: repo, linkLauncher: FakePlaidLinkLauncher());
    final wallet = WalletNotifier(accounts: accounts, catalog: catalog);

    await wallet.load();

    expect(wallet.yourCards.firstWhere((c) => c.id == 'acct-chase').balanceCents, isNull);

    // Update the statement data with new balance info.
    repo.statementCyclesResult = const Success(StatementCycleSummary(
      status: 'READY',
      total: null,
      currency: 'USD',
      accountCount: 1,
      accounts: <StatementAccount>[
        StatementAccount(
          accountId: 'acct-chase',
          accountName: 'Chase Card',
          mask: '1234',
          itemId: 'item-chase',
          institutionName: 'Chase',
          creditLimitCents: 50000,
          currentBalanceCents: 9999,
          currency: 'USD',
        ),
      ],
    ));

    // Start a gated sync.
    repo.syncGate = Completer<void>();
    final syncFuture = accounts.syncConnections();

    // Sync started: isSyncing is true.
    expect(wallet.isSyncing, isTrue);

    // Mid-sync: data should not yet reflect the updated statement.
    expect(wallet.yourCards.firstWhere((c) => c.id == 'acct-chase').balanceCents, isNull);

    // Release the sync.
    repo.syncGate!.complete();
    await syncFuture;
    await Future.delayed(const Duration(milliseconds: 100));

    final chase = wallet.yourCards.firstWhere((c) => c.id == 'acct-chase');
    expect(chase.balanceCents, 9999);
    expect(chase.creditLimitCents, 50000);
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
      walletSummaryResult: const Success(WalletSummary(cardCount: 1, currencies: [])),
    );
    final accounts = AccountsNotifier(accountRepository: repo, linkLauncher: FakePlaidLinkLauncher());
    final wallet = WalletNotifier(accounts: accounts, catalog: catalog);

    // Start a gated sync.
    repo.syncGate = Completer<void>();
    final syncFuture = accounts.syncConnections();
    expect(wallet.isSyncing, isTrue);

    // Calling load() during sync should be deferred — no repo reads.
    await wallet.load();
    expect(wallet.isLoading, isTrue);
    expect(repo.connectionLoads, 0);
    expect(repo.statementCycleLoads, 0);
    expect(repo.walletSummaryLoads, 0);

    // Release the sync gate.
    repo.syncGate!.complete();
    await syncFuture;

    // Let the deferred load() (triggered by the listener) complete.
    await Future.delayed(const Duration(milliseconds: 100));

    // The deferred load should have run: each counter went from 1 (sync reload)
    // to 2 (sync reload + deferred load).
    expect(repo.connectionLoads, greaterThan(1));
    expect(repo.statementCycleLoads, greaterThan(1));
    expect(repo.walletSummaryLoads, greaterThan(1));
  });

  test('listener is removed on dispose and does not rebuild after sync', () async {
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
      walletSummaryResult: const Success(WalletSummary(cardCount: 1, currencies: [])),
    );
    final accounts = AccountsNotifier(accountRepository: repo, linkLauncher: FakePlaidLinkLauncher());
    final wallet = WalletNotifier(accounts: accounts, catalog: catalog);

    await wallet.load();
    expect(wallet.yourCards.firstWhere((c) => c.id == 'acct-chase').balanceCents, isNull);

    final lastUpdatedBefore = wallet.lastUpdated;

    wallet.dispose();

    // Update statement data with balance info.
    repo.statementCyclesResult = const Success(StatementCycleSummary(
      status: 'READY',
      total: null,
      currency: 'USD',
      accountCount: 1,
      accounts: <StatementAccount>[
        StatementAccount(
          accountId: 'acct-chase',
          accountName: 'Chase Card',
          mask: '1234',
          itemId: 'item-chase',
          institutionName: 'Chase',
          creditLimitCents: 50000,
          currentBalanceCents: 555,
          currency: 'USD',
        ),
      ],
    ));

    await accounts.syncConnections();
    await Future.delayed(const Duration(milliseconds: 100));

    // No rebuild should have occurred after dispose.
    expect(wallet.lastUpdated, lastUpdatedBefore);
    expect(wallet.yourCards.firstWhere((c) => c.id == 'acct-chase').balanceCents, isNull);
  });
}

class FakeAccountRepository implements AccountRepository {
  FakeAccountRepository({
    this.connectionsResult,
    this.statementCyclesResult,
    this.walletSummaryResult,
  });

  Result<List<PlaidConnection>>? connectionsResult;
  Result<StatementCycleSummary>? statementCyclesResult;
  Result<WalletSummary>? walletSummaryResult;

  int connectionLoads = 0;
  int statementCycleLoads = 0;
  int walletSummaryLoads = 0;
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
    walletSummaryLoads++;
    return walletSummaryResult ??
        const Success(
          WalletSummary(
            cardCount: 0,
            currencies: [],
          ),
        );
  }
}
