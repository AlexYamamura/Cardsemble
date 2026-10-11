import 'dart:convert';

import 'package:http/http.dart' as http;

abstract interface class LedgerApi {
  String get apiBaseUrl;
  Future<List<HouseholdPerson>> loadPeople();
  Future<void> createPerson(String displayName);
  Future<DeviceCaptureCredentials> createGooglePayDeviceToken(String personId);
  Future<void> revokeDeviceToken(String deviceId);
  Future<List<CardTransaction>> loadTransactions();
  Future<List<CardEventRecord>> loadCardEvents();
  Future<StatementCycleSummary> loadStatementCycles();
  Future<List<PlaidConnection>> loadPlaidConnections();
  Future<String> createPlaidLinkToken(String platform);
  Future<void> syncPlaidConnections();
  Future<void> exchangePlaidPublicToken({
    required String publicToken,
    required String? institutionId,
    required String? institutionName,
    required String platform,
  });
  Future<void> updateCreditCardDisplayName(
    String accountId,
    String? displayName,
  );
  Future<void> assignTransaction(String transactionId, String? personId);
}

class DeviceCaptureCredentials {
  const DeviceCaptureCredentials({required this.id, required this.token});

  final String id;
  final String token;
}

class RestLedgerApi implements LedgerApi {
  RestLedgerApi({
    required String baseUrl,
    required this.accessToken,
    http.Client? client,
  }) : baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
       _client = client ?? http.Client();

  final String baseUrl;
  final String? Function() accessToken;
  final http.Client _client;

  @override
  String get apiBaseUrl => baseUrl;

  Future<Map<String, dynamic>> _get(String path) async {
    final response = await _client.get(
      Uri.parse('$baseUrl$path'),
      headers: _headers(),
    );
    return _decodeResponse(response);
  }

  Future<void> _delete(String path) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl$path'),
      headers: _headers(),
    );
    _decodeResponse(response);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await _client.post(
      Uri.parse('$baseUrl$path'),
      headers: _headers(),
      body: jsonEncode(body),
    );
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> _patch(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await _client.patch(
      Uri.parse('$baseUrl$path'),
      headers: _headers(),
      body: jsonEncode(body),
    );
    return _decodeResponse(response);
  }

  @override
  Future<List<PlaidConnection>> loadPlaidConnections() async {
    final payload = await _get('/api/plaid/items');
    return _records(
      payload,
      'items',
    ).map(PlaidConnection.fromJson).toList(growable: false);
  }

  @override
  Future<void> syncPlaidConnections() async {
    await _post('/api/plaid/items/sync', const {});
  }

  @override
  Future<String> createPlaidLinkToken(String platform) async {
    final payload = await _post(
      '/api/plaid/items/link-token?platform=${Uri.encodeQueryComponent(platform)}',
      const {},
    );
    final token = payload['link_token'];
    if (token is! String || token.isEmpty) {
      throw const LedgerApiException(
        'The card service did not return a Plaid Link token.',
      );
    }
    return token;
  }

  @override
  Future<void> exchangePlaidPublicToken({
    required String publicToken,
    required String? institutionId,
    required String? institutionName,
    required String platform,
  }) async {
    await _post('/api/plaid/items/exchange', {
      'public_token': publicToken,
      'institution_id': institutionId,
      'institution_name': institutionName,
      'platform': platform,
    });
  }

  Map<String, String> _headers() {
    final token = accessToken();
    if (token == null || token.isEmpty) {
      throw const LedgerApiException(
        'Your session has expired. Sign in again.',
      );
    }
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw LedgerApiException(
        'The card service returned an invalid response '
        '(HTTP ${response.statusCode}).',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map<String, dynamic>
          ? decoded['detail']?.toString()
          : null;
      throw LedgerApiException(
        detail ?? 'Request failed (HTTP ${response.statusCode}).',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const LedgerApiException(
        'The card service returned an unexpected response.',
      );
    }
    return decoded;
  }

  @override
  Future<List<HouseholdPerson>> loadPeople() async {
    final payload = await _get('/api/household/people');
    return _records(
      payload,
      'people',
    ).map(HouseholdPerson.fromJson).toList(growable: false);
  }

  @override
  Future<void> createPerson(String displayName) async {
    await _post('/api/household/people', {'display_name': displayName});
  }

  @override
  Future<DeviceCaptureCredentials> createGooglePayDeviceToken(
    String personId,
  ) async {
    final payload = await _post('/api/device-tokens', {
      'device_label': 'Android Google Pay',
      'person_id': personId,
      'platform': 'android_google_pay',
    });
    return DeviceCaptureCredentials(
      id: payload['id'] as String,
      token: payload['device_token'] as String,
    );
  }

  @override
  Future<void> revokeDeviceToken(String deviceId) async {
    await _delete('/api/device-tokens/${Uri.encodeComponent(deviceId)}');
  }

  @override
  Future<List<CardTransaction>> loadTransactions() async {
    const pageSize = 500;
    final transactions = <CardTransaction>[];
    var offset = 0;
    while (true) {
      final payload = await _get(
        '/api/plaid-transactions?limit=$pageSize&offset=$offset',
      );
      final page = _records(
        payload,
        'transactions',
      ).map(CardTransaction.fromJson).toList(growable: false);
      transactions.addAll(page);
      if (page.length < pageSize) {
        return transactions;
      }
      offset += page.length;
    }
  }

  @override
  Future<List<CardEventRecord>> loadCardEvents() async {
    final payload = await _get('/api/card-events?limit=200');
    return _records(
      payload,
      'events',
    ).map(CardEventRecord.fromJson).toList(growable: false);
  }

  @override
  Future<StatementCycleSummary> loadStatementCycles() async {
    return StatementCycleSummary.fromJson(
      await _get('/api/owed/statement-cycles'),
    );
  }

  @override
  Future<void> updateCreditCardDisplayName(
    String accountId,
    String? displayName,
  ) async {
    final encodedId = Uri.encodeComponent(accountId);
    await _patch('/api/plaid-credit-accounts/$encodedId/display-name', {
      'display_name': displayName,
    });
  }

  @override
  Future<void> assignTransaction(String transactionId, String? personId) async {
    final encodedId = Uri.encodeComponent(transactionId);
    await _post('/api/plaid-transactions/$encodedId/assignment', {
      'person_id': personId,
    });
  }
}

