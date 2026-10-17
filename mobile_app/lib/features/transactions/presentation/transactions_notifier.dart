import 'package:flutter/material.dart';
import 'package:cardsemble/features/transactions/domain/transactions_domain.dart';
import 'package:cardsemble/features/transactions/data/transaction_cache.dart';
import 'package:cardsemble/features/household/domain/household_domain.dart';
import 'package:cardsemble/features/accounts/domain/accounts_domain.dart';
import 'package:cardsemble/core/error/failure.dart';

class SummaryRow {
  const SummaryRow({
    required this.label,
    required this.currency,
    required this.amount,
    this.accountId,
    this.personId,
    this.color,
    this.displayName,
    this.plaidName,
    this.officialName,
    this.accountMask,
  });

  final String label;
  final String currency;
  final double amount;
  final String? accountId;
  final String? personId;
  final Color? color;
  final String? displayName;
  final String? plaidName;
  final String? officialName;
  final String? accountMask;
}

class TransactionsNotifier extends ChangeNotifier {
  final TransactionRepository _transactionRepository;
  final LoadTransactionSplitDraft _loadTransactionSplitDraft;
  final SaveTransactionSplit _saveTransactionSplit;
  final HouseholdRepository _householdRepository;
  final TransactionCache? _cache;

   TransactionsNotifier({
     required TransactionRepository transactionRepository,
     LoadTransactionSplitDraft? loadTransactionSplitDraft,
     SaveTransactionSplit? saveTransactionSplit,
     required HouseholdRepository householdRepository,
     TransactionCache? cache,
   }) : _transactionRepository = transactionRepository,
        _loadTransactionSplitDraft = loadTransactionSplitDraft ?? LoadTransactionSplitDraft(transactionRepository),
        _saveTransactionSplit = saveTransactionSplit ?? SaveTransactionSplit(transactionRepository),
        _householdRepository = householdRepository,
        _cache = cache;

  /// Page size for the transactions list. The server caps this at 500.
  static const int _pageSize = 100;

  // Transactions tab (paged, server-filtered).
  List<CardTransaction> _transactions = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _offset = 0;

  // Summary tab (all pages within a date range).
  List<CardTransaction> _summaryTransactions = [];
  bool _isSummaryLoading = false;
  DateTimeRange? _summaryRange;
  int _summaryGeneration = 0;

  List<HouseholdPerson> _people = [];
  List<StatementAccount> _accounts = [];
  String? _error;
  DateTime? _lastUpdated;
  CsvImportPreview? _csvPreview;
  bool _isPreviewing = false;
  DateTimeRange? _dateRange;
  String? _selectedAccountId;
  String? _selectedPersonId;

  // Coalesces concurrent loads and guards against stale responses.
  Future<void>? _activeLoadAll;
  int _transactionsGeneration = 0;
  bool _reloadScheduled = false;
  bool _hydrated = false;

  List<CardTransaction> get transactions => _transactions;
  List<CardTransaction> get summaryTransactions => _summaryTransactions;
  List<HouseholdPerson> get people => _people;
  List<StatementAccount> get accounts => _accounts;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get isSummaryLoading => _isSummaryLoading;
  bool get hasMore => _hasMore;
  String? get error => _error;
  DateTime? get lastUpdated => _lastUpdated;
  CsvImportPreview? get csvPreview => _csvPreview;
  bool get isPreviewing => _isPreviewing;
  DateTimeRange? get dateRange => _dateRange;

  DateTimeRange get _currentMonthRange {
     final now = DateTime.now();
     final start = DateTime(now.year, now.month, 1);
     final end = DateTime(now.year, now.month + 1, 0);
     return DateTimeRange(start: start, end: end);
   }

   DateTimeRange get effectiveDateRange => _dateRange ?? _currentMonthRange;
   String? get selectedAccountId => _selectedAccountId;
  String? get selectedPersonId => _selectedPersonId;

