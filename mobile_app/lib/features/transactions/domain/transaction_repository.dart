import 'package:cardsemble/core/core.dart';
import 'package:cardsemble/features/transactions/domain/transactions_domain.dart';
import 'package:cardsemble/features/accounts/domain/accounts_domain.dart';

abstract class TransactionRepository {
  Future<Result<List<CardTransaction>>> loadTransactions();
  Future<Result<List<StatementAccount>>> loadAccounts();
  Future<Result<void>> assignTransaction(String transactionId, String? personId);
  Future<Result<void>> assignTransactionSplit(String transactionId, List<TransactionSplit> splits);
  Future<Result<List<TransactionSplit>>> fetchTransactionSplits(String transactionId);
  Future<Result<void>> setHouseholdVisible(String transactionId, bool visible);
  Future<Result<CsvImportPreview>> previewCsvImport(String accountId, String csvText);
  Future<Result<CsvImportResult>> confirmCsvImport(String accountId, List<CsvImportRow> rows, String filename);
  Future<Result<List<CsvImportHistory>>> loadCsvImportHistory();
}