List<Map<String, dynamic>> _records(Map<String, dynamic> payload, String key) {
  final value = payload[key];
  if (value is! List) {
    throw LedgerApiException('The card service response is missing "$key".');
  }
  return value
      .map((record) {
        if (record is! Map<String, dynamic>) {
          throw LedgerApiException(
            'The card service returned an invalid "$key" row.',
          );
        }
        return record;
      })
      .toList(growable: false);
}

class LedgerApiException implements Exception {
  const LedgerApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class HouseholdPerson {
  const HouseholdPerson({
    required this.id,
    required this.displayName,
    required this.isDefault,
  });

  final String id;
  final String displayName;
  final bool isDefault;

  factory HouseholdPerson.fromJson(Map<String, dynamic> json) {
    return HouseholdPerson(
      id: json['person_id'] as String,
      displayName: json['display_name'] as String,
      isDefault: json['is_default'] as bool? ?? false,
    );
  }
}

class CardTransaction {
  const CardTransaction({
    required this.id,
    required this.accountId,
    this.accountName,
    this.displayName,
    this.plaidName,
    this.officialName,
    this.accountMask,
    required this.amount,
    required this.currency,
    required this.date,
    required this.name,
    required this.merchant,
    required this.pending,
    required this.transactionCode,
    required this.assignedPersonId,
    required this.assignmentSource,
  });

  final String id;
  final String? accountId;
  final String? accountName;
  final String? displayName;
  final String? plaidName;
  final String? officialName;
  final String? accountMask;
  final String amount;
  final String currency;
  final String? date;
  final String name;
  final String? merchant;
  final bool pending;
  final String? transactionCode;
  final String? assignedPersonId;
  final String assignmentSource;

  factory CardTransaction.fromJson(Map<String, dynamic> json) {
    return CardTransaction(
      id: json['transaction_id'] as String,
      accountId: json['account_id'] as String?,
      accountName: json['account_name'] as String?,
      displayName: json['display_name'] as String?,
      plaidName: json['plaid_name'] as String?,
      officialName: json['official_name'] as String?,
      accountMask: json['account_mask'] as String?,
      amount: json['amount']?.toString() ?? '0',
      currency: json['iso_currency_code'] as String? ?? 'USD',
      date: json['date'] as String?,
      name: json['name'] as String? ?? 'Card transaction',
      merchant: json['merchant_name'] as String?,
      pending: json['pending'] as bool? ?? false,
      transactionCode: json['transaction_code'] as String?,
      assignedPersonId: json['assigned_person_id'] as String?,
      assignmentSource: json['assignment_source'] as String? ?? 'default',
    );
  }
}

class CardEventRecord {
  const CardEventRecord({
    required this.id,
    required this.amount,
    required this.currency,
    required this.occurredAt,
    required this.merchant,
    required this.cardLabel,
    required this.paymentLabel,
    required this.source,
    required this.personId,
  });

  final String id;
  final String amount;
  final String currency;
  final String occurredAt;
  final String merchant;
  final String cardLabel;
  final String paymentLabel;
  final String source;
  final String? personId;

  factory CardEventRecord.fromJson(Map<String, dynamic> json) {
    return CardEventRecord(
      id: json['event_id'] as String,
      amount: json['amount']?.toString() ?? '0',
      currency: json['currency'] as String? ?? 'USD',
      occurredAt: json['occurred_at'] as String? ?? '',
      merchant: json['merchant'] as String? ?? 'Card event',
      cardLabel: json['card_label'] as String? ?? 'Card',
      paymentLabel: json['payment_label'] as String? ?? 'uncategorized',
      source: json['source'] as String? ?? 'unknown',
      personId: json['person_id'] as String?,
    );
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
      institutionName:
          json['institution_name'] as String? ?? 'Linked institution',
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
    );
  }
}
