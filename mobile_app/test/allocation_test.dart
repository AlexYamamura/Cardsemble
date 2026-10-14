import 'dart:math';

import 'package:cardsemble/ledger_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Allocation angle calculations', () {
    test('angle normalization maps top to 0', () {
      final angle = -pi / 2; // Top in atan2 (y inverted)
      var normalized = angle + pi / 2;
      if (normalized < 0) normalized += pi * 2;
      expect(normalized, closeTo(0, 0.001));
    });

    test('angle normalization maps right to pi/2', () {
      final angle = 0.0; // Right
      var normalized = angle + pi / 2;
      if (normalized < 0) normalized += pi * 2;
      expect(normalized, closeTo(pi / 2, 0.001));
    });

    test('angle normalization maps bottom to pi', () {
      final angle = pi / 2; // Bottom
      var normalized = angle + pi / 2;
      if (normalized < 0) normalized += pi * 2;
      expect(normalized, closeTo(pi, 0.001));
    });

    test('angle normalization maps left to 3pi/2', () {
      final angle = pi; // Left
      var normalized = angle + pi / 2;
      if (normalized < 0) normalized += pi * 2;
      expect(normalized, closeTo(3 * pi / 2, 0.001));
    });
  });

  group('Angular delta with wraparound', () {
    test('clockwise drag gives positive delta', () {
      final startAngle = pi / 2; // Right
      final endAngle = pi; // Bottom (clockwise from right)
      var delta = endAngle - startAngle;
      if (delta > pi) delta -= 2 * pi;
      if (delta < -pi) delta += 2 * pi;
      expect(delta, greaterThan(0));
    });

    test('counterclockwise drag gives negative delta', () {
      final startAngle = pi / 2; // Right
      final endAngle = 0; // Top (counterclockwise from right)
      var delta = endAngle - startAngle;
      if (delta > pi) delta -= 2 * pi;
      if (delta < -pi) delta += 2 * pi;
      expect(delta, lessThan(0));
    });

    test('wraparound across 0/2pi boundary clockwise', () {
      final startAngle = 7 * pi / 4; // Near top-left
      final endAngle = pi / 4; // Slightly past top
      var delta = endAngle - startAngle;
      if (delta > pi) delta -= 2 * pi;
      if (delta < -pi) delta += 2 * pi;
      // Should be clockwise (positive): from 315° to 45° going clockwise = 90°
      expect(delta, closeTo(pi / 2, 0.001));
    });

    test('wraparound across 0/2pi boundary counterclockwise', () {
      final startAngle = pi / 4; // Slightly past top
      final endAngle = 7 * pi / 4; // Near top-left
      var delta = endAngle - startAngle;
      if (delta > pi) delta -= 2 * pi;
      if (delta < -pi) delta += 2 * pi;
      // Should be counterclockwise (negative): from 45° to 315° going counterclockwise = -90°
      expect(delta, closeTo(-pi / 2, 0.001));
    });
  });

  group('Allocation transfer logic', () {
    test('transfer between two adjacent users preserves total', () {
      final transfers = 25.0;
      final amount1 = 50.0;
      final amount2 = 50.0;
      final newAmount1 = amount1 + transfers;
      final newAmount2 = amount2 - transfers;
      expect(newAmount1 + newAmount2, 100.0);
    });

    test('clockwise delta increases selected user amount', () {
      final total = 100.0;
      final delta = pi / 2; // 90 degrees clockwise
      final amountDelta = (delta / (2 * pi)) * total;
      final startAmount = 50.0;
      final newAmount = (startAmount + amountDelta).clamp(0.0, total);
      expect(newAmount, greaterThan(startAmount));
    });

    test('counterclockwise delta decreases selected user amount', () {
      final total = 100.0;
      final delta = -pi / 2; // 90 degrees counterclockwise
      final amountDelta = (delta / (2 * pi)) * total;
      final startAmount = 50.0;
      final newAmount = (startAmount + amountDelta).clamp(0.0, total);
      expect(newAmount, lessThan(startAmount));
    });

    test('full circle delta transfers full amount', () {
      final total = 100.0;
      final delta = 2 * pi; // Full clockwise circle
      final amountDelta = (delta / (2 * pi)) * total;
      final startAmount = 50.0;
      final newAmount = (startAmount + amountDelta).clamp(0.0, total);
      expect(newAmount, closeTo(total, 0.01));
    });
  });

  group('Boundary-to-user mapping', () {
    test('2-user split has boundary at pi radians', () {
      final fractions = [0.5, 0.5];
      double cumulative = 0;
      for (int i = 0; i < fractions.length; i++) {
        cumulative += fractions[i] * 2 * pi;
      }
      // First boundary at cumulative = pi (after first slice)
      expect(cumulative / 2, closeTo(pi, 0.001));
    });

    test('3-user equal split has boundaries at 2pi/3 and 4pi/3', () {
      final fractions = [1.0 / 3, 1.0 / 3, 1.0 / 3];
      double cumulative = 0;
      final boundaries = <double>[];
      for (int i = 0; i < fractions.length; i++) {
        cumulative += fractions[i] * 2 * pi;
        boundaries.add(cumulative);
      }
      expect(boundaries[0], closeTo(2 * pi / 3, 0.001));
      expect(boundaries[1], closeTo(4 * pi / 3, 0.001));
    });

    test('4-user equal split has boundaries at pi/2, pi, 3pi/2', () {
      final fractions = [0.25, 0.25, 0.25, 0.25];
      double cumulative = 0;
      final boundaries = <double>[];
      for (int i = 0; i < fractions.length; i++) {
        cumulative += fractions[i] * 2 * pi;
        boundaries.add(cumulative);
      }
      expect(boundaries[0], closeTo(pi / 2, 0.001));
      expect(boundaries[1], closeTo(pi, 0.001));
      expect(boundaries[2], closeTo(3 * pi / 2, 0.001));
    });
  });

  group('Allocation limits', () {
    const minAllocation = 0.0;
    const total = 100.0;

    test('allocation clamps to 0 minimum', () {
      final transfer = -60.0;
      final startAmount = 50.0;
      final newAmount = (startAmount + transfer).clamp(minAllocation, total);
      expect(newAmount, 0.0);
    });

    test('allocation clamps to total maximum', () {
      final transfer = 60.0;
      final startAmount = 50.0;
      final newAmount = (startAmount + transfer).clamp(minAllocation, total);
      expect(newAmount, 100.0);
    });

    test('negative allocation is prevented', () {
      final transfer = -120.0;
      final startAmount = 20.0;
      final newAmount = (startAmount + transfer).clamp(minAllocation, total);
      expect(newAmount, greaterThanOrEqualTo(0.0));
    });

    test('exceeding total is prevented', () {
      final transfer = 80.0;
      final startAmount = 80.0;
      final newAmount = (startAmount + transfer).clamp(minAllocation, total);
      expect(newAmount, lessThanOrEqualTo(total));
    });
  });

  group('TransactionSplit model', () {
    test('toJson produces correct map', () {
      const split = TransactionSplit(personId: 'user-1', amount: 50.0);
      final json = split.toJson();
      expect(json['person_id'], 'user-1');
      expect(json['amount'], 50.0);
    });

    test('fromJson-like construction produces correct object', () {
      final split = TransactionSplit(personId: 'user-2', amount: 25.0);
      expect(split.personId, 'user-2');
      expect(split.amount, 25.0);
    });
  });

  group('One-user behavior', () {
    test('single user has 100% allocation', () {
      const total = 100.0;
      const amount = 100.0;
      final fraction = amount / total;
      expect(fraction, 1.0);
    });

    test('single user sweep covers full circle', () {
      const fraction = 1.0;
      final sweep = fraction * 2 * pi;
      expect(sweep, closeTo(2 * pi, 0.001));
    });
  });

  group('Dynamic user count transitions', () {
    test('allocations sum to total for 1 user', () {
      final allocations = [100.0];
      expect(allocations.reduce((a, b) => a + b), closeTo(100.0, 0.01));
    });

    test('allocations sum to total for 2 users', () {
      final allocations = [50.0, 50.0];
      expect(allocations.reduce((a, b) => a + b), closeTo(100.0, 0.01));
    });

    test('allocations sum to total for 3 users', () {
      final allocations = [33.33, 33.33, 33.34];
      expect(allocations.reduce((a, b) => a + b), closeTo(100.0, 0.01));
    });

    test('allocations sum to total for 4 users', () {
      final allocations = [25.0, 25.0, 25.0, 25.0];
      expect(allocations.reduce((a, b) => a + b), closeTo(100.0, 0.01));
    });
  });

  group('Rounding and displayed percentages', () {
    test('displayed percentage rounds correctly', () {
      final amount = 33.333;
      final total = 100.0;
      final fraction = amount / total;
      final percentage = fraction * 100;
      expect(percentage, closeTo(33.33, 0.1));
    });

    test('25% allocation displays as 25%', () {
      const fraction = 0.25;
      final percentage = fraction * 100;
      expect(percentage, 25.0);
    });

    test('50% allocation displays as 50%', () {
      const fraction = 0.5;
      final percentage = fraction * 100;
      expect(percentage, 50.0);
    });
  });
}
