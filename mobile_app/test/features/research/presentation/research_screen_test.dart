import 'package:cardsemble/core/core.dart';
import 'package:cardsemble/features/card_catalog/data/card_catalog_repository.dart';
import 'package:cardsemble/features/card_catalog/domain/card_catalog_source.dart';
import 'package:cardsemble/features/card_catalog/domain/entities/card_catalog_card.dart';
import 'package:cardsemble/features/research/presentation/research_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../core/cache/fake_cache_store.dart';

class _FakeSource implements CardCatalogSource {
  _FakeSource(this.cards);

  final List<CardCatalogCard> cards;

  @override
  Future<Result<List<CardCatalogCard>>> fetchCards(Set<String> ids) async {
    return Success(
      cards.where((card) => ids.contains(card.id)).toList(growable: false),
    );
  }

  @override
  Future<Result<List<CardCatalogCard>>> fetchAllCards() async => Success(cards);
}

void main() {
  testWidgets('search results with the keyboard open do not overflow', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 780);
    addTearDown(tester.view.reset);

    final repository = CardCatalogRepository(
      store: FakeCacheStore(),
      source: _FakeSource([
        const CardCatalogCard(
          id: 'amex-gold',
          name: 'Amex Gold',
          issuer: 'American Express',
        ),
        const CardCatalogCard(
          id: 'chase-sapphire',
          name: 'Chase Sapphire',
          issuer: 'Chase',
        ),
      ]),
    );

    await tester.pumpWidget(
      Provider<CardCatalogRepository>.value(
        value: repository,
        child: const MaterialApp(home: ResearchScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Simulate the on-screen keyboard shrinking the viewport, then search so
    // the result dropdown is visible.
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'amex');
    await tester.pumpAndSettle();

    expect(find.text('Amex Gold'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('card details show the base earn rate above the category rates', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 780);
    addTearDown(tester.view.reset);

    final repository = CardCatalogRepository(
      store: FakeCacheStore(),
      source: _FakeSource([
        const CardCatalogCard(
          id: 'chase-sapphire',
          name: 'Chase Sapphire',
          issuer: 'Chase',
          rewards: CardRewards(
            currency: 'ultimate_rewards',
            baseRate: CardRewardRate(
              pointsPerDollar: 1,
              description: '1x on other purchases',
            ),
            categories: [
              CardRewardCategory(label: 'Dining', pointsPerDollar: 3),
            ],
          ),
        ),
      ]),
    );

    await tester.pumpWidget(
      Provider<CardCatalogRepository>.value(
        value: repository,
        child: const MaterialApp(home: ResearchScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Select the card from the search dropdown.
    await tester.enterText(find.byType(TextField), 'sapphire');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chase Sapphire').first);
    await tester.pumpAndSettle();

    // Open the detail sheet from the selected-cards table.
    await tester.tap(find.text('Chase Sapphire').first);
    await tester.pumpAndSettle();

    expect(find.text('Base earn rate'), findsOneWidget);
    expect(find.text('1.0x'), findsOneWidget);
    expect(find.text('1x on other purchases'), findsOneWidget);
    // The elevated category rate is still shown.
    expect(find.text('3.0x'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('card details show a base earn description without a rate', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 780);
    addTearDown(tester.view.reset);

    final repository = CardCatalogRepository(
      store: FakeCacheStore(),
      source: _FakeSource([
        const CardCatalogCard(
          id: 'shield-visa',
          name: 'Shield Visa',
          issuer: 'US Bank',
          rewards: CardRewards(
            currency: 'usd',
            baseRate: CardRewardRate(
              description: 'No base earn rate stated. Only category earn.',
            ),
            categories: [
              CardRewardCategory(label: 'Cash back', pointsPerDollar: 4),
            ],
          ),
        ),
      ]),
    );

    await tester.pumpWidget(
      Provider<CardCatalogRepository>.value(
        value: repository,
        child: const MaterialApp(home: ResearchScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'shield');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shield Visa').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Shield Visa').first);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Base earn rate: No base earn rate stated. Only category earn.',
      ),
      findsOneWidget,
    );
    // No rate value is rendered when the catalog has no numeric base rate.
    expect(find.text('Base earn rate'), findsNothing);
    expect(find.text('4.0x'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
