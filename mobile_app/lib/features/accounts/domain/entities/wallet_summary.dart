// Aggregation data for the Wallet tab, computed server-side from synced Plaid
// account and transaction data.
//
// Amounts are integer minor currency units (cents). Monetary values are
// bucketed by currency; the first bucket (primaryCurrency) is the headline one.
//
// Credit limit and current balance are no longer included here: they were
// sourced from the deprecated /liabilities/get Plaid product. The wallet now
// surfaces only card count and the highest cost transaction (largest positive
// charge in the past 30 days, excluding pending and payment rows).
class WalletSummary {
  const WalletSummary({
    required this.cardCount,
    this.primaryCurrency,
    required this.currencies,
    this.highestCostTransaction,
  });

  /// Number of connected credit-card accounts (all currencies).
  final int cardCount;

  /// Headline currency code, or null when there are no connected accounts.
  final String? primaryCurrency;

  /// Per-currency totals, ordered with the primary bucket first.
  final List<WalletCurrencySummary> currencies;

  /// Highest cost transaction in the past 30 days (largest positive charge),
  /// or null when none is available.
  final WalletCostTransaction? highestCostTransaction;

  /// Number of currencies not represented in the headline bucket.
  int get otherCurrencyCount => currencies.length - (primaryCurrency == null ? 0 : 1);

  factory WalletSummary.fromJson(Map<String, dynamic> json) {
    final currenciesRaw = json['currencies'];
    final currencies = (currenciesRaw is List)
        ? currenciesRaw
            .whereType<Map<String, dynamic>>()
            .map(WalletCurrencySummary.fromJson)
            .toList(growable: false)
        : <WalletCurrencySummary>[];

    // Backward-compatible key parsing: prefer the new key, fall back to the
    // legacy `highest_payment` key from older deployed API versions.
    final highestRaw = json['highest_cost_transaction'] ?? json['highest_payment'];

    return WalletSummary(
      cardCount: _asInt(json['card_count']) ?? 0,
      primaryCurrency: json['primary_currency'] as String?,
      currencies: currencies,
      highestCostTransaction: highestRaw is Map<String, dynamic>
          ? WalletCostTransaction.fromJson(highestRaw)
          : null,
    );
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  WalletSummary copyWith({
    int? cardCount,
    String? primaryCurrency,
    List<WalletCurrencySummary>? currencies,
    WalletCostTransaction? highestCostTransaction,
  }) {
    return WalletSummary(
      cardCount: cardCount ?? this.cardCount,
      primaryCurrency: primaryCurrency ?? this.primaryCurrency,
      currencies: currencies ?? this.currencies,
      highestCostTransaction: highestCostTransaction ?? this.highestCostTransaction,
    );
  }

  @override
  String toString() =>
      'WalletSummary(cardCount: $cardCount, primaryCurrency: $primaryCurrency, '
      'currencies: ${currencies.length}, highestCostTransaction: $highestCostTransaction)';
}

/// One currency bucket of wallet aggregation data.
class WalletCurrencySummary {
  const WalletCurrencySummary({
    required this.currency,
    required this.cardCount,
  });

  final String currency;
  final int cardCount;

  factory WalletCurrencySummary.fromJson(Map<String, dynamic> json) {
    return WalletCurrencySummary(
      currency: (json['currency'] as String? ?? 'UNKNOWN'),
      cardCount: WalletSummary._asInt(json['card_count']) ?? 0,
    );
  }

  @override
  String toString() =>
      'WalletCurrencySummary(currency: $currency, cards: $cardCount)';
}

/// Highest cost transaction in the past 30 days: the largest positive charge
/// (expenditure). `amountCents` is stored as a positive value — charges are
/// positive in Plaid, so no absolute-value conversion is needed.
class WalletCostTransaction {
  const WalletCostTransaction({
    required this.transactionId,
    this.accountId,
    this.accountName,
    required this.amountCents,
    required this.currency,
    this.date,
    required this.name,
    this.merchantName,
  });

  final String transactionId;
  final String? accountId;
  final String? accountName;
  final int amountCents; // positive cost amount in minor currency units
  final String currency;
  final DateTime? date;
  final String name;
  final String? merchantName;

  factory WalletCostTransaction.fromJson(Map<String, dynamic> json) {
    return WalletCostTransaction(
      transactionId: json['transaction_id'] as String? ?? '',
      accountId: json['account_id'] as String?,
      accountName: json['account_name'] as String?,
      amountCents: WalletSummary._asInt(json['amount_cents']) ?? 0,
      currency: (json['currency'] as String? ?? 'UNKNOWN'),
      date: _parseDate(json['date']),
      name: json['name'] as String? ?? '',
      merchantName: json['merchant_name'] as String?,
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  @override
  String toString() =>
      'WalletCostTransaction(amountCents: $amountCents, currency: $currency, date: $date)';
}
