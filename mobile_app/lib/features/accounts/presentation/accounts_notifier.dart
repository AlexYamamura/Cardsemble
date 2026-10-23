import 'package:flutter/material.dart';
import 'package:cardsemble/features/accounts/domain/accounts_domain.dart';

class AccountsNotifier extends ChangeNotifier {
  AccountsNotifier({
    required AccountRepository accountRepository,
    required PlaidLinkLauncher linkLauncher,
  })  : _accountRepository = accountRepository,
        _linkLauncher = linkLauncher;

  final AccountRepository _accountRepository;
  final PlaidLinkLauncher _linkLauncher;

  List<PlaidConnection> _connections = [];
  StatementCycleSummary? _statementSummary;
  WalletSummary? _walletSummary;
  bool _isLoading = false;
  bool _isLinking = false;
  String? _error;
  String? _warning;
  String? _linkToken;
  String? _lastLinkedInstitutionName;

  List<PlaidConnection> get connections => _connections;
  StatementCycleSummary? get statementSummary => _statementSummary;
  WalletSummary? get walletSummary => _walletSummary;
  bool get isLoading => _isLoading;
  bool get isLinking => _isLinking;
  String? get error => _error;
  String? get warning => _warning;
  String? get linkToken => _linkToken;
  String? get lastLinkedInstitutionName => _lastLinkedInstitutionName;

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

  Future<void> loadWalletSummary() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _accountRepository.loadWalletSummary();
      result.fold(
        (summary) => _walletSummary = summary,
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

  /// Runs the full Plaid Link flow: request a link token, open Plaid Link, and
  /// exchange the returned public token for a stored connection.
  Future<bool> linkAccount() async {
    if (_isLinking) {
      _error = 'A card link is already in progress.';
      notifyListeners();
      return false;
    }
    _isLinking = true;
    _error = null;
    _warning = null;
    _lastLinkedInstitutionName = null;
    notifyListeners();

    try {
      final created = await createLinkToken();
      if (!created) return false;

      final token = _linkToken;
      if (token == null) {
        _error = 'Could not create a card link session.';
        notifyListeners();
        return false;
      }

      final result = await _linkLauncher.launch(linkToken: token);
      clearLinkToken();

      if (!result.isSuccess) {
        _error = result.message ?? 'Could not link a card.';
        notifyListeners();
        return false;
      }

      final publicToken = result.publicToken;
      if (publicToken == null) {
        _error = 'Could not link a card.';
        notifyListeners();
        return false;
      }

      return await exchangePublicToken(
        publicToken: publicToken,
        institutionId: result.institutionId,
        institutionName: result.institutionName,
      );
    } finally {
      _isLinking = false;
      notifyListeners();
    }
  }

  Future<bool> syncConnections() async {
    _error = null;
    _warning = null;
    notifyListeners();

    try {
      final result = await _accountRepository.syncPlaidConnections();
      return await result.fold(
        (outcome) async {
          final itemWarning = outcome.hasWarnings
              ? _describeItemErrors(outcome.itemErrors)
              : null;
          await loadConnections();
          final reloadError = _error;
          await loadStatementCycles();
          await loadWalletSummary();
          final messages = <String>[];
          if (itemWarning != null) {
            messages.add('Sync finished with warnings: $itemWarning');
          }
          if (reloadError != null) {
            messages.add(
              'Sync finished, but the account list could not be reloaded: $reloadError',
            );
          }
          _error = null;
          _warning = messages.isEmpty ? null : _joinSentences(messages);
          notifyListeners();
          return true;
        },
        (failure) {
          _error = failure.message;
          _warning = null;
          notifyListeners();
          return false;
        },
      );
    } catch (e) {
      _error = e.toString();
      _warning = null;
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
    _warning = null;
    notifyListeners();

    try {
      final result = await _accountRepository.exchangePlaidPublicToken(
        publicToken: publicToken,
        institutionId: institutionId,
        institutionName: institutionName,
        platform: 'android',
      );
      return await result.fold(
        (outcome) async {
          if (institutionName != null) {
            _lastLinkedInstitutionName = institutionName;
          }
          await loadConnections();
          final connectionsError = _error;
          await loadStatementCycles();
          await loadWalletSummary();
          final statementCyclesError = _error;
          final details = [
            if (connectionsError != null) connectionsError,
            if (statementCyclesError != null) statementCyclesError,
          ].join('; ');
          final itemWarning = outcome.hasWarnings
              ? _describeItemErrors(outcome.itemErrors)
              : null;
          final messages = <String>[];
          final linked = _lastLinkedInstitutionName;
          if (itemWarning != null || details.isNotEmpty) {
            // Always confirm the link first, then list what needs attention.
            messages.add(
              linked == null ? 'Card linked successfully.' : '$linked connected.',
            );
          }
          if (details.isNotEmpty) {
            // The card is linked, but the refreshed state could not be read.
            messages.add(
              'Card linked, but the account list could not be reloaded: $details',
            );
          }
          if (itemWarning != null) {
            messages.add(itemWarning);
          }
          _error = null;
          _warning = messages.isEmpty ? null : _joinSentences(messages);
          notifyListeners();
          return true;
        },
        (failure) async {
          _error = failure.message;
          _warning = null;
          notifyListeners();
          return false;
        },
      );
    } catch (e) {
      _error = e.toString();
      _warning = null;
      notifyListeners();
      return false;
    }
  }

  /// Joins message fragments into a single readable sentence-per-clause string.
  String _joinSentences(List<String> messages) {
    return messages
        .map((message) => message.endsWith('.') ? message : '$message.')
        .join(' ');
  }

  /// Turns per-item sync errors into a short, de-duplicated sentence.
  String _describeItemErrors(List<PlaidItemSyncError> errors) {
    final seen = <String>{};
    final parts = <String>[];
    for (final error in errors) {
      final name = error.institutionName?.trim();
      final label = (name == null || name.isEmpty) ? 'A linked card' : name;
      final description = error.needsReauthentication
          ? '$label needs re-authentication.'
          : '$label could not finish syncing (${error.errorCode ?? 'unknown error'}).';
      if (seen.add(description)) {
        parts.add(description);
      }
    }
    return parts.join(' ');
  }

  Future<bool> updateDisplayName(String accountId, String? displayName) async {
    _error = null;
    _warning = null;
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

  /// Drops all user-owned state when the authenticated identity changes.
  void reset() {
    _connections = [];
    _statementSummary = null;
    _walletSummary = null;
    _isLoading = false;
    _isLinking = false;
    _error = null;
    _warning = null;
    _linkToken = null;
    _lastLinkedInstitutionName = null;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void clearWarning() {
    _warning = null;
    notifyListeners();
  }

  void clearLinkToken() {
    _linkToken = null;
    notifyListeners();
  }
}