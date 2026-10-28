import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cardsemble/features/wallet/domain/wallet_card.dart';
import 'package:cardsemble/features/wallet/domain/benefit_spending.dart';
import 'package:cardsemble/features/wallet/presentation/widgets/wallet_card_panel.dart';
import 'package:cardsemble/features/accounts/domain/entities/account.dart';

void main() {
  group('WalletCardPanel', () {
    WalletCard buildCard({
      int benefitCount = 0,
      StatementAccount? stmtAccount,
      bool needsRelink = false,
    }) {
      final status = needsRelink ? 'error' : 'connected';
      final benefits = List.generate(benefitCount, (i) => WalletBenefit(
            id: 'b$i',
            title: 'Benefit $i',
            category: 'Travel',
          ));
      return WalletCard(
        id: 'card-1',
        displayName: 'Test Card',
        issuer: 'Test Bank',
        network: 'Visa',
        mask: '1234',
        status: status,
        statementAccount: stmtAccount,
        benefits: benefits,
      );
    }

    StatementAccount stmtAccount() => StatementAccount(
          accountId: 'acct-1',
          accountName: 'Card',
          displayName: 'Card',
          mask: '1234',
          itemId: 'item-1',
          currency: 'USD',
        );

    testWidgets('shows Spending toward benefits metric in compact mode',
        (tester) async {
      final card = buildCard(benefitCount: 0);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WalletCardPanel(
              card: card,
              mode: WalletCardPanelMode.collapsed,
              benefitSpending: null,
            ),
          ),
        ),
      );

      expect(find.text('Spending toward benefits'), findsOneWidget);
      expect(find.text('Payment due'), findsNothing);
    });

    testWidgets('shows benefit spending amount when data is available',
        (tester) async {
      final card = buildCard(benefitCount: 2, stmtAccount: stmtAccount());
      final spending = WalletBenefitSpending(
        amountCentsByCurrency: {'USD': 15000},
        transactionCount: 3,
        matchedCategoryKeys: {'travel'},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WalletCardPanel(
              card: card,
              mode: WalletCardPanelMode.collapsed,
              benefitSpending: spending,
            ),
          ),
        ),
      );

      expect(find.text('Spending toward benefits'), findsOneWidget);
      expect(find.text('\$ 150.00'), findsOneWidget);
      expect(find.text('3 matching transactions in the loaded period'), findsOneWidget);
    });

    testWidgets('shows loading state while transactions are loading',
        (tester) async {
      final card = buildCard(benefitCount: 0);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WalletCardPanel(
              card: card,
              mode: WalletCardPanelMode.collapsed,
              benefitSpending: null,
              isTransactionsLoading: true,
            ),
          ),
        ),
      );

      expect(find.text('Loading transactions…'), findsOneWidget);
    });

    testWidgets('compact mode does not overflow with many benefits',
        (tester) async {
      // 11 benefits in compact mode should only show the spending metric and
      // the used summary, not the full progress bars.
      final card = buildCard(benefitCount: 11, stmtAccount: stmtAccount());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WalletCardPanel(
              card: card,
              mode: WalletCardPanelMode.collapsed,
              benefitSpending: null,
            ),
          ),
        ),
      );

      // In compact mode, benefit progress tiles should not be rendered.
      expect(find.byType(LinearProgressIndicator), findsNothing);
      // The used summary should be present.
      expect(find.text('0 of 11 benefits used'), findsOneWidget);
    });

    testWidgets('expandable mode shows benefit progress bars', (tester) async {
      final card = buildCard(benefitCount: 2, stmtAccount: stmtAccount());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WalletCardPanel(
              card: card,
              mode: WalletCardPanelMode.expandable,
              expanded: true,
              benefitSpending: null,
            ),
          ),
        ),
      );

      // In expandable mode, benefit progress bars should be rendered.
      expect(find.byType(LinearProgressIndicator), findsWidgets);
      expect(find.text('Spending toward benefits'), findsOneWidget);
      expect(find.text('Payment due'), findsNothing);
    });
  });
}
