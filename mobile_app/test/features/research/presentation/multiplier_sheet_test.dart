import 'package:cardsemble/features/card_catalog/domain/entities/card_catalog_card.dart';
import 'package:cardsemble/features/card_optimizer/data/card_optimizer_repository.dart';
import 'package:cardsemble/features/research/presentation/research_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

CardCatalogCard _pointsCard({
  String id = 'us-amex-blue-business-plus',
  String name = 'Blue Business Plus Credit Card from American Express',
  String issuer = 'American Express',
  String currency = 'membership_rewards',
}) {
  return CardCatalogCard.fromJson({
    'id': id,
    'name': name,
    'type': 'credit',
    'issuer': issuer,
    'rewards': {
      'currency': currency,
      'categories': [
        {'label': 'Dining', 'points_per_dollar': 4},
      ],
    },
  });
}

CardCatalogCard _cashCard() {
  return CardCatalogCard.fromJson({
    'id': 'us-amex-blue-cash-everyday',
    'name': 'Blue Cash Everyday Card',
    'type': 'credit',
    'issuer': 'American Express',
    'rewards': {
      'currency': 'reward_dollars',
      'categories': [
        {'label': 'Dining', 'points_per_dollar': 3},
      ],
    },
  });
}

/// Opens the multiplier sheet and captures the map it returns on Save.
Future<Map<String, double>?> _openSheet(
  WidgetTester tester,
  List<CardCatalogCard> cards, {
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final repository = CardOptimizerRepository();
  Map<String, double>? saved;

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              saved = await showCardOptimizerSettings(
                context: context,
                repository: repository,
                cards: cards,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return saved;
}

/// Labels rendered above the multiplier inputs, in display order.
List<String> _labels(WidgetTester tester) {
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data)
      .whereType<String>()
      .where((d) => d.contains('multiplier'))
      .where((d) => !d.startsWith('Set a default points multiplier'))
      .toList(growable: false);
}

int _fieldCount(WidgetTester tester) =>
    tester.widgetList(find.byType(TextFormField)).length;

Future<void> _setField(WidgetTester tester, int index, String value) async {
  final field = find.byType(TextFormField).at(index);
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, value);
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  final save = find.widgetWithText(FilledButton, 'Save');
  await tester.ensureVisible(save);
  await tester.pumpAndSettle();
  await tester.tap(save);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows an instruction instead of a points input when no cards '
      'are selected', (
    tester,
  ) async {
    await _openSheet(tester, const []);

    expect(
      find.text(
        'Select a points based credit card to set a points multiplier.',
      ),
      findsOneWidget,
    );
    expect(_labels(tester), isNot(contains('Points multiplier (default)')));
    expect(_fieldCount(tester), 0);
  });

  testWidgets('shows an instruction instead of a points input when only cash '
      'cards are selected', (
    tester,
  ) async {
    await _openSheet(tester, [_cashCard()]);

    expect(
      find.text(
        'Select a points based credit card to set a points multiplier.',
      ),
      findsOneWidget,
    );
    expect(_labels(tester), isNot(contains('Points multiplier (default)')));
    expect(_labels(tester), isNot(contains('Cash multiplier')));
    expect(_fieldCount(tester), 0);
  });

  testWidgets('replaces the instruction with the default points input once a '
      'points card is selected', (
    tester,
  ) async {
    await _openSheet(tester, [_pointsCard()]);

    expect(
      find.text(
        'Select a points based credit card to set a points multiplier.',
      ),
      findsNothing,
    );
    expect(_labels(tester), contains('Points multiplier (default)'));
    expect(_labels(tester), contains('American Express points multiplier'));
    expect(_labels(tester), isNot(contains('Cash multiplier')));
  });

  testWidgets('keeps a stored default points value when the sheet is opened '
      'without a points card', (
    tester,
  ) async {
    Map<String, double>? saved;
    SharedPreferences.setMockInitialValues({
      'card_optimizer.type_multipliers.v1': '{"points":1.75}',
    });
    final repository = CardOptimizerRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                saved = await showCardOptimizerSettings(
                  context: context,
                  repository: repository,
                  cards: [_cashCard()],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await _save(tester);

    // The hidden default is preserved and cash is never stored.
    expect(saved!['points'], 1.75);
    expect(saved!.containsKey('cash'), isFalse);
  });

  testWidgets('orders issuer inputs alphabetically after the default', (
    tester,
  ) async {
    await _openSheet(tester, [
      _pointsCard(
        id: 'chase-card',
        name: 'Chase Card',
        issuer: 'Chase',
        currency: 'ultimate_rewards',
      ),
      _pointsCard(),
    ]);

    expect(_labels(tester), [
      'Points multiplier (default)',
      'American Express points multiplier',
      'Chase points multiplier',
    ]);
  });

  testWidgets('prefills the stored default points value', (tester) async {
    await _openSheet(
      tester,
      [_pointsCard()],
      prefs: {'card_optimizer.type_multipliers.v1': '{"points":1.50}'},
    );

    final field = tester.widget<TextFormField>(
      find.byType(TextFormField).first,
    );
    expect(field.controller!.text, '1.50');
  });

  testWidgets('saves the default points value and leaves untouched issuers '
      'on the default', (tester) async {
    Map<String, double>? saved;
    SharedPreferences.setMockInitialValues({});
    final repository = CardOptimizerRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                saved = await showCardOptimizerSettings(
                  context: context,
                  repository: repository,
                  cards: [_pointsCard()],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await _setField(tester, 0, '2.00');
    await _save(tester);

    expect(saved, isNotNull);
    expect(saved!['points'], 2.0);
    // The issuer field was not edited, so it inherits the default instead of
    // storing an override.
    expect(saved!.containsKey('points:American Express'), isFalse);
  });

  testWidgets('stores an issuer override when the issuer field is edited', (
    tester,
  ) async {
    Map<String, double>? saved;
    SharedPreferences.setMockInitialValues({});
    final repository = CardOptimizerRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                saved = await showCardOptimizerSettings(
                  context: context,
                  repository: repository,
                  cards: [_pointsCard()],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await _setField(tester, 1, '3.00');
    await _save(tester);

    expect(saved!['points:American Express'], 3.0);
    expect(saved!['points'], 1.0);
  });

  testWidgets('keeps stored multipliers that are not currently displayed', (
    tester,
  ) async {
    Map<String, double>? saved;
    SharedPreferences.setMockInitialValues({
      'card_optimizer.type_multipliers.v1':
          '{"points":1.5,"points:Chase":2.0,"travel":1.2,"cash":3.0}',
    });
    final repository = CardOptimizerRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                saved = await showCardOptimizerSettings(
                  context: context,
                  repository: repository,
                  cards: [_pointsCard()],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await _setField(tester, 0, '1.25');
    await _save(tester);

    expect(saved!['points'], 1.25);
    // Hidden issuer override for an issuer that is not selected.
    expect(saved!['points:Chase'], 2.0);
    expect(saved!['travel'], 1.2);
    // Cash multipliers are never stored.
    expect(saved!.containsKey('cash'), isFalse);
  });

  testWidgets('rejects an invalid value without closing the sheet', (
    tester,
  ) async {
    Map<String, double>? saved;
    SharedPreferences.setMockInitialValues({});
    final repository = CardOptimizerRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                saved = await showCardOptimizerSettings(
                  context: context,
                  repository: repository,
                  cards: [_pointsCard()],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await _setField(tester, 0, '');
    await _save(tester);

    expect(saved, isNull);
    expect(find.text('Point Multipliers'), findsOneWidget);
  });
}
