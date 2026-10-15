import 'package:flutter/material.dart';
import 'package:cardsemble/features/accounts/domain/accounts_domain.dart';

class AccountsNotifier extends ChangeNotifier {
  AccountsNotifier({
    required AccountRepository accountRepository,
  }) : _accountRepository = accountRepository;

  final AccountRepository _accountRepository;

  List<PlaidConnection> _connections = [];
  StatementCycleSummary? _statementSummary;
  bool _isLoading = false;
  String? _error;
  String? _linkToken;

  List<PlaidConnection> get connections => _connections;
  StatementCycleSummary? get statementSummary => _statementSummary;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get linkToken => _linkToken;

  Future<void> loadConnections() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _accountRepository.loadPlaidConnections();
      result.fold(
        (connections) => _connections = connections,
        (failure) => _error = failure.message,
      );
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadStatementCycles() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _accountRepository.loadStatementCycles();
      result.fold(
        (summary) => _statementSummary = summary,
        (failure) => _error = failure.message,
      );
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createLinkToken() async {
    _error = null;
    _linkToken = null;
    notifyListeners();

    try {
      final result = await _accountRepository.createPlaidLinkToken('android');
      return result.fold(
        (token) {
          _linkToken = token;
          notifyListeners();
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

  Future<bool> syncConnections() async {
    _error = null;
    notifyListeners();

    try {
      final result = await _accountRepository.syncPlaidConnections();
      return result.fold(
        (_) {
          loadConnections();
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

  Future<bool> exchangePublicToken({
    required String publicToken,
    String? institutionId,
    String? institutionName,
  }) async {
    _error = null;
    notifyListeners();

    try {
      final result = await _accountRepository.exchangePlaidPublicToken(
        publicToken: publicToken,
        institutionId: institutionId,
        institutionName: institutionName,
        platform: 'android',
      );
      return result.fold(
        (_) {
          loadConnections();
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

  Future<bool> updateDisplayName(String accountId, String? displayName) async {
    _error = null;
    notifyListeners();

    try {
      final result = await _accountRepository.updateCreditCardDisplayName(accountId, displayName);
      return result.fold(
        (_) {
          loadStatementCycles();
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

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void clearLinkToken() {
    _linkToken = null;
    notifyListeners();
  }
}