  List<CardTransaction> get filteredTransactions {
    final effectiveDateRange = _dateRange ?? _currentMonthRange;
    return _transactions.where((tx) {
      // Only show charges that are due / not paid. Card payments to the card
      // itself (isPayment) are not spending, so they are excluded here and the
      // list no longer shows incoming/outgoing payment arrows.
      if (tx.isPayment) return false;
      if (_selectedAccountId != null && tx.accountId != _selectedAccountId) return false;
      if (_selectedPersonId != null && tx.assignedPersonId != _selectedPersonId) return false;
         if (tx.date == null) return false;
         final txDate = tx.parsedDate!;
         if (txDate.isBefore(effectiveDateRange.start.subtract(const Duration(days: 1))) ||
             txDate.isAfter(effectiveDateRange.end.add(const Duration(days: 1)))) {
           return false;
         }
      return true;
    }).toList();
  }

  /// Map of currency code to total amount for positive (charge) transactions
  /// matching the current filters. Excludes pending and payment transactions.
  Map<String, double> get filteredTotalsByCurrency {
    final Map<String, double> totalsByCurrency = {};
    for (final tx in filteredTransactions) {
      // Only count positive charges (not pending, not payments)
      if (!tx.pending && tx.isPositive && !tx.isPayment) {
        final currency = tx.currency;
        totalsByCurrency[currency] = (totalsByCurrency[currency] ?? 0) + tx.amountValue;
      }
    }
    return totalsByCurrency;
  }

  /// Convenience getter for the total amount in the primary currency.
  /// Returns the total for the currency with the highest amount, or USD if no transactions.
  double get filteredTotal {
    if (filteredTotalsByCurrency.isEmpty) return 0.0;
    // Return the currency with the highest total amount
    return filteredTotalsByCurrency.values.reduce((a, b) => a > b ? a : b);
  }

  /// Convenience getter for the currency of the filtered total.
  /// Returns the currency with the highest amount, or USD if no transactions.
  String get filteredCurrency {
    if (filteredTotalsByCurrency.isEmpty) return 'USD';
    // Find the currency with the highest total
    String? maxCurrency;
    double maxAmount = 0.0;
    for (final entry in filteredTotalsByCurrency.entries) {
      if (entry.value > maxAmount) {
        maxAmount = entry.value;
        maxCurrency = entry.key;
      }
    }
    return maxCurrency ?? 'USD';
  }

  void setDateRange(DateTimeRange? range, {bool reloadList = true}) {
    _dateRange = range;
    notifyListeners();
    if (reloadList) _scheduleListReload();
  }

  void clearDateRange() {
    _dateRange = null;
    notifyListeners();
    _scheduleListReload();
  }

  void setAccountFilter(String? accountId) {
    _selectedAccountId = accountId;
    notifyListeners();
    _scheduleListReload();
  }

  void setPersonFilter(String? personId) {
    _selectedPersonId = personId;
    notifyListeners();
    _scheduleListReload();
  }

  void clearAllFilters() {
    _selectedAccountId = null;
    _selectedPersonId = null;
    _dateRange = null;
    notifyListeners();
    _scheduleListReload();
  }

  bool get hasActiveFilters => _selectedAccountId != null || _selectedPersonId != null || _dateRange != null;

   TransactionQuery _queryFor({required int offset}) {
     final effectiveDateRange = _dateRange ?? _currentMonthRange;
     return TransactionQuery(
       limit: _pageSize,
       offset: offset,
        accountId: _selectedAccountId,
        dateFrom: effectiveDateRange.start,
        dateTo: effectiveDateRange.end,
      );
   }

  List<SummaryRow> get spendingByAccount {
    final Map<String, Map<String, dynamic>> grouped = {};
    for (final tx in _summaryTransactions) {
      if (tx.accountId == null) continue;
      final key = tx.accountId!;
      if (!grouped.containsKey(key)) {
        grouped[key] = {
          'label': tx.displayName ?? tx.accountName ?? tx.plaidName ?? 'Unknown',
          'currency': tx.currency,
          'amount': 0.0,
          'accountId': tx.accountId,
          'displayName': tx.displayName,
          'plaidName': tx.plaidName,
          'officialName': tx.officialName,
          'accountMask': tx.accountMask,
        };
      }
      grouped[key]!['amount'] = (grouped[key]!['amount'] as double) + tx.amountValue;
    }
    return grouped.entries.map((e) => SummaryRow(
      label: e.value['label'] as String,
      currency: e.value['currency'] as String,
      amount: e.value['amount'] as double,
      accountId: e.value['accountId'] as String,
      displayName: e.value['displayName'] as String?,
      plaidName: e.value['plaidName'] as String?,
      officialName: e.value['officialName'] as String?,
      accountMask: e.value['accountMask'] as String?,
    )).toList()..sort((a, b) => b.amount.compareTo(a.amount));
  }

