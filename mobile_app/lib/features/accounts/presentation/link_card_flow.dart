import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cardsemble/features/accounts/domain/entities/account.dart';
import 'package:cardsemble/features/accounts/presentation/accounts_notifier.dart';
import 'package:cardsemble/features/accounts/presentation/card_config_sheet.dart';
import 'package:cardsemble/features/transactions/presentation/transactions_notifier.dart';
import 'package:cardsemble/features/wallet/presentation/wallet_notifier.dart';

/// Runs the shared "link a card" flow and, for each newly connected account,
/// opens the per-card configuration sheet so the user can choose whether the
/// card is individual or household and set its default assignee.
///
/// Returns once all config sheets for new accounts have been dismissed and the
/// transaction/Pay totals have been refreshed.
Future<void> linkAndConfigureCard({
  required BuildContext context,
  required AccountsNotifier accounts,
  required TransactionsNotifier transactions,
  required WalletNotifier wallet,
}) async {
  final before = <String>{
    for (final account in accounts.statementSummary?.accounts ?? const [])
      account.accountId,
  };

  final linked = await accounts.linkAccount();
  if (!linked) return;

  final after = <String, StatementAccount>{};
  for (final account in accounts.statementSummary?.accounts ?? const []) {
    after[account.accountId] = account;
  }

  final newIds = after.keys.where((id) => !before.contains(id)).toList();

  for (final accountId in newIds) {
    if (!context.mounted) return;
    final account = after[accountId];
    if (account == null) continue;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => CardConfigSheet(
        accountId: account.accountId,
        accountName: account.displayName ?? account.accountName,
        cardType: account.cardType,
        defaultAssigneeMode: account.defaultAssigneeMode,
        defaultAssigneePersonId: account.defaultAssigneePersonId,
        people: transactions.people,
        accountsNotifier: accounts,
        transactionsNotifier: transactions,
      ),
    );
    if (!context.mounted) return;
  }

  // Refresh so the Pay total reflects any new card configuration.
  await transactions.loadAccounts();
  await wallet.load();
}
