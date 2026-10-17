import 'package:cardsemble/core/error/failure.dart';
import 'package:cardsemble/features/transactions/domain/entities/transaction.dart';
import 'package:cardsemble/features/transactions/domain/split_math.dart';
import 'package:cardsemble/features/transactions/domain/transaction_repository.dart';

class SaveTransactionSplit {
  SaveTransactionSplit(this._transactionRepository);

  final TransactionRepository _transactionRepository;

  Future<Result<List<TransactionSplit>>> call({
    required String transactionId,
    required double totalAmount,
    required Map<String, double> percentages,
    required List<String> orderedPersonIds,
  }) async {
    if (orderedPersonIds.length < 2) {
      return FailureResult(const ValidationFailure(
        'At least two participants are required.',
      ));
    }
    if (orderedPersonIds.toSet().length != orderedPersonIds.length) {
      return FailureResult(const ValidationFailure(
        'Duplicate participant IDs are not allowed.',
      ));
    }
    for (final id in orderedPersonIds) {
      if (!percentages.containsKey(id)) {
        return FailureResult(ValidationFailure(
          'Percentage missing for participant: $id',
        ));
      }
    }
    final double sum = percentages.values.fold<double>(
      0.0,
      (sum, value) => sum + value,
    );
    if ((sum - 100).abs() > 0.01) {
      return FailureResult(const ValidationFailure(
        'Percentages must sum to 100%.',
      ));
    }
    if (totalAmount <= 0) {
      return FailureResult(const ValidationFailure(
        'Transaction amount must be greater than zero.',
      ));
    }

    final List<TransactionSplit> splits = percentagesToCents(
      totalAmount.abs(),
      percentages,
      orderedPersonIds,
    );

    final int expectedCents = (totalAmount.abs() * 100).round();
    final int actualCents = splits.fold<int>(
      0,
      (sum, split) => sum + (split.amount * 100).round(),
    );
    if (splits.isEmpty || actualCents != expectedCents) {
      return FailureResult(const ValidationFailure(
        'Split amounts do not add up to the transaction total.',
      ));
    }

    try {
      final result = await _transactionRepository.assignTransactionSplit(
        transactionId,
        splits,
      );
      return result.map((_) => splits);
    } on Failure catch (failure) {
      return FailureResult(failure);
    } catch (e) {
      return FailureResult(UnknownFailure(e.toString()));
    }
  }
}