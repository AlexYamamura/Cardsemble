class PlaidConnection {
  const PlaidConnection({
    required this.itemId,
    required this.institutionName,
    required this.status,
    this.institutionId,
  });

  final String itemId;
  final String institutionName;
  final String status;
  final String? institutionId;

  factory PlaidConnection.fromJson(Map<String, dynamic> json) {
    return PlaidConnection(
      itemId: json['item_id'] as String,
      institutionName: json['institution_name'] as String? ?? 'Linked institution',
      institutionId: json['institution_id'] as String?,
      status: json['status'] as String? ?? 'connected',
    );
  }
}

class StatementAccount {
  const StatementAccount({
    required this.accountId,
    required this.accountName,
    this.displayName,
    this.plaidName,
    this.officialName,
    this.mask,
    this.subtype,
    this.itemId,
    this.institutionName,
    this.creditLimitCents,
    this.currentBalanceCents,
    this.currency,
  });

  final String accountId;
  final String accountName;
  final String? displayName;
  final String? plaidName;
  final String? officialName;
  final String? mask;
  final String? subtype;
  final String? itemId;
  final String? institutionName;

  /// Credit limit in minor currency units, null when not yet synced from Plaid.
  final int? creditLimitCents;

  /// Current balance in minor currency units, null when not yet synced from Plaid.
  final int? currentBalanceCents;

  /// ISO currency code for the monetary fields above.
  final String? currency;

  static int? _centsFrom(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  factory StatementAccount.fromJson(Map<String, dynamic> json) {
    return StatementAccount(
      accountId: json['account_id'] as String,
      accountName: json['account_name'] as String? ?? 'Credit card',
      displayName: json['display_name'] as String?,
      plaidName: json['plaid_name'] as String? ?? json['name'] as String?,
      officialName: json['official_name'] as String?,
      mask: json['mask'] as String?,
      subtype: json['subtype'] as String?,
      itemId: json['item_id'] as String?,
      institutionName: json['institution_name'] as String?,
      creditLimitCents: _centsFrom(json['credit_limit']),
      currentBalanceCents: _centsFrom(json['current_balance']),
      currency: json['iso_currency_code'] as String? ?? json['currency'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'account_id': accountId,
      'account_name': accountName,
      'display_name': displayName,
      'plaid_name': plaidName,
      'official_name': officialName,
      'mask': mask,
      'subtype': subtype,
      'item_id': itemId,
      'institution_name': institutionName,
      'credit_limit': creditLimitCents == null ? null : creditLimitCents! / 100,
      'current_balance': currentBalanceCents == null ? null : currentBalanceCents! / 100,
      'iso_currency_code': currency,
    };
  }
}

class StatementCycleSummary {
  const StatementCycleSummary({
    required this.status,
    required this.total,
    required this.currency,
    required this.accountCount,
    required this.accounts,
  });

  final String status;
  final String? total;
  final String? currency;
  final int accountCount;
  final List<StatementAccount> accounts;

  factory StatementCycleSummary.fromJson(Map<String, dynamic> json) {
    final totals = json['totals_by_currency'];
    final currency = totals is Map && totals.length == 1
        ? totals.keys.first.toString()
        : null;
    final accounts = json['credit_accounts'] ?? json['accounts'];
    return StatementCycleSummary(
      status: json['total_status'] as String? ?? 'WAITING_FOR_STATEMENTS',
      total: json['current_total_owed']?.toString(),
      currency: currency,
      accountCount: accounts is List ? accounts.length : 0,
      accounts: accounts is List
          ? accounts
              .whereType<Map<String, dynamic>>()
              .map(StatementAccount.fromJson)
              .toList(growable: false)
          : const [],
    );
  }
}