  List<SummaryRow> get spendingByPerson {
    final Map<String, Map<String, dynamic>> grouped = {};
    for (final tx in _summaryTransactions) {
      final personId = tx.assignedPersonId ?? '__default__';
      if (!grouped.containsKey(personId)) {
        final person = _people.firstWhere((p) => p.id == personId, orElse: () => HouseholdPerson(id: '', displayName: '', isDefault: false));
        grouped[personId] = {
          'label': person.id.isEmpty ? 'Household default' : person.displayName,
          'currency': tx.currency,
          'amount': 0.0,
          'personId': person.id.isEmpty ? null : person.id,
          'color': person.id.isEmpty ? null : _personColor(person.id, _people),
        };
      }
      grouped[personId]!['amount'] = (grouped[personId]!['amount'] as double) + tx.amountValue;
    }
    return grouped.entries.map((e) => SummaryRow(
      label: e.value['label'] as String,
      currency: e.value['currency'] as String,
      amount: e.value['amount'] as double,
      personId: e.value['personId'] as String?,
      color: e.value['color'] as Color?,
    )).toList()..sort((a, b) => b.amount.compareTo(a.amount));
  }

  Color _personColor(String personId, List<HouseholdPerson> people) {
    const palette = [
      Color(0xFF176B5B),
      Color(0xFF4F46A5),
      Color(0xFFC2415D),
      Color(0xFF146A8A),
      Color(0xFF8A4E9B),
      Color(0xFF966000),
    ];
    final index = people.indexWhere((person) => person.id == personId);
    if (index < 0) return palette.first;
    return palette[index % palette.length];
  }

  /// Schedules a single list reload for a batch of filter changes (e.g. the
  /// summary drill-down sets account, person and date in sequence).
  void _scheduleListReload() {
    if (_reloadScheduled) return;
    _reloadScheduled = true;
    Future.microtask(() {
      _reloadScheduled = false;
      loadTransactions(reset: true);
    });
  }

