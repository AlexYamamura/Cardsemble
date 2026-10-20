import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cardsemble/features/card_catalog/domain/entities/card_catalog_card.dart';
import 'package:cardsemble/features/card_optimizer/data/card_optimizer_repository.dart';

CardCatalogCard _card({
  required String id,
  required String name,
  String? type,
  String? issuer,
  String? network,
  String? currency,
  String? currencyLabel,
  List<Map<String, dynamic>> categories = const [],
}) {
  return CardCatalogCard(
    id: id,
    name: name,
    issuer: issuer,
    network: network,
    type: type,
    rewards: categories.isNotEmpty
        ? CardRewards(
            currency: currency,
            currencyLabel: currencyLabel,
            categories: categories
                .map((c) => CardRewardCategory(
                      label: c['label'] as String?,
                      pointsPerDollar: c['pointsPerDollar'] as num?,
                      cap: c['cap'],
                    ))
                .toList(growable: false),
          )
        : null,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CardOptimizerRepository', () {
    late CardOptimizerRepository repo;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      repo = CardOptimizerRepository();
    });

    test('rewardTypeFor returns explicit type when points/cash/travel', () {
      final dummy = {'label': 'Dining', 'pointsPerDollar': 1};
      final card = _card(id: '1', name: 'Test', type: 'points', categories: [dummy]);
      expect(repo.rewardTypeFor(card), 'points');

      final card2 = _card(id: '2', name: 'Test2', type: 'CASH', categories: [dummy]);
      expect(repo.rewardTypeFor(card2), 'cash');

      final card3 = _card(id: '3', name: 'Test3', type: 'Travel', categories: [dummy]);
      expect(repo.rewardTypeFor(card3), 'travel');
    });

    test('rewardTypeFor infers from currency/label', () {
      final dummy = {'label': 'Dining', 'pointsPerDollar': 1};
      expect(repo.rewardTypeFor(_card(id: '1', name: 'A', currency: 'cash', categories: [dummy])), 'cash');
      expect(repo.rewardTypeFor(_card(id: '2', name: 'B', currency: 'usd', categories: [dummy])), 'cash');
      expect(repo.rewardTypeFor(_card(id: '3', name: 'C', currency: 'cash_back', categories: [dummy])), 'cash');
      expect(repo.rewardTypeFor(_card(id: '4', name: 'D', currency: 'dollars', categories: [dummy])), 'cash');

      expect(repo.rewardTypeFor(_card(id: '5', name: 'E', currency: 'miles', categories: [dummy])), 'travel');
      expect(repo.rewardTypeFor(_card(id: '6', name: 'F', currency: 'travel', categories: [dummy])), 'travel');
      expect(repo.rewardTypeFor(_card(id: '7', name: 'G', currency: 'airline', categories: [dummy])), 'travel');

      expect(repo.rewardTypeFor(_card(id: '8', name: 'H', currency: 'points', categories: [dummy])), 'points');
      expect(repo.rewardTypeFor(_card(id: '9', name: 'I', currency: 'rewards', categories: [dummy])), 'points');
      expect(repo.rewardTypeFor(_card(id: '10', name: 'J', currency: 'membership_rewards', categories: [dummy])), 'points');
    });

    test('rewardTypeFor falls back to other for credit/charge', () {
      final dummy = {'label': 'Dining', 'pointsPerDollar': 1};
      final card = _card(id: '1', name: 'Test', type: 'credit', categories: [dummy]);
      expect(repo.rewardTypeFor(card), 'other');

      final card2 = _card(id: '2', name: 'Test2', type: 'charge', categories: [dummy]);
      expect(repo.rewardTypeFor(card2), 'other');
    });

    test('categoryKeyFor normalizes common synonyms', () {
      expect(repo.categoryKeyFor('Dining'), 'dining');
      expect(repo.categoryKeyFor('Restaurants'), 'dining');
      expect(repo.categoryKeyFor('Food & Drink'), 'dining');
      expect(repo.categoryKeyFor('Bars'), 'dining');
      expect(repo.categoryKeyFor('Nightlife'), 'dining');

      expect(repo.categoryKeyFor('Groceries'), 'groceries');
      expect(repo.categoryKeyFor('Grocery Stores'), 'groceries');
      expect(repo.categoryKeyFor('Supermarkets'), 'groceries');

      expect(repo.categoryKeyFor('Gas'), 'gas');
      expect(repo.categoryKeyFor('Gas Stations'), 'gas');
      expect(repo.categoryKeyFor('Fuel'), 'gas');
      expect(repo.categoryKeyFor('Petrol'), 'gas');
      expect(repo.categoryKeyFor('EV Charging'), 'gas');

      expect(repo.categoryKeyFor('Travel'), 'travel');
      expect(repo.categoryKeyFor('Hotels'), 'travel');
      expect(repo.categoryKeyFor('Airlines'), 'travel');
      expect(repo.categoryKeyFor('Flights'), 'travel');
      expect(repo.categoryKeyFor('Rideshare'), 'travel');

      expect(repo.categoryKeyFor('Online Shopping'), 'online_retail');
      expect(repo.categoryKeyFor('Amazon'), 'online_retail');

      expect(repo.categoryKeyFor('Drugstores'), 'drugstores');
      expect(repo.categoryKeyFor('Pharmacy'), 'drugstores');

      expect(repo.categoryKeyFor('Streaming'), 'streaming');
      expect(repo.categoryKeyFor('Subscriptions'), 'streaming');

      // Unknown falls back to lowercased label
      expect(repo.categoryKeyFor('Custom Category'), 'custom category');
    });

    test('optimize picks best card per category by effective rate', () {
      final cards = [
        _card(
          id: '1',
          name: 'Premium Card',
          currency: 'points',
          categories: [
            {'label': 'Dining', 'pointsPerDollar': 5},
            {'label': 'Travel', 'pointsPerDollar': 3},
          ],
        ),
        _card(
          id: '2',
          name: 'Basic Card',
          currency: 'points',
          categories: [
            {'label': 'Dining', 'pointsPerDollar': 3},
            {'label': 'Gas', 'pointsPerDollar': 4},
          ],
        ),
      ];

      final results = repo.optimize(cards: cards);

      // Dining: Premium 5x > Basic 3x
      final dining = results.firstWhere((r) => r.categoryKey == 'dining');
      expect(dining.bestCard.name, 'Premium Card');
      expect(dining.effectivePointsPerDollar, 5.0);

      // Travel: Premium 3x (only card)
      final travel = results.firstWhere((r) => r.categoryKey == 'travel');
      expect(travel.bestCard.name, 'Premium Card');

      // Gas: Basic 4x (only card)
      final gas = results.firstWhere((r) => r.categoryKey == 'gas');
      expect(gas.bestCard.name, 'Basic Card');

      // Results sorted by effective rate descending
      expect(results[0].categoryKey, 'dining');
      expect(results[1].categoryKey, 'gas');
      expect(results[2].categoryKey, 'travel');
    });

    test('optimize applies type multipliers', () {
      final cards = [
        _card(
          id: '1',
          name: 'Points Card',
          currency: 'points',
          categories: [{'label': 'Dining', 'pointsPerDollar': 4}],
        ),
        _card(
          id: '2',
          name: 'Cash Card',
          currency: 'cash',
          categories: [{'label': 'Dining', 'pointsPerDollar': 3}],
        ),
      ];

      // Both at 1x: Points 4 > Cash 3
      var results = repo.optimize(cards: cards);
      var dining = results.firstWhere((r) => r.categoryKey == 'dining');
      expect(dining.bestCard.name, 'Points Card');

      // Cash 1.5x: Points 4 vs Cash 4.5
      results = repo.optimize(
        cards: cards,
        typeMultipliers: {'cash': 1.5, 'points': 1.0},
      );
      dining = results.firstWhere((r) => r.categoryKey == 'dining');
      expect(dining.bestCard.name, 'Cash Card');
      expect(dining.effectivePointsPerDollar, 4.5);
    });

    test('optimize skips categories with no/missing points', () {
      final cards = [
        _card(
          id: '1',
          name: 'Card',
          currency: 'points',
          categories: [
            {'label': 'Dining', 'pointsPerDollar': 5},
            {'label': 'Travel', 'pointsPerDollar': 0},
            {'label': 'Gas'}, // no pointsPerDollar
          ],
        ),
      ];

      final results = repo.optimize(cards: cards);
      // Only Dining has positive points
      expect(results.length, 1);
      expect(results[0].categoryKey, 'dining');
    });

    test('optimize handles cap descriptions', () {
      final cards = [
        _card(
          id: '1',
          name: 'Card',
          currency: 'points',
          categories: [
            {'label': 'Dining', 'pointsPerDollar': 5, 'cap': 'up to \$1000/year'},
            {'label': 'Gas', 'pointsPerDollar': 3, 'cap': {'amount': 500, 'currency': 'USD', 'period': 'year'}},
            {'label': 'Groceries', 'pointsPerDollar': 2}, // no cap
          ],
        ),
      ];

      final results = repo.optimize(cards: cards);

      final dining = results.firstWhere((r) => r.categoryKey == 'dining');
      expect(dining.capDescription, 'up to \$1000/year');

      final gas = results.firstWhere((r) => r.categoryKey == 'gas');
      expect(gas.capDescription, 'USD 500 per year');

      final groceries = results.firstWhere((r) => r.categoryKey == 'groceries');
      expect(groceries.isUncapped, true);
      expect(groceries.capDescription, isNull);
    });

    test('tie break: uncapped preferred over capped', () {
      final cards = [
        _card(
          id: '1',
          name: 'Capped Card',
          currency: 'points',
          categories: [
            {'label': 'Dining', 'pointsPerDollar': 5, 'cap': {'amount': 1000}},
          ],
        ),
        _card(
          id: '2',
          name: 'Uncapped Card',
          currency: 'points',
          categories: [
            {'label': 'Dining', 'pointsPerDollar': 5}, // same rate, no cap
          ],
        ),
      ];

      final results = repo.optimize(cards: cards);
      final dining = results.firstWhere((r) => r.categoryKey == 'dining');
      // Uncapped wins tie
      expect(dining.bestCard.name, 'Uncapped Card');
      expect(dining.hasTieBreak, true);
    });

    test('loadTypeMultipliers returns empty map when none saved', () async {
      final multipliers = await repo.loadTypeMultipliers();
      expect(multipliers, isEmpty);
    });

    test('saveTypeMultipliers and loadTypeMultipliers roundtrip', () async {
      await repo.saveTypeMultipliers({'points': 1.5, 'cash': 1.25});
      final loaded = await repo.loadTypeMultipliers();
      expect(loaded['points'], 1.5);
      expect(loaded['cash'], 1.25);
    });

    test('saveTypeMultipliers clamps non-positive values to 1.0', () async {
      await repo.saveTypeMultipliers({'points': -1.0, 'cash': 0.0});
      final loaded = await repo.loadTypeMultipliers();
      expect(loaded['points'], 1.0);
      expect(loaded['cash'], 1.0);
    });

    test('defaultsFor returns 1.0 for observed types', () {
      final cards = [
        _card(id: '1', name: 'A', currency: 'points', categories: [{'label': 'Dining', 'pointsPerDollar': 5}]),
        _card(id: '2', name: 'B', currency: 'cash', categories: [{'label': 'Dining', 'pointsPerDollar': 3}]),
        _card(id: '3', name: 'C', currency: 'points', categories: [{'label': 'Travel', 'pointsPerDollar': 4}]), // duplicate
      ];

      final defaults = repo.defaultsFor(cards);
      expect(defaults['points'], 1.0);
      expect(defaults['cash'], 1.0);
      expect(defaults.length, 2);
    });
  });
}