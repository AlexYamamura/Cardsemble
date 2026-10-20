import 'package:flutter_test/flutter_test.dart';

import 'package:cardsemble/features/card_catalog/domain/entities/card_catalog_card.dart';

void main() {
  test('parses the supplied catalog entry shape and round-trips it', () {
    final json = <String, dynamic>{
      'id': 'us-chase-sapphire-preferred',
      'schema_version': '1.0.0',
      'name': 'Chase Sapphire Preferred® Card',
      'localized_names': {'en': 'Chase Sapphire Preferred® Card'},
      'country': 'us',
      'issuer': 'Chase',
      'issuer_id': 'chase',
      'network': 'visa',
      'network_tier': 'signature',
      'type': 'credit',
      'status': 'active',
      'annual_fee': {
        'amount': 95,
        'currency': 'USD',
        'first_year': 95,
        'waiver_conditions': null,
      },
      'apr': {
        'purchase': {'min': 19.24, 'max': 27.49, 'type': 'variable'},
        'notes': 'Variable APR.',
      },
      'fx_fee': {'percent': 0, 'notes': 'No foreign transaction fees.'},
      'credit_required': {
        'score_band': 'good_to_excellent',
        'notes': 'Chase targets good-to-excellent credit.',
      },
      'rewards': {
        'currency': 'ultimate_rewards',
        'currency_label': 'Ultimate Rewards points',
        'structure': 'multi',
        'base_rate': {
          'points_per_dollar': 1,
          'description': '1x on other purchases',
        },
        'categories': [
          {
            'label': 'Travel booked through Chase Travel',
            'points_per_dollar': 5,
            'cap': null,
          },
          {
            'label': 'Dining',
            'points_per_dollar': 3,
            'cap': null,
          },
        ],
        'redemption_notes': 'Points transfer to travel partners.',
        'rate_type': 'points_multiplier',
      },
      'signup_bonus': {
        'amount': 75000,
        'unit': 'points',
        'spend_required': 5000,
        'spend_currency': 'USD',
        'months': 3,
        'description': 'Earn 75,000 points.',
        'as_of': '2026-07-24',
      },
      'benefits': [
        {
          'id': 'trip-cancellation',
          'title': 'Trip Cancellation/Interruption Insurance',
          'category': 'insurance',
          'source': 'issuer',
          'description': 'Coverage for eligible prepaid trip costs.',
          'details': {'conditions': 'Charge eligible trip costs to the card.'},
        },
        {
          'id': 'baggage-delay',
          'title': 'Baggage Delay Insurance',
          'category': 'insurance',
          'source': 'issuer',
          'description': 'Reimbursement for essentials.',
        },
      ],
      'travel_perks': {
        'lounge_access': null,
        'tsa_precheck_credit': null,
        'global_entry_credit': null,
        'free_checked_bags': null,
        'hotel_status': null,
        'other': ['No foreign transaction fees'],
      },
      'official_url': 'https://creditcards.chase.com/',
      'image': {
        'url': 'https://example.com/card.png',
        'attribution': '© JPMorgan Chase Bank, N.A.',
        'local_path': null,
      },
      'bin_hints': <String>[],
      'last_verified': '2026-07-24',
      'sources': ['https://creditcards.chase.com/'],
      'notes': 'Representative catalog entry.',
      'segment': 'personal',
      'future_field': {'value': 1},
    };

    final card = CardCatalogCard.fromJson(json);

    expect(card.id, 'us-chase-sapphire-preferred');
    expect(card.schemaVersion, '1.0.0');
    expect(card.name, 'Chase Sapphire Preferred® Card');
    expect(card.localizedNames['en'], 'Chase Sapphire Preferred® Card');
    expect(card.annualFee!.amount, 95);
    expect(card.apr!.purchase!.min, 19.24);
    expect(card.rewards!.categories.length, 2);
    expect(card.rewards!.categories.first.pointsPerDollar, 5);
    expect(card.signupBonus!.months, 3);
    expect(card.benefits.length, 2);
    expect(
      card.benefits.first.details!['conditions'],
      'Charge eligible trip costs to the card.',
    );
    expect(card.travelPerks!.other, ['No foreign transaction fees']);
    expect(card.extra['future_field'], {'value': 1});

    final roundTripped = CardCatalogCard.fromJson(card.toJson());

    expect(roundTripped.id, card.id);
    expect(roundTripped.rewards!.categories.length, 2);
    expect(roundTripped.benefits.length, 2);
    expect(roundTripped.searchText, contains('chase'));
    expect(roundTripped.toJson()['future_field'], {'value': 1});
  });

  test('accepts scalar forms for flexible numeric sections', () {
    final card = CardCatalogCard.fromJson(<String, dynamic>{
      'id': 'scalar-card',
      'name': 'Scalar Card',
      'annual_fee': 95,
      'apr': 20.0,
      'fx_fee': 3,
      'rewards': {
        'base_rate': 1,
      },
    });

    expect(card.annualFee!.amount, 95);
    expect(card.apr!.purchase!.min, 20.0);
    expect(card.fxFee!.percent, 3);
    expect(card.rewards!.baseRate!.pointsPerDollar, 1);
  });

  test('missing optional sections parse safely', () {
    final card = CardCatalogCard.fromJson(<String, dynamic>{
      'id': 'minimal-card',
      'name': 'Minimal Card',
    });

    expect(card.id, 'minimal-card');
    expect(card.annualFee, isNull);
    expect(card.benefits, isEmpty);
    expect(card.sources, isEmpty);
    expect(card.extra, isEmpty);
  });

  test('an entry without a stable id is rejected', () {
    expect(
      () => CardCatalogCard.fromJson(<String, dynamic>{'name': 'No id'}),
      throwsFormatException,
    );
  });
}
