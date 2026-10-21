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
}
