import 'package:flutter_test/flutter_test.dart';
import 'package:cardsemble/features/transactions/domain/split_math.dart';
import 'package:cardsemble/features/transactions/domain/transactions_domain.dart';

void main() {
  group('equalSplitPercentages', () {
    test('splits 2 people evenly as [50, 50]', () {
      final result = equalSplitPercentages(['a', 'b']);
      expect(result['a'], 50.0);
      expect(result['b'], 50.0);
      expect(result.values.fold(0.0, (x, y) => x + y), 100.0);
    });

    test('splits 3 people with remainder distribution as [34, 33, 33]', () {
      final result = equalSplitPercentages(['a', 'b', 'c']);
      expect(result['a'], 34.0);
      expect(result['b'], 33.0);
      expect(result['c'], 33.0);
      expect(result.values.fold(0.0, (x, y) => x + y), 100.0);
    });

    test('splits 4 people as [25, 25, 25, 25]', () {
      final result = equalSplitPercentages(['a', 'b', 'c', 'd']);
      expect(result.values.every((v) => v == 25.0), isTrue);
      expect(result.values.fold(0.0, (x, y) => x + y), 100.0);
    });

    test('always sums to exactly 100 for 2-4 people', () {
      for (var n = 2; n <= 4; n++) {
        final ids = List.generate(n, (i) => 'p$i');
        final result = equalSplitPercentages(ids);
        expect(result.values.fold(0.0, (x, y) => x + y), 100.0,
            reason: 'n=$n should sum to 100');
      }
    });

    test('returns empty map for no participants', () {
      expect(equalSplitPercentages([]), isEmpty);
    });
  });

  group('snapToGuideline', () {
    test('snaps to 25 when within tolerance', () {
      expect(snapToGuideline(24.0), 25.0);
      expect(snapToGuideline(26.0), 25.0);
    });

    test('snaps to 50 and 75 when within tolerance', () {
      expect(snapToGuideline(48.0), 50.0);
      expect(snapToGuideline(73.0), 75.0);
    });

    test('does not snap when outside tolerance', () {
      expect(snapToGuideline(10.0), 10.0);
      expect(snapToGuideline(60.0), 60.0);
      expect(snapToGuideline(90.0), 90.0);
    });
  });

  group('moveBoundary', () {
    test('keeps the total at 100 after moving a boundary', () {
      final current = {'a': 50.0, 'b': 50.0};
      final result = moveBoundary(current, ['a', 'b'], 0, 70.0);
      expect(result['a'], 70.0);
      expect(result['b'], 30.0);
      expect(result.values.fold(0.0, (x, y) => x + y), 100.0);
    });

    test('respects the minimum percentage constraint', () {
      final current = {'a': 50.0, 'b': 50.0};
      final result = moveBoundary(current, ['a', 'b'], 0, 90.0, minPercent: 20.0);
      expect(result['a'], 80.0);
      expect(result['b'], 20.0);
      expect(result.values.fold(0.0, (x, y) => x + y), 100.0);
    });

    test('returns unchanged map for an invalid boundary index', () {
      final current = {'a': 50.0, 'b': 50.0};
      final result = moveBoundary(current, ['a', 'b'], 5, 70.0);
      expect(result, current);
    });
  });

  group('percentagesToCents', () {
    test('splits a 2-way exactly to the cent', () {
      final splits = percentagesToCents(
        10.00,
        {'a': 50.0, 'b': 50.0},
        ['a', 'b'],
      );
      expect(splits.length, 2);
      final sum = splits.fold(0.0, (s, e) => s + e.amount);
      expect(sum, closeTo(10.00, 0.0001));
    });

    test('resolves rounding remainder so the sum equals the total', () {
      // 3-way split of $10.00 with 33.33/33.33/33.34-ish percentages
      final splits = percentagesToCents(
        10.00,
        {'a': 33.33, 'b': 33.33, 'c': 33.34},
        ['a', 'b', 'c'],
      );
      final sum = splits.fold(0.0, (s, e) => s + e.amount);
      expect(sum, closeTo(10.00, 0.0001));
    });

    test('drops zero-percent participants', () {
      final splits = percentagesToCents(
        10.00,
        {'a': 100.0, 'b': 0.0},
        ['a', 'b'],
      );
      expect(splits.length, 1);
      expect(splits.first.personId, 'a');
      expect(splits.first.amount, closeTo(10.00, 0.0001));
    });

    test('handles odd cent totals without negative amounts', () {
      final splits = percentagesToCents(
        0.03,
        {'a': 25.0, 'b': 25.0, 'c': 25.0, 'd': 25.0},
        ['a', 'b', 'c', 'd'],
      );
      expect(splits.every((s) => s.amount > 0), isTrue);
      final sum = splits.fold(0.0, (s, e) => s + e.amount);
      expect(sum, closeTo(0.03, 0.0001));
    });

    test('never exceeds the total when several shares round up (\$0.02/4-way)', () {
      // Regression: previously three shares floored/rounded to 1 cent each and
      // the last share went negative, producing a 3-cent payload for a 2-cent
      // transaction.
      final splits = percentagesToCents(
        0.02,
        {'a': 25.0, 'b': 25.0, 'c': 25.0, 'd': 25.0},
        ['a', 'b', 'c', 'd'],
      );
      final sum = splits.fold(0.0, (s, e) => s + e.amount);
      expect(sum, closeTo(0.02, 0.0001));
      expect(sum, lessThanOrEqualTo(0.02 + 0.0001));
      expect(splits.every((s) => s.amount > 0), isTrue);
    });

    test('sums exactly for many amounts and participant counts', () {
      final cases = <double>[0.01, 0.02, 0.03, 0.07, 1.00, 9.99, 10.00, 123.45];
      for (final amount in cases) {
        for (var n = 2; n <= 4; n++) {
          final ids = List.generate(n, (i) => 'p$i');
          final pct = equalSplitPercentages(ids);
          final splits = percentagesToCents(amount, pct, ids);
          final sum = splits.fold(0.0, (s, e) => s + e.amount);
          expect(sum, closeTo(amount, 0.0001),
              reason: 'amount=$amount n=$n should sum exactly');
          expect(splits.every((s) => s.amount > 0), isTrue,
              reason: 'no non-positive amounts for amount=$amount n=$n');
        }
      }
    });
  });

  group('split payload', () {
    test('serializes to person_id/amount with an exact-cent sum', () {
      final splits = percentagesToCents(
        10.00,
        {'a': 33.33, 'b': 33.33, 'c': 33.34},
        ['a', 'b', 'c'],
      );
      final payload = splits.map((s) => s.toJson()).toList();
      expect(payload.every((m) => m.containsKey('person_id')), isTrue);
      expect(payload.every((m) => m.containsKey('amount')), isTrue);
      expect(payload.every((m) => (m['amount'] as num).toDouble() > 0), isTrue);
      final sum = payload.fold<double>(
        0.0,
        (acc, m) => acc + (m['amount'] as num).toDouble(),
      );
      expect(sum, closeTo(10.00, 0.0001));
    });
  });

  group('percentagesFromExistingSplits', () {
    test('normalizes existing splits to sum 100', () {
      final splits = [
        const TransactionSplit(personId: 'a', amount: 3.0),
        const TransactionSplit(personId: 'b', amount: 7.0),
      ];
      final result = percentagesFromExistingSplits(splits, 10.0);
      expect(result['a'], closeTo(30.0, 0.001));
      expect(result['b'], closeTo(70.0, 0.001));
      expect(result.values.fold(0.0, (x, y) => x + y), closeTo(100.0, 0.001));
    });

    test('backfills participants missing from the stored splits', () {
      // Regression: partial splits previously produced a map without every
      // participant key, crashing the slider's force-unwrap.
      final splits = [
        const TransactionSplit(personId: 'a', amount: 5.0),
        const TransactionSplit(personId: 'b', amount: 5.0),
      ];
      final result = percentagesFromExistingSplits(
        splits,
        10.0,
        allPersonIds: ['a', 'b', 'c'],
      );
      expect(result.containsKey('c'), isTrue);
      expect(result['c'], 0.0);
      expect(result.values.fold(0.0, (x, y) => x + y), closeTo(100.0, 0.001));
    });

    test('backfills all participants when there are no stored splits', () {
      final result = percentagesFromExistingSplits(
        const [],
        10.0,
        allPersonIds: ['a', 'b'],
      );
      expect(result.keys.toSet(), {'a', 'b'});
      expect(result['a'], 0.0);
      expect(result['b'], 0.0);
    });

    test('returns empty map when total is zero', () {
      final splits = [
        const TransactionSplit(personId: 'a', amount: 0.0),
      ];
      expect(percentagesFromExistingSplits(splits, 0.0), isEmpty);
    });
  });
}
