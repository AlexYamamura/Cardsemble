// Aggregation data for the Wallet tab, computed server-side from synced Plaid
// account and transaction data.
//
// Amounts are integer minor currency units (cents). Monetary values are
// bucketed by currency; the first bucket (primaryCurrency) is the headline one.
class WalletSummary {
  const WalletSummary({
    required this.cardCount,
    this.primaryCurrency,
    required this.currencies,
    this.highestPayment,
  });

  /// Number of connected credit-card accounts (all currencies).
  final int cardCount;

  /// Headline currency code, or null when there are no connected accounts.
  final String? primaryCurrency;

  /// Per-currency totals, ordered with the primary bucket first.
  final List<WalletCurrencySummary> currencies;

  /// Highest payment in the past 30 days, or null when none is available.
  final WalletPayment? highestPayment;

  /// The headline (primary) currency bucket, if any.
  WalletCurrencySummary? get primary =>
      currencies.isEmpty ? null : currencies.first;

  /// Whether every known card has both a credit limit and a balance synced.
  bool get isFullySynced =>
      currencies.isNotEmpty &&
      currencies.every((bucket) => bucket.isComplete);

  /// Number of currencies not represented in the headline bucket.
  int get otherCurrencyCount => currencies.length - (primary == null ? 0 : 1);

  factory WalletSummary.fromJson(Map<String, dynamic> json) {
    final currenciesRaw = json['currencies'];
    final currencies = (currenciesRaw is List)
        ? currenciesRaw
            .whereType<Map<String, dynamic>>()
            .map(WalletCurrencySummary.fromJson)
            .toList(growable: false)
        : <WalletCurrencySummary>[];

    return WalletSummary(
      cardCount: _asInt(json['card_count']) ?? 0,
      primaryCurrency: json['primary_currency'] as String?,
      currencies: currencies,
      highestPayment: json['highest_payment'] is Map<String, dynamic>
          ? WalletPayment.fromJson(json['highest_payment'] as Map<String, dynamic>)
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
    WalletPayment? highestPayment,
  }) {
    return WalletSummary(
      cardCount: cardCount ?? this.cardCount,
      primaryCurrency: primaryCurrency ?? this.primaryCurrency,
      currencies: currencies ?? this.currencies,
      highestPayment: highestPayment ?? this.highestPayment,
    );
  }

  @override
  String toString() =>
      'WalletSummary(cardCount: $cardCount, primaryCurrency: $primaryCurrency, '
      'currencies: ${currencies.length}, highestPayment: $highestPayment)';
}

/// One currency bucket of wallet aggregation data.
class WalletCurrencySummary {
  const WalletCurrencySummary({
    required this.currency,
    required this.creditLimitCents,
    required this.balanceCents,
    required this.cardCount,
    required this.accountsWithLimit,
    required this.accountsWithBalance,
  });

  final String currency;
  final int creditLimitCents;
  final int balanceCents;
  final int cardCount;
  final int accountsWithLimit;
  final int accountsWithBalance;

  /// Whether at least one card in this bucket has a synced credit limit.
  bool get hasLimitData => accountsWithLimit > 0;

  /// Whether every card in this bucket has both a limit and a balance.
  bool get isComplete =>
      accountsWithLimit == cardCount && accountsWithBalance == cardCount;

  /// Utilization ratio (balance / limit), or null when no positive limit exists.
  double? get utilization {
    if (creditLimitCents <= 0) return null;
    return (balanceCents / creditLimitCents).clamp(0.0, 1.0);
  }

  factory WalletCurrencySummary.fromJson(Map<String, dynamic> json) {
    return WalletCurrencySummary(
      currency: (json['currency'] as String? ?? 'UNKNOWN'),
      creditLimitCents: WalletSummary._asInt(json['credit_limit_cents']) ?? 0,
      balanceCents: WalletSummary._asInt(json['balance_cents']) ?? 0,
      cardCount: WalletSummary._asInt(json['card_count']) ?? 0,
      accountsWithLimit: WalletSummary._asInt(json['accounts_with_limit']) ?? 0,
      accountsWithBalance: WalletSummary._asInt(json['accounts_with_balance']) ?? 0,
    );
  }

  @override
  String toString() =>
      'WalletCurrencySummary(currency: $currency, limit: $creditLimitCents, '
      'balance: $balanceCents, cards: $cardCount)';
}

/// Highest payment in the past 30 days. amountCents is stored as a positive
/// value (payments are negative in Plaid).
class WalletPayment {
  const WalletPayment({
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
  final int amountCents; // positive magnitude of the payment
  final String currency;
  final DateTime? date;
  final String name;
  final String? merchantName;

  factory WalletPayment.fromJson(Map<String, dynamic> json) {
    return WalletPayment(
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
      'WalletPayment(amountCents: $amountCents, currency: $currency, date: $date)';
}