  /// Loads one page of the transactions list. With [reset] the list is replaced;
  /// otherwise the next page is appended. When the client-side person filter is
  /// active every page is fetched so the filter operates on the full set.
  Future<void> loadTransactions({bool reset = false}) async {
    if (!reset && !_hasMore) return;
    if (!reset && (_isLoading || _isLoadingMore)) return;

    final generation = ++_transactionsGeneration;


    if (reset) {
      _isLoading = true;
    } else {
      _isLoadingMore = true;
    }
    _error = null;
    notifyListeners();

    try {
      final collected = <CardTransaction>[];
      var offset = reset ? 0 : _offset;
      var hasMore = true;

      while (true) {
        final result = await _transactionRepository.loadTransactions(_queryFor(offset: offset));
        if (generation != _transactionsGeneration) return;
        if (result.isFailure) {
          _error = result.failure.message;
          _isLoading = false;
          _isLoadingMore = false;
          notifyListeners();
          return;
        }
        final page = result.value;
        collected.addAll(page.items);
         offset += page.items.length;
         if (!page.hasMore || page.items.isEmpty) {
           hasMore = false;
           break;
         }
      }

      if (generation != _transactionsGeneration) return;
      _transactions = reset ? collected : [..._transactions, ...collected];
      _offset = offset;
      _hasMore = hasMore;
      _lastUpdated = DateTime.now();
      _writeCache();
    } catch (e) {
      if (generation == _transactionsGeneration) _error = e.toString();
    } finally {
      if (generation == _transactionsGeneration) {
        _isLoading = false;
        _isLoadingMore = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMoreTransactions() async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;
    await loadTransactions();
  }

  /// Loads every page of transactions within [range] for the summary tab. The
  /// server applies the date bounds, so this never downloads the whole ledger.
  Future<void> loadSummaryTransactions(DateTimeRange range) async {
    _summaryRange = range;
    final generation = ++_summaryGeneration;
    _isSummaryLoading = true;
    notifyListeners();

    try {
      final collected = <CardTransaction>[];
      var offset = 0;
      while (true) {
        final result = await _transactionRepository.loadTransactions(
          TransactionQuery(
            limit: _pageSize,
            offset: offset,
            dateFrom: range.start,
            dateTo: range.end,
          ),
        );
        if (generation != _summaryGeneration) return;
        if (result.isFailure) {
          _error = result.failure.message;
          _isSummaryLoading = false;
          notifyListeners();
          return;
        }
        final page = result.value;
        collected.addAll(page.items);
        offset += page.items.length;
        if (!page.hasMore || page.items.isEmpty) break;
      }

      if (generation != _summaryGeneration) return;
      _summaryTransactions = collected;
      _lastUpdated = DateTime.now();
      _writeCache();
    } catch (e) {
      if (generation == _summaryGeneration) _error = e.toString();
    } finally {
      if (generation == _summaryGeneration) {
        _isSummaryLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadAccounts() async {
    try {
      final result = await _transactionRepository.loadAccounts();
      result.fold(
        (accounts) {
          _accounts = accounts;
          _writeCache();
        },
        (failure) => _error = failure.message,
      );
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> loadPeople() async {
    try {
      final result = await _householdRepository.loadPeople();
      result.fold(
        (people) {
          _people = people;
          _writeCache();
        },
        (failure) => _error = failure.message,
      );
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Loads the shared data once. Concurrent callers (both tabs build at
  /// startup) share the same future instead of firing duplicate fetches.
  Future<void> loadAll() {
    final existing = _activeLoadAll;
    if (existing != null) return existing;
    final future = _runLoadAll();
    _activeLoadAll = future;
    future.whenComplete(() {
      if (identical(_activeLoadAll, future)) _activeLoadAll = null;
    });
    return future;
  }

  Future<void> _runLoadAll() async {
    await _hydrateFromCache();
    await Future.wait([loadPeople(), loadAccounts()]);
    await loadTransactions(reset: true);
  }

  /// Reloads everything the user can see (used after mutations that change
  /// derived data such as card display names).
  Future<void> refresh() async {
    await Future.wait([loadPeople(), loadAccounts()]);
    await loadTransactions(reset: true);
    await _reloadSummary();
  }

  Future<void> _reloadSummary() async {
    final range = _summaryRange;
    if (range != null) {
      await loadSummaryTransactions(range);
    }
  }

  Future<bool> assignTransaction(String transactionId, String? personId) async {
    _error = null;
    notifyListeners();

    try {
      final result = await _transactionRepository.assignTransaction(transactionId, personId);
      if (result.isFailure) {
        _error = result.failure.message;
        notifyListeners();
        return false;
      }
      // Use the server's resolved assignment: unassigning reassigns the
      // transaction to the household default person rather than leaving it null.
      final assignment = result.value;
      _applyAssignment(transactionId, assignment.personId, assignment.assignmentSource);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

   void _applyAssignment(String transactionId, String? personId, String source) {
     _replaceTransaction(
       transactionId,
       (tx) => tx.copyWith(
         assignedPersonId: personId,
         assignmentSource: source,
         hasSplits: false,
       ),
     );
   }

    Future<bool> saveTransactionSplit({
      required String transactionId,
      required double totalAmount,
      required Map<String, double> percentages,
      required List<String> orderedPersonIds,
    }) async {
      _error = null;
      notifyListeners();

      final outcome = await _saveTransactionSplit.call(
        transactionId: transactionId,
        totalAmount: totalAmount,
        percentages: percentages,
        orderedPersonIds: orderedPersonIds,
      );
       return outcome.fold(
         (splits) async {
           await loadTransactions(reset: true);
           await _reloadSummary();
           return true;
         },
         (failure) async {
           _error = failure.message;
           notifyListeners();
           return false;
         },
       );
    }

  Future<bool> setHouseholdVisible(String transactionId, bool visible) async {
    // Optimistic update with rollback on failure.
    _replaceTransaction(transactionId, (tx) => tx.copyWith(householdVisible: visible));
    notifyListeners();

    try {
      final result = await _transactionRepository.setHouseholdVisible(transactionId, visible);
      if (result.isFailure) {
        _replaceTransaction(transactionId, (tx) => tx.copyWith(householdVisible: !visible));
        _error = result.failure.message;
        notifyListeners();
        return false;
      }
      return true;
    } catch (e) {
      _replaceTransaction(transactionId, (tx) => tx.copyWith(householdVisible: !visible));
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  void _replaceTransaction(
    String transactionId,
    CardTransaction Function(CardTransaction) transform,
  ) {
    final index = _transactions.indexWhere((t) => t.id == transactionId);
    if (index != -1) {
      _transactions[index] = transform(_transactions[index]);
    }
    final summaryIndex = _summaryTransactions.indexWhere((t) => t.id == transactionId);
    if (summaryIndex != -1) {
      _summaryTransactions[summaryIndex] = transform(_summaryTransactions[summaryIndex]);
    }
  }

   Future<Result<CsvImportPreview>> previewCsvImport(String accountId, String csvText) async {
     _isPreviewing = true;
     _csvPreview = null;
     _error = null;
     notifyListeners();

     try {
       final result = await _transactionRepository.previewCsvImport(accountId, csvText);
       return result.fold(
         (preview) {
           _csvPreview = preview;
           _isPreviewing = false;
           notifyListeners();
           return Success(preview);
         },
         (failure) {
           _error = failure.message;
           _isPreviewing = false;
           notifyListeners();
           return FailureResult(failure);
         },
       );
     } catch (e) {
       _error = e.toString();
       _isPreviewing = false;
       notifyListeners();
       return FailureResult(UnknownFailure(e.toString()));
     }
   }

   Future<Result<CsvImportResult>> confirmCsvImport(String accountId, List<CsvImportRow> rows, String filename) async {
     _error = null;
     notifyListeners();

     try {
       final result = await _transactionRepository.confirmCsvImport(accountId, rows, filename);
       if (result.isFailure) {
         _error = result.failure.message;
         notifyListeners();
         return FailureResult(result.failure);
       }
       await loadTransactions(reset: true);
       await _reloadSummary();
       return Success(result.value);
     } catch (e) {
       _error = e.toString();
       notifyListeners();
       return FailureResult(UnknownFailure(e.toString()));
     }
   }

  Future<void> loadCsvHistory() async {
    try {
      final result = await _transactionRepository.loadCsvImportHistory();
      result.fold(
        (history) => debugPrint('History: $history'),
        (failure) => _error = failure.message,
      );
    } catch (e) {
      _error = e.toString();
    }
  }

  Future<void> _hydrateFromCache() async {
    final cache = _cache;
    if (cache == null || _hydrated) return;
    _hydrated = true;
    try {
      final snapshot = await cache.read();
      if (_people.isEmpty && snapshot.people.isNotEmpty) _people = snapshot.people;
      if (_accounts.isEmpty && snapshot.accounts.isNotEmpty) _accounts = snapshot.accounts;
      if (_transactions.isEmpty && snapshot.transactions.isNotEmpty) {
        _transactions = snapshot.transactions;
        _hasMore = false;
      }
      if (_summaryTransactions.isEmpty && snapshot.summaryTransactions.isNotEmpty) {
        _summaryTransactions = snapshot.summaryTransactions;
      }
      _lastUpdated = snapshot.savedAt;
      notifyListeners();
    } catch (_) {
      // Cache hydration is best-effort and must never block a network load.
    }
  }

    Future<Result<Map<String, double>>> loadSplitDraft({
      required String transactionId,
      required double totalAmount,
      required List<String> participantIds,
    }) {
      return _loadTransactionSplitDraft.call(
        transactionId: transactionId,
        totalAmount: totalAmount,
        participantIds: participantIds,
      );
    }

   void _writeCache() {
    final cache = _cache;
    if (cache == null) return;
    // Fire-and-forget: caching must not delay the UI or surface errors.
    cache.write(
      people: _people,
      accounts: _accounts,
      transactions: _transactions,
      summaryTransactions: _summaryTransactions,
    ).catchError((_) {});
  }

  Future<void> clearCache() async {
    await _cache?.clear();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void clearPreview() {
    _csvPreview = null;
    notifyListeners();
  }
}
