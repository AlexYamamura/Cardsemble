import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cardsemble/core/core.dart';
import 'package:cardsemble/features/accounts/domain/accounts_domain.dart';
import 'package:cardsemble/features/accounts/presentation/accounts_notifier.dart';
import 'package:cardsemble/features/card_catalog/data/card_catalog_repository.dart';
import 'package:cardsemble/features/card_catalog/domain/entities/card_catalog_card.dart';
import 'package:cardsemble/features/transactions/presentation/transactions_notifier.dart';
import 'package:cardsemble/features/wallet/presentation/wallet_notifier.dart';
import 'package:cardsemble/features/wallet/presentation/wallet_screen.dart';
import 'package:cardsemble/features/wallet/presentation/widgets/wallet_card_panel.dart';
import '../../../core/cache/fake_cache_store.dart';
import 'wallet_notifier_test.dart';

void main() {
  group('WalletScreen', () {
    late AccountsNotifier accounts;
    late CardCatalogRepository catalog;
    late TransactionsNotifier transactions;
    late WalletNotifier walletNotifier;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final repo = FakeAccountRepository(
        connectionsResult: const Success(<PlaidConnection>[]),
        statementCyclesResult: const Success(StatementCycleSummary(
          status: 'WAITING_FOR_STATEMENTS',
          total: null,
          currency: null,
          accountCount: 0,
          accounts: [],
        )),
      );
      accounts = AccountsNotifier(
        accountRepository: repo,
        linkLauncher: FakePlaidLinkLauncher(),
      );
      catalog = CardCatalogRepository(
        store: FakeCacheStore(),
        source: FakeCardCatalogSource(const []),
      );
      transactions = FakeTransactionsNotifier();
      walletNotifier = WalletNotifier(
        accounts: accounts,
        catalog: catalog,
        transactions: transactions,
      );
    });

    testWidgets('shows empty state while cards are empty', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<AccountsNotifier>.value(value: accounts),
              ChangeNotifierProvider<WalletNotifier>.value(value: walletNotifier),
              ChangeNotifierProvider<TransactionsNotifier>.value(
                  value: transactions),
            ],
            child: const Scaffold(body: WalletScreen()),
          ),
        ),
      );

      // When no cards are loaded (synchronously in tests), the empty state
      // should be shown instead of the waiting view.
      expect(find.text('No cards in your wallet yet'), findsOneWidget);
      // Payment due should never appear.
      expect(find.text('Payment due'), findsNothing);
      // Spending toward benefits appears in card panels when cards are present,
      // not in the empty state.
      expect(find.text('Spending toward benefits'), findsNothing);
    });

    testWidgets('shows Spending toward benefits metric after cards load',
        (tester) async {
      final repo2 = FakeAccountRepository(
        connectionsResult: Success(<PlaidConnection>[
          PlaidConnection(itemId: 'item-1', institutionName: 'Chase', status: 'connected'),
        ]),
        statementCyclesResult: Success(StatementCycleSummary(
          status: 'READY',
          total: null,
          currency: null,
          accountCount: 1,
          accounts: <StatementAccount>[
            StatementAccount(
              accountId: 'acct-1',
              accountName: 'Chase Card',
              displayName: 'Chase Sapphire Preferred',
              mask: '1234',
              itemId: 'item-1',
              institutionName: 'Chase',
            ),
          ],
        )),
      );
      final accounts2 = AccountsNotifier(
        accountRepository: repo2,
        linkLauncher: FakePlaidLinkLauncher(),
      );
      final source = FakeCardCatalogSource(<CardCatalogCard>[
        CardCatalogCard(
          id: 'cat-1',
          name: 'Chase Sapphire Preferred',
          issuer: 'Chase',
          network: 'Visa',
        ),
      ]);
      final catalog2 = CardCatalogRepository(
        store: FakeCacheStore(),
        source: source,
      );
      final wallet2 = WalletNotifier(
        accounts: accounts2,
        catalog: catalog2,
        transactions: transactions,
      );

      await wallet2.load();

      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<AccountsNotifier>.value(value: accounts2),
              ChangeNotifierProvider<WalletNotifier>.value(value: wallet2),
              ChangeNotifierProvider<TransactionsNotifier>.value(
                  value: transactions),
            ],
            child: const Scaffold(body: WalletScreen()),
          ),
        ),
      );

      // The summary card should use Column (no GridView).
      expect(find.byType(GridView), findsNothing);
      expect(find.text('Number of cards:'), findsOneWidget);
      expect(find.text('Highest cost:'), findsOneWidget);
      // Payment due should no longer exist.
      expect(find.text('Payment due'), findsNothing);
      // Spending toward benefits metric should exist in card panels.
      expect(find.text('Spending toward benefits'), findsWidgets);
    });

    testWidgets('does not show Payment due text anywhere', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<AccountsNotifier>.value(value: accounts),
              ChangeNotifierProvider<WalletNotifier>.value(value: walletNotifier),
              ChangeNotifierProvider<TransactionsNotifier>.value(
                  value: transactions),
            ],
            child: const Scaffold(body: WalletScreen()),
          ),
        ),
      );

      expect(find.text('Payment due'), findsNothing);
    });

    testWidgets('summary uses Column layout, not GridView', (tester) async {
      // Verify the _WalletSummaryCard renders a Column (checked via the
      // Number of cards and Highest cost metrics being in a Column,
      // not a GridView).
      final repo3 = FakeAccountRepository(
        connectionsResult: Success(<PlaidConnection>[
          PlaidConnection(itemId: 'item-1', institutionName: 'Chase', status: 'connected'),
        ]),
        statementCyclesResult: Success(StatementCycleSummary(
          status: 'READY',
          total: null,
          currency: null,
          accountCount: 1,
          accounts: <StatementAccount>[
            StatementAccount(
              accountId: 'acct-1',
              accountName: 'Chase Card',
              displayName: 'Chase Sapphire Preferred',
              mask: '1234',
              itemId: 'item-1',
              institutionName: 'Chase',
            ),
          ],
        )),
      );
      final accounts3 = AccountsNotifier(
        accountRepository: repo3,
        linkLauncher: FakePlaidLinkLauncher(),
      );
      final source = FakeCardCatalogSource(<CardCatalogCard>[
        CardCatalogCard(
          id: 'cat-1',
          name: 'Chase Sapphire Preferred',
          issuer: 'Chase',
          network: 'Visa',
        ),
      ]);
      final catalog3 = CardCatalogRepository(
        store: FakeCacheStore(),
        source: source,
      );
      final wallet3 = WalletNotifier(
        accounts: accounts3,
        catalog: catalog3,
        transactions: transactions,
      );

      await wallet3.load();

      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<AccountsNotifier>.value(value: accounts3),
              ChangeNotifierProvider<WalletNotifier>.value(value: wallet3),
              ChangeNotifierProvider<TransactionsNotifier>.value(
                  value: transactions),
            ],
            child: const Scaffold(body: WalletScreen()),
          ),
        ),
      );

      expect(find.byType(GridView), findsNothing);
      expect(find.byType(WalletCardPanel), findsWidgets);
    });
  });
}
