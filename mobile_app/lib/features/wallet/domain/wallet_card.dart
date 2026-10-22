// View models for the Wallet tab.
//
// The Wallet tab is the landing page: it shows the cards that are actually in
// the user's wallet (connected Plaid accounts) enriched with reference data
// from the card catalog (the same source used by the Research tab), plus
// household cards owned by other household members.
//
// Per-account balances, credit limits, benefit usage, and welcome-bonus spend
// are not yet exposed by the backend, so those fields are nullable and the UI
// renders a "—" placeholder until the data exists. Benefit usage and bonus
// spend are tracked locally so the landing page is functional today and can be
// migrated to backend tables later.
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
    this.balanceCents,
    this.currency,
    this.creditLimitCents,
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

  /// Current balance in minor currency units, null when unavailable.
  final int? balanceCents;
  final String? currency;

  /// Credit limit in minor currency units, null when unavailable.
  final int? creditLimitCents;

  /// Catalog benefits annotated with locally-tracked usage state.
  final List<WalletBenefit> benefits;

  /// Catalog welcome bonus annotated with locally-tracked spend.
  final WalletBonus? welcomeBonus;

  /// Whether this connected card matched a `card_catalog` row. When `unmatched`,
  /// benefits and welcome-bonus tracking are unavailable for this card.
  final CatalogMatchStatus catalogMatchStatus;

  /// Utilization ratio (balance / limit), or null when either is missing.
  double? get utilization {
    if (balanceCents == null || creditLimitCents == null || creditLimitCents == 0) {
      return null;
    }
    return (balanceCents! / creditLimitCents!).clamp(0.0, 1.0);
  }

  bool get hasBalance => balanceCents != null;
  bool get hasCreditLimit => creditLimitCents != null;

  bool get isCatalogMatched => catalogMatchStatus == CatalogMatchStatus.matched;

  /// Last four digits when a mask is available.
  String? get lastFour {
    final m = mask;
    if (m == null || m.length < 4) return null;
    return m.substring(m.length - 4);
  }
}

/// One catalog benefit with its locally-tracked usage state.
class WalletBenefit {
  const WalletBenefit({
    required this.id,
    required this.title,
    this.category,
    this.source,
    this.description,
    this.used = false,
  });

  final String id;
  final String title;
  final String? category;
  final String? source;
  final String? description;
  final bool used;
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
