import 'package:cardsemble/core/error/failure.dart';
import 'package:cardsemble/features/transactions/domain/split_math.dart';
import 'package:cardsemble/features/transactions/domain/transaction_repository.dart';

class LoadTransactionSplitDraft {
  LoadTransactionSplitDraft(this._transactionRepository);

  final TransactionRepository _transactionRepository;

  Future<Result<Map<String, double>>> call({
    required String transactionId,
    required double totalAmount,
    required List<String> participantIds,
  }) async {
    try {
      final result =
          await _transactionRepository.fetchTransactionSplits(transactionId);
      return result.map((splits) {
        if (splits.isEmpty || totalAmount <= 0) {
          return equalSplitPercentages(participantIds);
        }

        final percentages = percentagesFromExistingSplits(
          splits,
          totalAmount,
          allPersonIds: participantIds,
        );
        final double total = percentages.values.fold<double>(
          0.0,
          (sum, value) => sum + value,
        );
        return total <= 0
            ? equalSplitPercentages(participantIds)
            : percentages;
      });
    } on Failure catch (failure) {
      return FailureResult(failure);
    } catch (e) {
      return FailureResult(UnknownFailure(e.toString()));
    }
  }
}