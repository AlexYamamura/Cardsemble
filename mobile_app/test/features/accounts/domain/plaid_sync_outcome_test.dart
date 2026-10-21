import 'package:flutter_test/flutter_test.dart';

import 'package:cardsemble/features/accounts/domain/accounts_domain.dart';

void main() {
  group('PlaidSyncOutcome.fromJson', () {
    test('parses a realistic item_errors payload', () {
      final outcome = PlaidSyncOutcome.fromJson({
        'ok': true,
        'items_synced': 1,
        'items_failed': 2,
        'item_errors': [
          {
            'item_id': 'item-1',
            'institution_name': 'Chase',
            'error_code': 'ITEM_LOGIN_REQUIRED',
            'message': 'This connection needs to be re-authenticated.',
          },
          {
            'item_id': 'item-2',
            'institution_name': null,
            'error_code': 'ITEM_LOGIN_REQUIRED',
            'message': 'This connection needs to be re-authenticated.',
          },
        ],
      });

      expect(outcome.hasWarnings, isTrue);
      expect(outcome.itemErrors, hasLength(2));
      expect(outcome.itemErrors.first.itemId, 'item-1');
      expect(outcome.itemErrors.first.institutionName, 'Chase');
      expect(outcome.itemErrors.first.errorCode, 'ITEM_LOGIN_REQUIRED');
      expect(
        outcome.itemErrors.first.message,
        'This connection needs to be re-authenticated.',
      );
      expect(outcome.itemErrors.first.needsReauthentication, isTrue);
      expect(outcome.itemErrors.last.institutionName, isNull);
    });

    test('treats a missing item_errors list as no warnings', () {
      final outcome = PlaidSyncOutcome.fromJson({'ok': true});

      expect(outcome.itemErrors, isEmpty);
      expect(outcome.hasWarnings, isFalse);
    });

    test('treats a non-list item_errors value as no warnings', () {
      final outcome = PlaidSyncOutcome.fromJson({'item_errors': 'nope'});

      expect(outcome.itemErrors, isEmpty);
      expect(outcome.hasWarnings, isFalse);
    });

    test('skips malformed rows without throwing', () {
      final outcome = PlaidSyncOutcome.fromJson({
        'item_errors': [
          'not-an-object',
          42,
          <String, dynamic>{'institution_name': 'No Item Id'},
          {
            'item_id': 'item-3',
            'institution_name': 'Amex',
            'error_code': 'ITEM_LOGIN_REQUIRED',
            'message': 'This connection needs to be re-authenticated.',
          },
        ],
      });

      expect(outcome.itemErrors, hasLength(1));
      expect(outcome.itemErrors.first.itemId, 'item-3');
      expect(outcome.itemErrors.first.institutionName, 'Amex');
    });
  });

  group('PlaidItemSyncError.needsReauthentication', () {
    test('is true for the expected re-authentication codes', () {
      for (final code in [
        'ITEM_LOGIN_REQUIRED',
        'INVALID_ACCESS_TOKEN',
        'REAUTH_REQUIRED',
      ]) {
        final error = PlaidItemSyncError(
          itemId: 'item-1',
          errorCode: code,
          message: 'message',
        );
        expect(error.needsReauthentication, isTrue, reason: code);
      }
    });

    test('is false for other codes and for a missing code', () {
      expect(
        PlaidItemSyncError(
          itemId: 'item-1',
          errorCode: 'ITEM_NOT_FOUND',
          message: 'message',
        ).needsReauthentication,
        isFalse,
      );
      expect(
        PlaidItemSyncError(
          itemId: 'item-1',
          message: 'message',
        ).needsReauthentication,
        isFalse,
      );
    });
  });
}
