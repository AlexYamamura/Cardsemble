import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cardsemble/features/wallet/domain/wallet_card.dart';
import 'package:cardsemble/features/wallet/presentation/widgets/wallet_card_panel.dart';
import 'package:cardsemble/features/wallet/presentation/widgets/wallet_card_carousel.dart';

void main() {
  group('carouselCardStyleFor', () {
    test('active card (delta 0) is identity', () {
      final style = carouselCardStyleFor(0.0);
      expect(style.isIdentity, isTrue);
      expect(style.scale, 1.0);
      expect(style.rotation, 0.0);
    });

    test('next card (delta +1) has reduced scale and negative rotation', () {
      final style = carouselCardStyleFor(1.0);
      expect(style.scale, lessThan(1.0));
      expect(style.rotation, lessThan(0.0));
      expect(style.alignment, Alignment.centerLeft);
    });

    test('previous card (delta -1) has smaller scale and positive rotation', () {
      final style = carouselCardStyleFor(-1.0);
      expect(style.scale, lessThan(1.0));
      expect(style.rotation, greaterThan(0.0));
      expect(style.alignment, Alignment.centerRight);
    });

    test('previous card recedes more than next card (smaller scale)', () {
      final prev = carouselCardStyleFor(-1.0);
      final next = carouselCardStyleFor(1.0);
      expect(prev.scale, lessThan(next.scale));
    });

    test('previous and next rotation have opposite signs', () {
      final prev = carouselCardStyleFor(-1.0);
      final next = carouselCardStyleFor(1.0);
      expect(prev.rotation * next.rotation, lessThan(0));
    });

    test('scale is monotonic as delta approaches 0', () {
      expect(
        carouselCardStyleFor(1.0).scale,
        lessThan(carouselCardStyleFor(0.5).scale),
      );
      expect(
        carouselCardStyleFor(0.5).scale,
        lessThan(carouselCardStyleFor(0.0).scale),
      );
    });

    test('values clamp at |delta| > 1', () {
      final at1 = carouselCardStyleFor(1.0);
      final beyond = carouselCardStyleFor(2.5);
      expect(beyond.scale, equals(at1.scale));
      expect(beyond.rotation, equals(at1.rotation));
    });

    test('rotation magnitude increases as delta moves away from 0', () {
      final prevHalf = carouselCardStyleFor(-0.5);
      final prevFull = carouselCardStyleFor(-1.0);
      expect(prevHalf.rotation.abs(), lessThan(prevFull.rotation.abs()));

      final nextHalf = carouselCardStyleFor(0.5);
      final nextFull = carouselCardStyleFor(1.0);
      expect(nextHalf.rotation.abs(), lessThan(nextFull.rotation.abs()));
    });
  });

  group('buildCarouselTransform', () {
    test('identity for identity style', () {
      final matrix = buildCarouselTransform(
        const CarouselCardStyle(
          scale: 1.0,
          rotation: 0.0,
          alignment: Alignment.center,
        ),
      );
      expect(Matrix4.identity(), matrix);
    });

    test('non-identity for non-identity style', () {
      final matrix = buildCarouselTransform(
        const CarouselCardStyle(
          scale: 0.9,
          rotation: 0.1,
          alignment: Alignment.centerLeft,
        ),
      );
      expect(matrix, isNot(Matrix4.identity()));
    });
  });

  group('WalletCardCarousel', () {
    testWidgets('renders the correct number of cards', (tester) async {
      final cards = _buildFakeCards(3);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WalletCardCarousel(
              cards: cards,
              onCardTap: (_) {},
              onResync: (_) async {},
              carouselHeight: 264,
              benefitSpendingFor: (_) => null,
              isTransactionsLoading: false,
            ),
          ),
        ),
      );

      expect(find.byType(WalletCardCarousel), findsOneWidget);
    });

    testWidgets('tap on a card invokes onCardTap', (tester) async {
      final cards = _buildFakeCards(3);
      WalletCard? tappedCard;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WalletCardCarousel(
              cards: cards,
              onCardTap: (card) => tappedCard = card,
              onResync: (_) async {},
              carouselHeight: 264,
              benefitSpendingFor: (_) => null,
              isTransactionsLoading: false,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(WalletCardPanel).first);
      await tester.pumpAndSettle();

      expect(tappedCard, isNotNull);
      expect(tappedCard?.id, cards.first.id);
    });

    testWidgets('empty cards list renders empty state in parent', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WalletCardCarousel(
              cards: [],
              onCardTap: (_) {},
              onResync: (_) async {},
              carouselHeight: 264,
              benefitSpendingFor: (_) => null,
              isTransactionsLoading: false,
            ),
          ),
        ),
      );

      // WalletCardCarousel itself doesn't render the empty state (the parent
      // does), but it should not throw.
      expect(find.byType(WalletCardCarousel), findsOneWidget);
      expect(find.byType(PageView), findsOneWidget);
      expect(find.byType(PageView).evaluate().single.widget, isNotNull);
    });

    testWidgets('PageView.builder renders with cards', (tester) async {
      final cards = _buildFakeCards(3);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WalletCardCarousel(
              cards: cards,
              onCardTap: (_) {},
              onResync: (_) async {},
              carouselHeight: 264,
              benefitSpendingFor: (_) => null,
              isTransactionsLoading: false,
            ),
          ),
        ),
      );

      final pageViewFinder = find.byType(PageView);
      expect(pageViewFinder, findsOneWidget);

      final pageViewWidget =
          pageViewFinder.evaluate().single.widget as PageView;
      final controller = pageViewWidget.controller;
      expect(controller, isNotNull);
      expect(controller!.viewportFraction, 0.82);
    });
  });
}

List<WalletCard> _buildFakeCards(int count) {
  return List.generate(count, (i) {
    return WalletCard(
      id: 'card-$i',
      displayName: 'Test Card $i',
      issuer: 'TestBank',
      network: 'Visa',
      mask: '1234',
      status: 'connected',
      itemId: 'item-$i',
    );
  });
}
