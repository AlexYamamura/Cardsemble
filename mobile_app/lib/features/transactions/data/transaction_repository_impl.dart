import 'package:cardsemble/core/core.dart';
import 'package:cardsemble/features/transactions/domain/transactions_domain.dart';
import 'package:cardsemble/features/accounts/domain/accounts_domain.dart';

class TransactionRepositoryImpl implements TransactionRepository {
  TransactionRepositoryImpl({
    required SupabaseApiClient apiClient,
  }) : _apiClient = apiClient;

  final SupabaseApiClient _apiClient;

  @override
  Future<Result<TransactionPage>> loadTransactions(TransactionQuery query) async {
    final queryString = Uri(queryParameters: query.toQueryParameters()).query;
    final result = await _apiClient.safeGet('/api/plaid-transactions?$queryString');
    return result.flatMap((payload) {
      try {
        final items = extractRecords(payload, 'transactions')
            .map(CardTransaction.fromJson)
            .toList(growable: false);
        return Success(
          TransactionPage(items: items, hasMore: payload['has_more'] == true),
        );
      } catch (e) {
        // A failed parse must surface as a failure instead of throwing out of
        // the repository and being treated as an empty page.
        return FailureResult(
          UnknownFailure('Could not read transactions: $e'),
        );
      }
    });
  }

  @override
  Future<Result<List<StatementAccount>>> loadAccounts() async {
    final result = await _apiClient.safeGet('/api/owed/statement-cycles');
    return result.map(
      (payload) {
        final accounts = payload['credit_accounts'] ?? payload['accounts'];
        if (accounts is! List) return <StatementAccount>[];
        return accounts
            .whereType<Map<String, dynamic>>()
            .map(StatementAccount.fromJson)
            .toList(growable: false);
      },
    );
  }

  @override
  Future<Result<TransactionAssignment>> assignTransaction(String transactionId, String? personId) async {
    final result = await _apiClient.safePost(
      '/api/plaid-transactions/$transactionId/assignment',
      {'person_id': personId},
    );
    return result.flatMap((payload) {
      if (payload['ok'] != true) {
        return const FailureResult<TransactionAssignment>(
          NetworkFailure('Could not assign transaction.'),
        );
      }
      // Unassigning returns the household default person at the top level;
      // assigning returns the created assignment row under "assignment".
      final assignment = payload['assignment'];
      final resolvedPersonId = payload['person_id'] ??
          (assignment is Map<String, dynamic> ? assignment['person_id'] : null);
      final source = (assignment is Map<String, dynamic>
              ? assignment['assignment_source']
              : null) ??
          payload['assignment_source'] as String? ??
          (personId != null ? 'manual' : 'default');
      return Success(
        TransactionAssignment(
          personId: resolvedPersonId as String?,
          assignmentSource: source,
        ),
      );
    });
  }

  @override
  Future<Result<void>> assignTransactionSplit(String transactionId, List<TransactionSplit> splits) async {
    final result = await _apiClient.safePost(
      '/api/plaid-transactions/$transactionId/assignment-split',
      {'splits': splits.map((s) => s.toJson()).toList()},
    );
    return result.map((payload) {
      if (payload['ok'] != true) {
        throw const NetworkException('Could not assign transaction split.');
      }
    });
  }

  @override
  Future<Result<List<TransactionSplit>>> fetchTransactionSplits(String transactionId) async {
    final result = await _apiClient.safeGet('/api/plaid-transactions/$transactionId/splits');
    return result.flatMap((payload) {
      final raw = payload['splits'];
      if (raw == null) {
        return const Success<List<TransactionSplit>>(<TransactionSplit>[]);
      }
      if (raw is! List) {
        return const FailureResult<List<TransactionSplit>>(
          UnknownFailure(
            'Could not read transaction splits: "splits" is not a list.',
          ),
        );
      }

      try {
        final splits = raw
            .map(TransactionSplit.tryParse)
            .whereType<TransactionSplit>()
            .toList(growable: false);
        return Success<List<TransactionSplit>>(splits);
      } catch (e) {
        return FailureResult<List<TransactionSplit>>(
          UnknownFailure('Could not read transaction splits: $e'),
        );
      }
    });
  }

  @override
  Future<Result<void>> setHouseholdVisible(String transactionId, bool visible) async {
    final result = await _apiClient.safePatch(
      '/api/plaid-transactions/$transactionId/household-visible',
      {'household_visible': visible},
    );
    return result.map((payload) {
      if (payload['ok'] != true) {
        throw const NetworkException('Could not update transaction visibility.');
      }
    });
  }

  @override
  Future<Result<CsvImportPreview>> previewCsvImport(String accountId, String csvText) async {
    final result = await _apiClient.safePost(
      '/api/csv-import/preview',
      {'account_id': accountId, 'csv_text': csvText},
    );
    return result.map(CsvImportPreview.fromJson);
  }

  @override
  Future<Result<CsvImportResult>> confirmCsvImport(String accountId, List<CsvImportRow> rows, String filename) async {
    final result = await _apiClient.safePost(
      '/api/csv-import/confirm',
      {
        'account_id': accountId,
        'rows': rows.map((r) => r.toJson()).toList(growable: false),
        'filename': filename,
      },
    );
    return result.map(CsvImportResult.fromJson);
  }

  @override
  Future<Result<List<CsvImportHistory>>> loadCsvImportHistory() async {
    final result = await _apiClient.safeGet('/api/csv-import/history');
    return result.map(
      (payload) => extractRecords(payload, 'imports')
          .map(CsvImportHistory.fromJson)
          .toList(growable: false),
    );
  }
}