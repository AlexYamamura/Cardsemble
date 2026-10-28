// View models for the Wallet tab.
//
// The Wallet tab is the landing page: it shows the cards that are actually in
// the user's wallet (connected Plaid accounts) enriched with reference data
// from the card catalog (the same source used by the Research tab), plus
// household cards owned by other household members.
//
// Balance, credit limit, and utilization are no longer shown on card panels:
// they were sourced from the deprecated /liabilities/get Plaid product. The
// wallet summary now surfaces only card count and the highest recent payment
// (computed client-side from loaded transactions). Catalog benefits and
// welcome-bonus spend are tracked locally in SharedPreferences.
import 'package:cardsemble/features/accounts/domain/entities/account.dart';
import 'package:cardsemble/features/card_catalog/domain/entities/card_catalog_card.dart';

/// Result of matching a connected account to the card_catalog table.
enum CatalogMatchStatus {
  /// A catalog entry was found for this card.
  matched,
  /// No catalog entry was found; benefits and bonus tracking are unavailable.
  unmatched,
}

/// One card shown on the Wallet tab.
///
/// `id` is the stable key used for local UI state (benefit usage, bonus spend)
/// and prefers the statement account id, falling back to the Plaid item id.
class WalletCard {
  const WalletCard({
    required this.id,
    required this.displayName,
    this.issuer,
    this.network,
    this.mask,
    this.subtype,
    this.status = 'connected',
    this.catalogCard,
    this.statementAccount,
    this.currency,
    this.paymentDueDate,
    this.itemId,
    this.benefits = const [],
    this.welcomeBonus,
    this.catalogMatchStatus = CatalogMatchStatus.unmatched,
  });

  final String id;
  final String displayName; // catalog name, or the institution name when unmatched
  final String? issuer;
  final String? network;
  final String? mask;
  final String? subtype;
  final String status;
  final CardCatalogCard? catalogCard;
  final StatementAccount? statementAccount;

  final String? currency;

  /// Payment due date for the current statement cycle, null when unavailable
  /// (sourced from the now-deprecated liabilities sync).
  final DateTime? paymentDueDate;

  /// The Plaid item_id for this card's connection. Used to trigger a per-item
  /// resync or re-authentication via Plaid Link in update mode.
  final String? itemId;

  /// Catalog benefits annotated with locally-tracked usage state.
  final List<WalletBenefit> benefits;

  /// Catalog welcome bonus annotated with locally-tracked spend.
  final WalletBonus? welcomeBonus;

  /// Whether this connected card matched a `card_catalog` row. When `unmatched`,
  /// benefits and welcome-bonus tracking are unavailable for this card.
  final CatalogMatchStatus catalogMatchStatus;

  /// Whether a payment due date is available.
  bool get hasPaymentDue => paymentDueDate != null;

  bool get isCatalogMatched => catalogMatchStatus == CatalogMatchStatus.matched;

  /// Last four digits when a mask is available.
  String? get lastFour {
    final m = mask;
    if (m == null || m.length < 4) return null;
    return m.substring(m.length - 4);
  }

  /// Whether this card's underlying Plaid connection needs re-authentication.
  bool get needsRelink => status == 'error' || status == 'reauth';
}

/// One catalog benefit with its locally-tracked usage state.
///
/// Tracks statement credits that need to be actively used (e.g. "$200 hotel
/// credit, expires semi-annually"). `used` reflects whether the credit has been
/// consumed within the current period; `expiresAt` is the period end date.
class WalletBenefit {
  const WalletBenefit({
    required this.id,
    required this.title,
    this.category,
    this.source,
    this.description,
    this.amount,
    this.currency,
    this.expiresAt,
    this.periodLength,
    this.used = false,
    this.usedAt,
  });

  final String id;
  final String title;
  final String? category;
  final String? source;
  final String? description;

  /// Credit amount in minor currency units (e.g. 20000 for $200.00), when the
  /// benefit is a statement credit with a dollar value.
  final int? amount;

  /// Currency code for [amount].
  final String? currency;

  /// When the credit expires / the current period ends.
  final DateTime? expiresAt;

  /// How often the credit resets: "monthly", "semi-annually", "annually", etc.
  final String? periodLength;

  /// Whether the credit has been used within the current period.
  final bool used;

  /// When the credit was last marked as used.
  final DateTime? usedAt;

  /// Human-readable amount string, e.g. "$200.00" or "200.00 EUR".
  String? get amountLabel {
    if (amount == null) return null;
    final value = amount! / 100;
    final currencySymbol = switch (currency) {
      'USD' => '\$',
      'EUR' => '€',
      'GBP' => '£',
      _ => '',
    };
    return '$currencySymbol${value.toStringAsFixed(2)}';
  }

  /// Whether this benefit has expired (past its expiry date).
  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  /// Short label for the reset frequency, e.g. "Resets semi-annually".
  String? get periodLabel {
    if (periodLength == null) return null;
    return 'Resets $periodLength';
  }
}

/// One catalog welcome bonus with locally-tracked spend progress.
///
/// Amounts are stored in the catalog's native units (cents for cash bonuses,
/// points for point bonuses); spend progress compares like-for-like units.
class WalletBonus {
  const WalletBonus({
    required this.amountUnits,
    this.currency,
    required this.spendRequiredUnits,
    this.spendCurrency,
    this.months,
    this.description,
    this.spentUnits = 0,
  });

  final int amountUnits;
  final String? currency;
  final int spendRequiredUnits;
  final String? spendCurrency;
  final int? months;
  final String? description;

  /// Spend already counted toward the bonus, in native units.
  final int spentUnits;

  /// Progress fraction from 0 to 1.
  double get progress {
    if (spendRequiredUnits <= 0) return 0.0;
    return (spentUnits / spendRequiredUnits).clamp(0.0, 1.0);
  }

  bool get isComplete => progress >= 1.0;

  int get remainingUnits => (spendRequiredUnits - spentUnits).clamp(0, spendRequiredUnits);
}
