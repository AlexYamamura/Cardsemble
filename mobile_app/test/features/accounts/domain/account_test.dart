import 'package:flutter_test/flutter_test.dart';

import 'package:cardsemble/features/accounts/domain/accounts_domain.dart';

void main() {
  group('StatementAccount.fromJson', () {
    test('parses next_payment_due_date from a Plaid date string', () {
      final account = StatementAccount.fromJson({
        'account_id': 'acct-1',
        'account_name': 'Chase Card',
        'item_id': 'item-1',
        'iso_currency_code': 'USD',
        'next_payment_due_date': '2026-11-15',
      });

      expect(account.nextPaymentDueDate, DateTime(2026, 11, 15));
    });

    test('leaves nextPaymentDueDate null when the field is absent or null', () {
      final account = StatementAccount.fromJson({
        'account_id': 'acct-1',
        'account_name': 'Card',
        'item_id': 'item-1',
        'next_payment_due_date': null,
      });

      expect(account.nextPaymentDueDate, isNull);
    });
  });

  group('StatementAccount.toJson', () {
    test('round-trips the payment due date as a date-only string', () {
      final account = StatementAccount(
        accountId: 'acct-1',
        accountName: 'Card',
        nextPaymentDueDate: DateTime(2026, 11, 15),
      );
      final json = account.toJson();

      expect(json['next_payment_due_date'], '2026-11-15');
      expect(
        StatementAccount.fromJson(json).nextPaymentDueDate,
        DateTime(2026, 11, 15),
      );
    });
  });
}
