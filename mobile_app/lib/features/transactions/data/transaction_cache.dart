import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:cardsemble/features/accounts/domain/accounts_domain.dart';
import 'package:cardsemble/features/household/domain/household_domain.dart';
import 'package:cardsemble/features/transactions/domain/transactions_domain.dart';

/// Last successfully loaded transaction data, persisted so the app can paint
/// something on the first frame instead of always showing a spinner.
class TransactionCacheSnapshot {
  const TransactionCacheSnapshot({
    required this.people,
    required this.accounts,
    required this.transactions,
    required this.summaryTransactions,
    required this.savedAt,
  });

  final List<HouseholdPerson> people;
  final List<StatementAccount> accounts;
  final List<CardTransaction> transactions;
  final List<CardTransaction> summaryTransactions;
  final DateTime? savedAt;
}

class TransactionCache {
  static const _peopleKey = 'tx_cache_people_v1';
  static const _accountsKey = 'tx_cache_accounts_v1';
  static const _transactionsKey = 'tx_cache_transactions_v1';
  static const _summaryKey = 'tx_cache_summary_v1';
  static const _savedAtKey = 'tx_cache_saved_at_v1';

  Future<TransactionCacheSnapshot> read() async {
    final prefs = await SharedPreferences.getInstance();
    return TransactionCacheSnapshot(
      people: _decode(prefs.getStringList(_peopleKey), HouseholdPerson.fromJson),
      accounts: _decode(prefs.getStringList(_accountsKey), StatementAccount.fromJson),
      transactions: _decode(prefs.getStringList(_transactionsKey), CardTransaction.fromJson),
      summaryTransactions: _decode(prefs.getStringList(_summaryKey), CardTransaction.fromJson),
      savedAt: DateTime.tryParse(prefs.getString(_savedAtKey) ?? ''),
    );
  }

  Future<void> write({
    List<HouseholdPerson>? people,
    List<StatementAccount>? accounts,
    List<CardTransaction>? transactions,
    List<CardTransaction>? summaryTransactions,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (people != null) {
      await prefs.setStringList(_peopleKey, people.map((e) => jsonEncode(e.toJson())).toList());
    }
    if (accounts != null) {
      await prefs.setStringList(_accountsKey, accounts.map((e) => jsonEncode(e.toJson())).toList());
    }
    if (transactions != null) {
      await prefs.setStringList(
        _transactionsKey,
        transactions.map((e) => jsonEncode(e.toJson())).toList(),
      );
    }
    if (summaryTransactions != null) {
      await prefs.setStringList(
        _summaryKey,
        summaryTransactions.map((e) => jsonEncode(e.toJson())).toList(),
      );
    }
    await prefs.setString(_savedAtKey, DateTime.now().toIso8601String());
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_peopleKey);
    await prefs.remove(_accountsKey);
    await prefs.remove(_transactionsKey);
    await prefs.remove(_summaryKey);
    await prefs.remove(_savedAtKey);
  }

  static List<T> _decode<T>(
    List<String>? raw,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (raw == null) return <T>[];
    final result = <T>[];
    for (final entry in raw) {
      try {
        final decoded = jsonDecode(entry);
        if (decoded is Map<String, dynamic>) result.add(fromJson(decoded));
      } catch (_) {
        // Corrupt cache entries are ignored; the network load will replace them.
      }
    }
    return result;
  }
}
