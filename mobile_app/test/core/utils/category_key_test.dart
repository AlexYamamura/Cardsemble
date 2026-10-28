import 'package:flutter_test/flutter_test.dart';

import 'package:cardsemble/core/utils/category_key.dart';

void main() {
  group('normalizeCategoryKey', () {
    test('maps common synonyms to canonical keys', () {
      expect(normalizeCategoryKey('Dining'), 'dining');
      expect(normalizeCategoryKey('Restaurants'), 'dining');
      expect(normalizeCategoryKey('Food'), 'dining');
      expect(normalizeCategoryKey('Groceries'), 'groceries');
      expect(normalizeCategoryKey('Grocery Stores'), 'groceries');
      expect(normalizeCategoryKey('Gas'), 'gas');
      expect(normalizeCategoryKey('Fuel'), 'gas');
      expect(normalizeCategoryKey('Travel'), 'travel');
      expect(normalizeCategoryKey('Hotels'), 'travel');
      expect(normalizeCategoryKey('Shopping'), 'online_retail');
      expect(normalizeCategoryKey('Amazon'), 'online_retail');
      expect(normalizeCategoryKey('Pharmacy'), 'drugstores');
      expect(normalizeCategoryKey('Streaming'), 'streaming');
      expect(normalizeCategoryKey('Transit'), 'transit');
      expect(normalizeCategoryKey('Parking'), 'transit');
      expect(normalizeCategoryKey('Entertainment'), 'entertainment');
      expect(normalizeCategoryKey('Movies'), 'entertainment');
    });

    test('falls back to lowercased label for unknown categories', () {
      expect(normalizeCategoryKey('Some Weird Category'), 'some weird category');
    });

    test('handles empty string', () {
      expect(normalizeCategoryKey(''), 'other');
      expect(normalizeCategoryKey('  '), 'other');
    });

    test('is case-insensitive and trims whitespace', () {
      expect(normalizeCategoryKey('  DINING  '), 'dining');
      expect(normalizeCategoryKey('RESTAURANTS'), 'dining');
    });
  });

  group('categoryKeyFromPlaid', () {
    test('maps detailed PFC categories', () {
      expect(
        categoryKeyFromPlaid(
          primary: 'TRAVEL',
          detailed: 'TRAVEL_AIR_AND_NTIRELINE',
        ),
        'travel',
      );
      expect(
        categoryKeyFromPlaid(
          primary: 'FOOD_AND_DRINK',
          detailed: 'FOOD_AND_DRINK_RESTAURANTS',
        ),
        'dining',
      );
      expect(
        categoryKeyFromPlaid(
          primary: 'TRANSPORTATION',
          detailed: 'TRANSPORTATION_FUEL',
        ),
        'gas',
      );
      expect(
        categoryKeyFromPlaid(
          primary: 'FOOD_AND_DRINK',
          detailed: 'FOOD_AND_DRINK_GROCERIES',
        ),
        'groceries',
      );
    });

    test('falls back to primary when detailed is absent', () {
      expect(
        categoryKeyFromPlaid(primary: 'TRAVEL', detailed: null),
        'travel',
      );
      expect(
        categoryKeyFromPlaid(primary: 'FOOD_AND_DRINK', detailed: null),
        'dining',
      );
    });

    test('derives from prefix when not in explicit map', () {
      expect(
        categoryKeyFromPlaid(
          primary: 'GENERAL_MERCHANDISE',
          detailed: 'GENERAL_MERCHANDISE_ENTERTAINMENT',
        ),
        'entertainment',
      );
    });

    test('returns null when both are null or empty', () {
      expect(categoryKeyFromPlaid(primary: null, detailed: null), isNull);
      expect(categoryKeyFromPlaid(primary: '', detailed: ''), isNull);
    });
  });
}
