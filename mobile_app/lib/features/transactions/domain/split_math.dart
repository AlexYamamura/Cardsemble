import 'package:cardsemble/features/transactions/domain/transactions_domain.dart';

/// Calculates equal split percentages with integer remainder distribution.
/// For n participants: base = 100 ~/ n, remainder = 100 % n
/// The first 'remainder' participants get base+1%, the rest get base%
/// This ensures the sum is exactly 100%.
Map<String, double> equalSplitPercentages(List<String> personIds) {
  final Map<String, double> percentages = <String, double>{};
  final int n = personIds.length;
  
  if (n == 0) return percentages;
  
  final int base = 100 ~/ n;
  final int remainder = 100 % n;
  
  for (int i = 0; i < n; i++) {
    final String personId = personIds[i];
    // First 'remainder' participants get base+1, others get base
    percentages[personId] = (i < remainder) ? (base + 1).toDouble() : base.toDouble();
  }
  
  return percentages;
}

/// Normalizes existing splits to percentages that sum to 100%.
///
/// When [allPersonIds] is provided, the result is guaranteed to contain a key
/// for every id in that list (missing participants are backfilled with 0.0),
/// so callers can safely index the map for every displayed participant.
Map<String, double> percentagesFromExistingSplits(
    List<TransactionSplit> existingSplits, double totalAmount,
    {List<String>? allPersonIds}) {
  final Map<String, double> percentages = <String, double>{};

  if (existingSplits.isEmpty || totalAmount <= 0) {
    if (allPersonIds != null) {
      for (final id in allPersonIds) {
        percentages[id] = 0.0;
      }
    }
    return percentages;
  }

  // Calculate raw percentages
  for (final split in existingSplits) {
    final double percent = (split.amount / totalAmount) * 100.0;
    percentages[split.personId] = percent;
  }

  // Backfill any displayed participant that has no stored split.
  if (allPersonIds != null) {
    for (final id in allPersonIds) {
      percentages.putIfAbsent(id, () => 0.0);
    }
  }

  // Normalize to ensure sum is exactly 100%
  final double totalPercentage =
      percentages.values.fold(0.0, (a, b) => a + b);

  if (totalPercentage > 0) {
    percentages.updateAll(
        (key, value) => (value / totalPercentage) * 100.0);
  }

  return percentages;
}

/// Moves a boundary between two adjacent segments, adjusting their percentages
/// while keeping the total sum exactly 100%.
Map<String, double> moveBoundary(
    Map<String, double> currentPercentages,
    List<String> orderedPersonIds,
    int boundaryIndex, // Index of the person whose right boundary is being moved
    double newCumulativePercent, {
      double minPercent = 0.0, // Minimum percentage for any segment
    }) {
  final Map<String, double> result = Map<String, double>.from(currentPercentages);
  
  if (boundaryIndex < 0 || boundaryIndex >= orderedPersonIds.length - 1) {
    return result; // Invalid boundary
  }
  
  // Calculate current cumulative percentage up to this boundary
  double currentCumulative = 0.0;
  for (int i = 0; i <= boundaryIndex; i++) {
    currentCumulative += result[orderedPersonIds[i]]!;
  }
  
  // Calculate the change needed
  final double delta = newCumulativePercent - currentCumulative;
  
  // Apply the change to the two adjacent segments. Moving the boundary to the
  // right grows the left segment and shrinks the right one.
  final String leftPersonId = orderedPersonIds[boundaryIndex];
  final String rightPersonId = orderedPersonIds[boundaryIndex + 1];
  
  double newLeftPercent = result[leftPersonId]! + delta;
  double newRightPercent = result[rightPersonId]! - delta;
  
  // Enforce minimum percentage constraints
  if (newLeftPercent < minPercent) {
    // Not enough to give to left, adjust right to compensate
    final double deficit = minPercent - newLeftPercent;
    newLeftPercent = minPercent;
    newRightPercent -= deficit;
  }
  
  if (newRightPercent < minPercent) {
    // Not enough to give to right, adjust left to compensate
    final double deficit = minPercent - newRightPercent;
    newRightPercent = minPercent;
    newLeftPercent -= deficit;
  }
  
  // Update the percentages
  result[leftPersonId] = newLeftPercent;
  result[rightPersonId] = newRightPercent;
  
  return result;
}

/// Snaps a value to the nearest guideline within tolerance, otherwise returns the original value.
double snapToGuideline(
    double value, {
      List<double> guidelines = const [25.0, 50.0, 75.0],
      double tolerance = 5.0, // Percent tolerance for snapping
    }) {
  for (final guideline in guidelines) {
    if ((value - guideline).abs() <= tolerance) {
      return guideline;
    }
  }
  return value; // No snap
}

/// Converts a percentage map to a [TransactionSplit] list whose amounts sum
/// exactly to [totalAmountAbs] to the cent.
///
/// Uses the largest-remainder method: every active participant is floored to
/// whole cents, then the leftover cents are handed to the participants with the
/// largest fractional parts. This guarantees `sum(amounts) == totalAmountAbs`
/// even when several shares round up (unlike "last person takes the remainder",
/// which can overrun and drop a negative share). Participants allocated zero
/// cents are omitted, since the server rejects non-positive split amounts.
List<TransactionSplit> percentagesToCents(
    double totalAmountAbs,
    Map<String, double> percentages,
    List<String> orderedPersonIds) {
  final int totalAmountCents = (totalAmountAbs * 100).round();
  if (totalAmountCents <= 0) return <TransactionSplit>[];

  // Only participants with a meaningful share can receive cents.
  final List<String> active = orderedPersonIds
      .where((id) => (percentages[id] ?? 0.0) > 0.1)
      .toList();
  if (active.isEmpty) return <TransactionSplit>[];

  final double sumPercent =
      active.fold(0.0, (sum, id) => sum + percentages[id]!);
  if (sumPercent <= 0) return <TransactionSplit>[];

  final Map<String, double> exact = <String, double>{};
  final Map<String, int> cents = <String, int>{};
  int allocated = 0;
  for (final id in active) {
    final double raw = totalAmountCents * percentages[id]! / sumPercent;
    exact[id] = raw;
    final int floored = raw.floor();
    cents[id] = floored;
    allocated += floored;
  }

  int remainder = totalAmountCents - allocated;
  final List<String> byFraction = active.toList()
    ..sort((a, b) =>
        (exact[b]! - cents[b]!).compareTo(exact[a]! - cents[a]!));
  for (int i = 0; i < byFraction.length && remainder > 0; i++) {
    cents[byFraction[i]] = cents[byFraction[i]]! + 1;
    remainder--;
  }

  final List<TransactionSplit> splits = <TransactionSplit>[];
  for (final id in orderedPersonIds) {
    final int amountCents = cents[id] ?? 0;
    if (amountCents > 0) {
      splits.add(TransactionSplit(personId: id, amount: amountCents / 100.0));
    }
  }
  return splits;
}