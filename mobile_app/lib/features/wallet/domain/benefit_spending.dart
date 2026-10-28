// Pure-domain helper that computes how much a wallet card's user has spent
// on transactions matching the card's catalog benefits.
//
// This replaces the deprecated "Payment due" metric (which relied on Plaid's
// /liabilities/get) with a "Spending toward benefits" metric derived from the
// loaded transaction list. The computation is side-effect-free so it can be
// unit-tested without any Flutter bindings.
library;

import 'package:cardsemble/core/utils/category_key.dart';
import 'package:cardsemble/features/transactions/domain/entities/transaction.dart';
import 'package:cardsemble/features/wallet/domain/wallet_card.dart';

/// The result of matching a card's benefit categories against the user's
/// loaded transactions.
class WalletBenefitSpending {
  const WalletBenefitSpending({
    required this.amountCentsByCurrency,
    required this.transactionCount,
    required this.matchedCategoryKeys,
  });

  /// Total spending per currency, keyed by ISO currency code.
  /// Values are minor currency units (cents). Always non-null when this
  /// object is present (may contain zero-value currencies).
  final Map<String, int> amountCentsByCurrency;

  /// Number of transactions that matched at least one benefit category.
  final int transactionCount;

  /// Set of canonical category keys that had at least one matching transaction.
  final Set<String> matchedCategoryKeys;

  /// Total spending across all currencies (in cents of the primary currency).
  /// Returns 0 if no spending was found.
  int get totalAmountCents {
    if (amountCentsByCurrency.isEmpty) return 0;
    // Return the first currency's value as the headline total.
    return amountCentsByCurrency.values.first;
  }

  /// Whether any transactions matched benefit categories.
  bool get hasSpending => transactionCount > 0;
}

/// Computes spending toward this card's benefits from the loaded transaction list.
///
/// Returns `null` when the card has no statement account (cannot match
/// transactions to the card) or has no mappable benefit categories.
///
/// When the transaction list is empty (either because it hasn't loaded yet
/// or because the user has no transactions), returns a zero-result
/// [WalletBenefitSpending] so the caller can distinguish "loading/empty" from
/// "card has no mappable benefits."
WalletBenefitSpending? calculateBenefitSpending({
  required WalletCard card,
  required List<CardTransaction> transactions,
}) {
  final statementAccount = card.statementAccount;
  if (statementAccount?.accountId == null) return null;

  final accountId = statementAccount!.accountId;
  final benefits = card.benefits;
  if (benefits.isEmpty) return null;

  // Build the set of canonical category keys this card's benefits cover.
  final benefitKeys = <String>{};
  for (final benefit in benefits) {
    final category = benefit.category;
    if (category != null && category.isNotEmpty) {
      benefitKeys.add(normalizeCategoryKey(category));
    } else {
      // Fall back to the benefit title if no explicit category.
      final title = benefit.title;
      if (title.isNotEmpty) {
        benefitKeys.add(normalizeCategoryKey(title));
      }
    }
  }
  if (benefitKeys.isEmpty) return null;

  final byCurrency = <String, int>{};
  var matchCount = 0;
  final matchedKeys = <String>{};

  for (final tx in transactions) {
    // Only count positive (charge) transactions that are posted and not payments.
    if (!tx.isPositive) continue;
    if (tx.pending) continue;
    if (tx.isPayment) continue;

    // Match by account so we only count this card's transactions.
    if (tx.accountId != accountId) continue;

    // Derive the transaction's category key from Plaid PFC fields.
    final txKey = categoryKeyFromPlaid(
      primary: tx.personalFinanceCategoryPrimary,
      detailed: tx.personalFinanceCategoryDetailed,
    );

    // Fall back to merchant name if no PFC is available.
    final effectiveKey = txKey ??
        (tx.merchant != null && tx.merchant!.isNotEmpty
            ? normalizeCategoryKey(tx.merchant!)
            : null);

    if (effectiveKey != null && benefitKeys.contains(effectiveKey)) {
      matchedKeys.add(effectiveKey);
      final amount = tx.amountValue;
      final cents = (amount.abs() * 100).round();
      final currency = tx.currency;
      byCurrency.update(
        currency,
        (existing) => existing + cents,
        ifAbsent: () => cents,
      );
      matchCount++;
    }
  }

  return WalletBenefitSpending(
    amountCentsByCurrency: byCurrency,
    transactionCount: matchCount,
    matchedCategoryKeys: matchedKeys,
  );
}
