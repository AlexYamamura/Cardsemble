import 'package:flutter/material.dart';
import 'package:cardsemble/core/utils/date_utils.dart';
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

  /// When the user clears all date chips, bound the load to a recent trailing
  /// window instead of downloading the entire transaction history.
  static const int _defaultHistoryDays = 60;

  /// Bounded window used when [dateRange] is null: roughly the last 60 days
  /// ending now. Keeps the server query bounded while still paginating normally.
  DateTimeRange get _defaultHistoryRange {
    final end = DateTime.now();
    final start = end.subtract(const Duration(days: _defaultHistoryDays));
    return DateTimeRange(start: start, end: end);
  }

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
  // Default filter: current month-to-date. Owned here so the transactions tab
  // has a date filter (and therefore a visible date chip) without depending on
  // the summary tab's lifecycle or post-frame callback ordering.
  DateTimeRange? _dateRange = monthRange(DateTime.now());
  String? _selectedAccountId;
  String? _selectedPersonId;

  // Coalesces concurrent loads and guards against stale responses.
  Future<void>? _activeLoadAll;
  int _transactionsGeneration = 0;
  bool _reloadScheduled = false;
  bool _hydrated = false;
  String? _hydratedScope;
  TransactionCacheSnapshot? _staleSnapshot;
  final Set<String> _staleSections = {};
  bool _summaryLoaded = false;

  /// Whether the ledger list has finished at least one successful load. Used by
  /// consumers (e.g. the Wallet tab's highest-cost computation) to avoid
  /// reading an empty list before the first fetch completes.
  bool _hasLoadedTransactions = false;

  // In-memory cache of split draft percentages keyed by transaction id. Keeps
  // the split dropdown from re-hitting the network on every open/close of the
  // expansion tile; rewritten when a split is saved.
  final Map<String, Map<String, double>> _splitDraftCache = {};

  List<CardTransaction> get transactions => _transactions;
  List<CardTransaction> get summaryTransactions => _summaryTransactions;
  List<HouseholdPerson> get people => _people;
  List<StatementAccount> get accounts => _accounts;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get isSummaryLoading => _isSummaryLoading;
  bool get hasMore => _hasMore;
  bool get hasLoadedTransactions => _hasLoadedTransactions;
  String? get error => _error;
  DateTime? get lastUpdated => _lastUpdated;
  DateTimeRange? get dateRange => _dateRange;

  String? get selectedAccountId => _selectedAccountId;
  String? get selectedPersonId => _selectedPersonId;

  /// True when at least one section was restored from an expired cache after a
  /// failed refresh. The UI can use this to disclose staleness without
  /// blocking first-frame rendering.
  bool get isShowingStaleData => _staleSections.isNotEmpty;

  List<CardTransaction> get filteredTransactions {
    final effectiveDateRange = _dateRange;
    return _transactions.where((tx) {
      // Only show charges that are due / not paid. Card payments to the card
      // itself (isPayment) are not spending, so they are excluded here and the
      // list no longer shows incoming/outgoing payment arrows.
      if (tx.isPayment) return false;
      if (_selectedAccountId != null && tx.accountId != _selectedAccountId) return false;
      if (_selectedPersonId != null && tx.assignedPersonId != _selectedPersonId) return false;
      if (tx.date == null) return false;
      final txDate = tx.parsedDate!;
      if (effectiveDateRange != null &&
          (txDate.isBefore(effectiveDateRange.start.subtract(const Duration(days: 1))) ||
          txDate.isAfter(effectiveDateRange.end.add(const Duration(days: 1))))) {
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
    // Re-selecting the same range is a no-op: it avoids redundant reloads and
    // keeps the active-filter chip stable when the user taps an already-active
    // month chip. `DateTimeRange` implements value equality on start/end.
    if (_dateRange == range) return;
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
    if (_selectedAccountId == accountId) return;
    _selectedAccountId = accountId;
    notifyListeners();
    _scheduleListReload();
  }

  void setPersonFilter(String? personId) {
    if (_selectedPersonId == personId) return;
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
     // A null dateRange means "no explicit date chip": bound the load to a recent
     // trailing window instead of downloading the entire transaction history. The
     // repository emits date_from/date_to and the SQL edge function applies them,
     // so only this window is returned, paginated by offset/limit with a
     // deterministic date desc, transaction_id asc order.
     final effectiveRange = _dateRange ?? _defaultHistoryRange;
     return TransactionQuery(
       limit: _pageSize,
       offset: offset,
       accountId: _selectedAccountId,
       dateFrom: effectiveRange.start,
       dateTo: effectiveRange.end,
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

    _syncCacheScope();
    final scope = _cache?.currentScope;
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
        if (generation != _transactionsGeneration || !_scopeStillValid(scope)) {
          return;
        }
        if (result.isFailure) {
          _error = result.failure.message;
          _applyStaleSection(transactions: true);
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

      if (generation != _transactionsGeneration || !_scopeStillValid(scope)) {
        return;
      }
      _transactions = reset ? collected : [..._transactions, ...collected];
      _offset = offset;
      _hasMore = hasMore;
      _hasLoadedTransactions = true;
      _staleSections.remove('transactions');
      _rememberGoodSection(transactions: _transactions);
      _lastUpdated = DateTime.now();
      _writeCache(scope: scope, transactions: true);
    } catch (e) {
      if (generation == _transactionsGeneration && _scopeStillValid(scope)) {
        _error = e.toString();
        _applyStaleSection(transactions: true);
      }
    } finally {
      if (generation == _transactionsGeneration && _scopeStillValid(scope)) {
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
    _syncCacheScope();
    final scope = _cache?.currentScope;
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
        if (generation != _summaryGeneration || !_scopeStillValid(scope)) {
          return;
        }
        if (result.isFailure) {
          _error = result.failure.message;
          _applyStaleSection(summary: true);
          _isSummaryLoading = false;
          notifyListeners();
          return;
        }
        final page = result.value;
        collected.addAll(page.items);
        offset += page.items.length;
        if (!page.hasMore || page.items.isEmpty) break;
      }

      if (generation != _summaryGeneration || !_scopeStillValid(scope)) {
        return;
      }
      _summaryTransactions = collected;
      _summaryLoaded = true;
      _staleSections.remove('summary');
      _rememberGoodSection(summary: _summaryTransactions);
      _lastUpdated = DateTime.now();
      _writeCache(scope: scope, summary: true);
    } catch (e) {
      if (generation == _summaryGeneration && _scopeStillValid(scope)) {
        _error = e.toString();
        _applyStaleSection(summary: true);
      }
    } finally {
      if (generation == _summaryGeneration && _scopeStillValid(scope)) {
        _isSummaryLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadAccounts() async {
    _syncCacheScope();
    final scope = _cache?.currentScope;
    try {
      final result = await _transactionRepository.loadAccounts();
      if (!_scopeStillValid(scope)) return;
      result.fold(
        (accounts) {
          _accounts = accounts;
          _staleSections.remove('accounts');
          _rememberGoodSection(accounts: accounts);
          _writeCache(scope: scope, accounts: true);
        },
        (failure) {
          _error = failure.message;
          _applyStaleSection(accounts: true);
        },
      );
      notifyListeners();
    } catch (e) {
      if (!_scopeStillValid(scope)) return;
      _error = e.toString();
      _applyStaleSection(accounts: true);
      notifyListeners();
    }
  }

  Future<void> loadPeople() async {
    _syncCacheScope();
    final scope = _cache?.currentScope;
    try {
      final result = await _householdRepository.loadPeople();
      if (!_scopeStillValid(scope)) return;
      result.fold(
        (people) {
          _people = people;
          _staleSections.remove('people');
          _rememberGoodSection(people: people);
          _writeCache(scope: scope, people: true);
        },
        (failure) {
          _error = failure.message;
          _applyStaleSection(people: true);
        },
      );
      notifyListeners();
    } catch (e) {
      if (!_scopeStillValid(scope)) return;
      _error = e.toString();
      _applyStaleSection(people: true);
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
    _syncCacheScope();
    await _hydrateFromCache();
    await Future.wait([loadPeople(), loadAccounts()]);
    await loadTransactions(reset: true);
  }

  /// Reloads everything the user can see (used after mutations that change
  /// derived data such as card display names).
  Future<void> refresh() async {
    _syncCacheScope();
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
    final scope = _cache?.currentScope;

    try {
      final result = await _transactionRepository.assignTransaction(transactionId, personId);
      if (!_scopeStillValid(scope)) return false;
      if (result.isFailure) {
        _error = result.failure.message;
        notifyListeners();
        return false;
      }
      // Use the server's resolved assignment: unassigning reassigns the
      // transaction to the household default person rather than leaving it null.
      final assignment = result.value;
      _applyAssignment(transactionId, assignment.personId, assignment.assignmentSource);
      _writeCache(
        scope: scope,
        transactions: true,
        summary: _summaryLoaded,
      );
      notifyListeners();
      return true;
    } catch (e) {
      if (!_scopeStillValid(scope)) return false;
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
      final scope = _cache?.currentScope;

      final outcome = await _saveTransactionSplit.call(
        transactionId: transactionId,
        totalAmount: totalAmount,
        percentages: percentages,
        orderedPersonIds: orderedPersonIds,
      );
      if (!_scopeStillValid(scope)) return false;

       return outcome.fold(
          (splits) async {
            // Rewrite the split draft cache with the saved percentages so the
            // dropdown re-opens instantly without a network call.
            _splitDraftCache[transactionId] = Map<String, double>.from(percentages);
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
    final scope = _cache?.currentScope;
    // Optimistic update with rollback on failure.
    _replaceTransaction(transactionId, (tx) => tx.copyWith(householdVisible: visible));
    notifyListeners();

    try {
      final result = await _transactionRepository.setHouseholdVisible(transactionId, visible);
      if (!_scopeStillValid(scope)) return false;
      if (result.isFailure) {
        _replaceTransaction(transactionId, (tx) => tx.copyWith(householdVisible: !visible));
        _error = result.failure.message;
        notifyListeners();
        return false;
      }
      _writeCache(
        scope: scope,
        transactions: true,
        summary: _summaryLoaded,
      );
      return true;
    } catch (e) {
      if (!_scopeStillValid(scope)) return false;
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
    // Snapshot hydration and stale fallback store unmodifiable lists. Rebuild
    // instead of index-assigning so cached rows can still be edited.
    final index = _transactions.indexWhere((t) => t.id == transactionId);
    if (index != -1) {
      final updated = List<CardTransaction>.of(_transactions);
      updated[index] = transform(updated[index]);
      _transactions = updated;
    }
    final summaryIndex =
        _summaryTransactions.indexWhere((t) => t.id == transactionId);
    if (summaryIndex != -1) {
      final updated = List<CardTransaction>.of(_summaryTransactions);
      updated[summaryIndex] = transform(updated[summaryIndex]);
      _summaryTransactions = updated;
    }
  }

  /// Clears all user-owned state. Called when the authenticated identity
  /// changes so the next session cannot render the previous user's data.
  void resetForSessionChange({bool clearFilters = true}) {
    _transactions = [];
    _summaryTransactions = [];
    _people = [];
    _accounts = [];
    _splitDraftCache.clear();
    _error = null;
    _lastUpdated = null;
    _isLoading = false;
    _isLoadingMore = false;
    _isSummaryLoading = false;
    _hasMore = true;
    _hasLoadedTransactions = false;
    _offset = 0;
    _summaryRange = null;
    _summaryLoaded = false;
    _staleSnapshot = null;
    _staleSections.clear();
    _hydrated = false;
    _hydratedScope = null;
    _activeLoadAll = null;
    // Invalidate any in-flight response from the previous identity.
    _transactionsGeneration++;
    _summaryGeneration++;

    if (clearFilters) {
      _dateRange = monthRange(DateTime.now());
      _selectedAccountId = null;
      _selectedPersonId = null;
    }
    notifyListeners();
  }

  /// Aligns [hydratedScope] with the cache's current identity, clearing old
  /// state when the signed-in user changes.
  void _syncCacheScope() {
    final cache = _cache;
    if (cache == null) return;

    final scope = cache.currentScope;
    if (_hydratedScope == scope) return;
    if (_hydrated || _hydratedScope != null) {
      resetForSessionChange();
    }
    _hydratedScope = scope;
  }

  bool _scopeStillValid(String? scope) {
    final cache = _cache;
    if (cache == null) return true;
    return cache.currentScope == scope;
  }

  void _applyStaleSection({
    bool people = false,
    bool accounts = false,
    bool transactions = false,
    bool summary = false,
  }) {
    final snapshot = _staleSnapshot;
    if (snapshot == null) return;

    if (people && _people.isEmpty && snapshot.people.hasData) {
      _people = snapshot.people.items;
      _staleSections.add('people');
    }
    if (accounts && _accounts.isEmpty && snapshot.accounts.hasData) {
      _accounts = snapshot.accounts.items;
      _staleSections.add('accounts');
    }
    if (transactions && _transactions.isEmpty && snapshot.transactions.hasData) {
      _transactions = snapshot.transactions.items;
      _hasMore = false;
      _staleSections.add('transactions');
    }
    if (summary &&
        _summaryTransactions.isEmpty &&
        snapshot.summaryTransactions.hasData) {
      _summaryTransactions = snapshot.summaryTransactions.items;
      _summaryLoaded = true;
      _staleSections.add('summary');
    }
  }

  /// Advances the fallback snapshot after a successful remote load.
  ///
  /// Without this, a later refresh failure could restore data from app startup
  /// instead of the most recent known-good response, including rows deleted
  /// server-side.
  void _rememberGoodSection({
    List<HouseholdPerson>? people,
    List<StatementAccount>? accounts,
    List<CardTransaction>? transactions,
    List<CardTransaction>? summary,
  }) {
    final cache = _cache;
    if (cache == null) return;

    final current = _staleSnapshot ?? const TransactionCacheSnapshot.empty();
    final savedAt = cache.now();
    _staleSnapshot = TransactionCacheSnapshot(
      people: people != null
          ? CachedSection<HouseholdPerson>(
              items: List<HouseholdPerson>.unmodifiable(people),
              savedAt: savedAt,
            )
          : current.people,
      accounts: accounts != null
          ? CachedSection<StatementAccount>(
              items: List<StatementAccount>.unmodifiable(accounts),
              savedAt: savedAt,
            )
          : current.accounts,
      transactions: transactions != null
          ? CachedSection<CardTransaction>(
              items: List<CardTransaction>.unmodifiable(transactions),
              savedAt: savedAt,
            )
          : current.transactions,
      summaryTransactions: summary != null
          ? CachedSection<CardTransaction>(
              items: List<CardTransaction>.unmodifiable(summary),
              savedAt: savedAt,
            )
          : current.summaryTransactions,
    );
  }

  Future<void> _hydrateFromCache() async {
    final cache = _cache;
    if (cache == null) return;

    final scope = cache.currentScope;
    if (scope == null) return;
    if (_hydrated && _hydratedScope == scope) return;
    if (_hydratedScope != null && _hydratedScope != scope) {
      resetForSessionChange();
    }

    try {
      final snapshot = await cache.read();
      if (!_scopeStillValid(scope)) return;

      _staleSnapshot = snapshot;
      final now = cache.now();
      var hydratedAny = false;
      if (_people.isEmpty && snapshot.people.isFresh(now, cache.ttl)) {
        _people = snapshot.people.items;
        hydratedAny = true;
      }
      if (_accounts.isEmpty && snapshot.accounts.isFresh(now, cache.ttl)) {
        _accounts = snapshot.accounts.items;
        hydratedAny = true;
      }
      if (_transactions.isEmpty &&
          snapshot.transactions.isFresh(now, cache.ttl)) {
        _transactions = snapshot.transactions.items;
        _hasMore = false;
        hydratedAny = true;
      }
      if (_summaryTransactions.isEmpty &&
          snapshot.summaryTransactions.isFresh(now, cache.ttl)) {
        _summaryTransactions = snapshot.summaryTransactions.items;
        _summaryLoaded = true;
        hydratedAny = true;
      }

      if (hydratedAny) _lastUpdated = snapshot.latestSavedAt;
      _hydrated = true;
      _hydratedScope = scope;
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
       // Serve the split draft from the local cache so re-opening the split
       // dropdown does not hit the network on every expand/collapse.
       final cached = _splitDraftCache[transactionId];
       if (cached != null) {
         return Future.value(Success(cached));
       }
       final scope = _cache?.currentScope;
       return _loadTransactionSplitDraft.call(
         transactionId: transactionId,
         totalAmount: totalAmount,
         participantIds: participantIds,
       ).then((result) {
         if (!_scopeStillValid(scope)) {
           return const FailureResult<Map<String, double>>(
             AuthFailure('The signed-in user changed while loading splits.'),
           );
         }
         result.fold(
           (percentages) => _splitDraftCache[transactionId] = Map<String, double>.from(percentages),
           (_) => null,
         );
         return result;
       });
    }

  /// Writes only the datasets that changed.
  ///
  /// The scope captured before the network call is passed explicitly so a late
  /// response from a previous user cannot be written into the active cache.
  void _writeCache({
    required String? scope,
    bool people = false,
    bool accounts = false,
    bool transactions = false,
    bool summary = false,
  }) {
    final cache = _cache;
    if (cache == null || scope == null) return;
    if (!_scopeStillValid(scope)) return;

    // A section restored from an expired snapshot must keep its original
    // timestamp. Re-stamping it after a successful local edit would make the
    // next launch treat old financial data as freshly loaded.
    final writePeople = people && !_staleSections.contains('people');
    final writeAccounts = accounts && !_staleSections.contains('accounts');
    final writeTransactions =
        transactions && !_staleSections.contains('transactions');
    final writeSummary = summary && !_staleSections.contains('summary');

    if (!writePeople && !writeAccounts && !writeTransactions && !writeSummary) {
      return;
    }

    // Fire-and-forget: caching must not delay the UI or surface errors.
    cache.write(
      scope: scope,
      people: writePeople
          ? List<HouseholdPerson>.unmodifiable(_people)
          : null,
      accounts: writeAccounts
          ? List<StatementAccount>.unmodifiable(_accounts)
          : null,
      transactions: writeTransactions
          ? List<CardTransaction>.unmodifiable(_transactions)
          : null,
      summaryTransactions: writeSummary
          ? List<CardTransaction>.unmodifiable(_summaryTransactions)
          : null,
    ).catchError((_) => false);
  }

  Future<void> clearCache() async {
    await _cache?.clearCurrentScope();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
