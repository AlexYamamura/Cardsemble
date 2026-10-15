import 'package:flutter/material.dart';
import 'package:cardsemble/features/transactions/domain/transactions_domain.dart';
import 'package:cardsemble/features/household/domain/household_domain.dart';
import 'package:cardsemble/features/accounts/domain/accounts_domain.dart';

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
  TransactionsNotifier({
    required TransactionRepository transactionRepository,
    required HouseholdRepository householdRepository,
  }) : _transactionRepository = transactionRepository,
       _householdRepository = householdRepository;

  final TransactionRepository _transactionRepository;
  final HouseholdRepository _householdRepository;

  List<CardTransaction> _transactions = [];
  List<HouseholdPerson> _people = [];
  List<StatementAccount> _accounts = [];
  bool _isLoading = false;
  String? _error;
  CsvImportPreview? _csvPreview;
  bool _isPreviewing = false;
  DateTimeRange? _dateRange;
  String? _selectedAccountId;
  String? _selectedPersonId;

  List<CardTransaction> get transactions => _transactions;
  List<HouseholdPerson> get people => _people;
  List<StatementAccount> get accounts => _accounts;
  bool get isLoading => _isLoading;
  String? get error => _error;
  CsvImportPreview? get csvPreview => _csvPreview;
  bool get isPreviewing => _isPreviewing;
  DateTimeRange? get dateRange => _dateRange;
  String? get selectedAccountId => _selectedAccountId;
  String? get selectedPersonId => _selectedPersonId;

  List<CardTransaction> get filteredTransactions {
    return _transactions.where((tx) {
      if (_selectedAccountId != null && tx.accountId != _selectedAccountId) return false;
      if (_selectedPersonId != null && tx.assignedPersonId != _selectedPersonId) return false;
      if (_dateRange != null) {
        if (tx.date == null) return false;
        final txDate = tx.parsedDate!;
        if (txDate.isBefore(_dateRange!.start.subtract(const Duration(days: 1))) ||
            txDate.isAfter(_dateRange!.end.add(const Duration(days: 1)))) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  void setDateRange(DateTimeRange? range) {
    _dateRange = range;
    notifyListeners();
  }

  void clearDateRange() {
    _dateRange = null;
    notifyListeners();
  }

  void setAccountFilter(String? accountId) {
    _selectedAccountId = accountId;
    notifyListeners();
  }

  void setPersonFilter(String? personId) {
    _selectedPersonId = personId;
    notifyListeners();
  }

  void clearAllFilters() {
    _selectedAccountId = null;
    _selectedPersonId = null;
    _dateRange = null;
    notifyListeners();
  }

  bool get hasActiveFilters => _selectedAccountId != null || _selectedPersonId != null || _dateRange != null;

  List<SummaryRow> get spendingByAccount {
    final Map<String, Map<String, dynamic>> grouped = {};
    for (final tx in _transactions) {
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
    for (final tx in _transactions) {
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

  Future<void> loadTransactions() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _transactionRepository.loadTransactions();
      result.fold(
        (transactions) => _transactions = transactions,
        (failure) => _error = failure.message,
      );
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadAccounts() async {
    try {
      final result = await _transactionRepository.loadAccounts();
      result.fold(
        (accounts) => _accounts = accounts,
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
        (people) => _people = people,
        (failure) => _error = failure.message,
      );
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> loadAll() async {
    await Future.wait([
      loadPeople(),
      loadAccounts(),
    ]);
    await loadTransactions();
  }

  Future<bool> assignTransaction(String transactionId, String? personId) async {
    _error = null;
    notifyListeners();

    try {
      final result = await _transactionRepository.assignTransaction(transactionId, personId);
      return result.fold(
        (_) {
          final index = _transactions.indexWhere((t) => t.id == transactionId);
          if (index != -1) {
            _transactions[index] = CardTransaction(
              id: _transactions[index].id,
              accountId: _transactions[index].accountId,
              accountName: _transactions[index].accountName,
              displayName: _transactions[index].displayName,
              plaidName: _transactions[index].plaidName,
              officialName: _transactions[index].officialName,
              accountMask: _transactions[index].accountMask,
              amount: _transactions[index].amount,
              currency: _transactions[index].currency,
              date: _transactions[index].date,
              name: _transactions[index].name,
              merchant: _transactions[index].merchant,
              pending: _transactions[index].pending,
              transactionCode: _transactions[index].transactionCode,
              assignedPersonId: personId,
              assignmentSource: personId != null ? 'manual' : 'default',
              hasSplits: _transactions[index].hasSplits,
            );
            notifyListeners();
          }
          return true;
        },
        (failure) {
          _error = failure.message;
          notifyListeners();
          return false;
        },
      );
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> assignTransactionSplit(String transactionId, List<TransactionSplit> splits) async {
    _error = null;
    notifyListeners();

    try {
      final result = await _transactionRepository.assignTransactionSplit(transactionId, splits);
      return result.fold(
        (_) {
          loadTransactions();
          return true;
        },
        (failure) {
          _error = failure.message;
          notifyListeners();
          return false;
        },
      );
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> previewCsvImport(String accountId, String csvText) async {
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
          return true;
        },
        (failure) {
          _error = failure.message;
          _isPreviewing = false;
          notifyListeners();
          return false;
        },
      );
    } catch (e) {
      _error = e.toString();
      _isPreviewing = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> confirmCsvImport(String accountId, List<CsvImportRow> rows, String filename) async {
    _error = null;
    notifyListeners();

    try {
      final result = await _transactionRepository.confirmCsvImport(accountId, rows, filename);
      return result.fold(
        (result) {
          loadTransactions();
          return true;
        },
        (failure) {
          _error = failure.message;
          notifyListeners();
          return false;
        },
      );
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
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

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void clearPreview() {
    _csvPreview = null;
    notifyListeners();
  }
}