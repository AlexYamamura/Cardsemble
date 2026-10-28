import 'package:flutter_test/flutter_test.dart';

import 'package:cardsemble/features/wallet/domain/wallet_card.dart';

void main() {
  group('WalletCard', () {
    test('lastFour returns the last four digits of the mask', () {
      expect(
        WalletCard(id: 'a', displayName: 'A', mask: '****1234').lastFour,
        '1234',
      );
      expect(
        WalletCard(id: 'a', displayName: 'A', mask: '1234').lastFour,
        '1234',
      );
      expect(WalletCard(id: 'a', displayName: 'A', mask: '123').lastFour, isNull);
      expect(WalletCard(id: 'a', displayName: 'A').lastFour, isNull);
    });
  });

  group('WalletBonus', () {
    test('progress is spent divided by required', () {
      final bonus = WalletBonus(
        amountUnits: 60_000,
        spendRequiredUnits: 3_000_000,
        spentUnits: 750_000,
      );
      expect(bonus.progress, 0.25);
      expect(bonus.isComplete, isFalse);
      expect(bonus.remainingUnits, 2_250_000);
    });

    test('progress clamps and completes at 100%', () {
      final bonus = WalletBonus(
        amountUnits: 60_000,
        spendRequiredUnits: 3_000_000,
        spentUnits: 4_000_000,
      );
      expect(bonus.progress, 1.0);
      expect(bonus.isComplete, isTrue);
      expect(bonus.remainingUnits, 0);
    });

    test('zero required spend yields zero progress', () {
      final bonus = WalletBonus(
        amountUnits: 60_000,
        spendRequiredUnits: 0,
        spentUnits: 100,
      );
      expect(bonus.progress, 0.0);
      expect(bonus.isComplete, isFalse);
    });
  });

  group('WalletBenefit', () {
    test('tracks usage state', () {
      final used = WalletBenefit(id: 'b1', title: 'Travel credit', used: true);
      final unused = WalletBenefit(id: 'b2', title: 'Purchase protection');
      expect(used.used, isTrue);
      expect(unused.used, isFalse);
    });
  });
}
