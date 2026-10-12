import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class LedgerApi {
  String get apiBaseUrl;
  Future<List<HouseholdMember>> loadHouseholdMembers();
  Future<List<HouseholdPerson>> loadHouseholdPeople();
  Future<void> createHouseholdPerson(String displayName, {bool isDefault = false});
  Future<void> updateHouseholdPerson(String personId, String displayName, {bool? isDefault});
  Future<void> deleteHouseholdPerson(String personId);
  Future<void> addHouseholdMember(String userId);
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
  Future<void> setTransactionHouseholdVisible(String transactionId, bool visible);
  Future<void> setEventHouseholdVisible(String eventId, bool visible);
}

class DeviceCaptureCredentials {
  const DeviceCaptureCredentials({required this.id, required this.token});

  final String id;
  final String token;
}

class HybridLedgerApi implements LedgerApi {
  HybridLedgerApi({
    required String baseUrl,
    required this.supabase,
    required this.accessToken,
    http.Client? client,
  })  : _baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
        _client = client ?? http.Client();

  final String _baseUrl;
  final SupabaseClient supabase;
  final String? Function() accessToken;
  final http.Client _client;

  @override
  String get apiBaseUrl => _baseUrl;

  String? _getAccessToken() {
    final token = accessToken();
    if (token == null || token.isEmpty) {
      throw LedgerApiException('Your session has expired. Sign in again.');
    }
    return token;
  }

  Map<String, String> _headers() {
    final token = _getAccessToken();
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl$path'),
      headers: _headers(),
      body: jsonEncode(body),
    );
    _decodeResponse(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _patch(String path, Map<String, dynamic> body) async {
    final response = await _client.patch(
      Uri.parse('$_baseUrl$path'),
      headers: _headers(),
      body: jsonEncode(body),
    );
    _decodeResponse(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _delete(String path) async {
    final response = await _client.delete(
      Uri.parse('$_baseUrl$path'),
      headers: _headers(),
    );
    _decodeResponse(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _edgeGet(String path) async {
    final response = await _client.get(
      Uri.parse('$_baseUrl$path'),
      headers: _headers(),
    );
    _decodeResponse(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  void _decodeResponse(http.Response response) {
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw LedgerApiException(
        'The card service returned an invalid response (HTTP ${response.statusCode}).',
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
      throw LedgerApiException('The card service returned an unexpected response.');
    }
  }

  String _currentUserId() {
    final user = supabase.auth.currentSession?.user;
    if (user == null) {
      throw LedgerApiException('Your session has expired. Sign in again.');
    }
    return user.id;
  }

  @override
  Future<List<HouseholdMember>> loadHouseholdMembers() async {
    final payload = await _edgeGet('/api/household/members');
    final members = _records(payload, 'members');
    return members.map((m) => HouseholdMember.fromJson(m)).toList(growable: false);
  }

  @override
  Future<List<HouseholdPerson>> loadHouseholdPeople() async {
    final payload = await _edgeGet('/api/household/people');
    final people = _records(payload, 'people');
    return people.map((p) => HouseholdPerson.fromJson(p)).toList(growable: false);
  }

  @override
  Future<void> createHouseholdPerson(String displayName, {bool isDefault = false}) async {
    final payload = await _post(
      '/api/household/people',
      {'display_name': displayName.trim(), 'is_default': isDefault},
    );
    if (!payload['ok']) {
      throw LedgerApiException('Could not add household person.');
    }
  }

  @override
  Future<void> updateHouseholdPerson(String personId, String displayName, {bool? isDefault}) async {
    final payload = await _patch(
      '/api/household/people/$personId',
      {'display_name': displayName.trim(), if (isDefault != null) 'is_default': isDefault},
    );
    if (!payload['ok']) {
      throw LedgerApiException('Could not update household person.');
    }
  }

  @override
  Future<void> deleteHouseholdPerson(String personId) async {
    final payload = await _delete('/api/household/people/$personId');
    if (!payload['ok']) {
      throw LedgerApiException('Could not delete household person.');
    }
  }

  @override
  Future<void> addHouseholdMember(String userId) async {
    final payload = await _post(
      '/api/household/members',
      {'user_id': userId},
    );
    if (!payload['ok']) {
      throw LedgerApiException('Could not add household member.');
    }
  }

  @override
  Future<DeviceCaptureCredentials> createGooglePayDeviceToken(String personId) async {
    final session = supabase.auth.currentSession;
    if (session == null || session.accessToken.isEmpty) {
      throw LedgerApiException('Your session has expired. Sign in again.');
    }

    // Check if the JWT is expired and refresh if needed
    final expiresAt = session.expiresAt;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (expiresAt != null && expiresAt < now) {
      try {
        final refreshed = await supabase.auth.refreshSession();
        final refreshedSession = refreshed.session;
        if (refreshedSession == null || refreshedSession.accessToken.isEmpty) {
          throw LedgerApiException('Your session has expired. Sign in again.');
        }
      } catch (error) {
        throw LedgerApiException('Could not refresh session: $error');
      }
    }

    final userId = session.user.id;

    try {
      await supabase
          .from('household_members')
          .select('user_id')
          .eq('user_id', userId)
          .eq('user_id', personId)
          .limit(1);
    } catch (error) {
      throw LedgerApiException('Could not verify household member: $error');
    }

    final deviceToken = _generateSecureToken();
    final hash = crypto.sha256.convert(utf8.encode(deviceToken)).toString();

    try {
      final data = await supabase.from('device_tokens').insert({
        'user_id': userId,
        'person_id': personId,
        'device_label': 'Android Google Pay',
        'platform': 'android_google_pay',
        'token_hash': hash,
      }).select('id');
      final dataRow = (data as List);
      if (dataRow.isEmpty) {
        throw LedgerApiException('Could not create device key.');
      }
      return DeviceCaptureCredentials(
        id: dataRow[0]['id'] as String,
        token: deviceToken,
      );
    } catch (error) {
      throw LedgerApiException('Could not create device key: $error');
    }
  }

  static String _generateSecureToken() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-';
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < 43; i++) {
      buffer.write(chars[random.nextInt(chars.length)]);
    }
    return buffer.toString();
  }

  @override
  Future<void> revokeDeviceToken(String deviceId) async {
    final userId = _currentUserId();
    try {
      await supabase
          .from('device_tokens')
          .update({'revoked_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', deviceId)
          .eq('user_id', userId)
          .isFilter('revoked_at', null);
    } catch (error) {
      throw LedgerApiException('Could not revoke device key.');
    }
  }

  @override
  Future<List<CardTransaction>> loadTransactions() async {
    final payload = await _edgeGet('/api/plaid-transactions');
    final transactions = _records(payload, 'transactions');
    return transactions.map(CardTransaction.fromJson).toList(growable: false);
  }

  @override
  Future<List<CardEventRecord>> loadCardEvents() async {
    final userId = _currentUserId();
    try {
      final data = await supabase
          .from('card_events')
          .select(
              'event_id,user_id,person_id,occurred_at,amount,currency,merchant,card_label,payment_label,source,received_at')
          .eq('user_id', userId)
          .order('received_at', ascending: false)
          .order('event_id', ascending: true)
          .limit(200);
      final events = (data as List?)
          ?.map((row) => CardEventRecord.fromJson(row))
          .toList(growable: false) ??
          [];

      final reconData = await supabase
          .from('card_event_reconciliations')
          .select('event_id,status')
          .eq('user_id', userId);
      final reconByEvent = <String, String>{};
      // ignore: unnecessary_type_check
      if (reconData is List) {
        for (final row in reconData) {
          final eventId = row['event_id'] as String?;
          final status = row['status'] as String?;
          if (eventId != null && status != null) {
            reconByEvent[eventId] = status;
          }
        }
      }

      return [
        for (final event in events)
          event.copyWith(reconciliationStatus: reconByEvent[event.id]),
      ];
    } catch (error) {
      throw LedgerApiException('Could not load card events: $error');
    }
  }

  @override
  Future<StatementCycleSummary> loadStatementCycles() async {
    final payload = await _edgeGet('/api/owed/statement-cycles');
    return StatementCycleSummary.fromJson(payload);
  }

  @override
  Future<List<PlaidConnection>> loadPlaidConnections() async {
    final userId = _currentUserId();
    try {
      final data = await supabase
          .from('plaid_items')
          .select('item_id,institution_id,institution_name,status,created_at')
          .eq('user_id', userId)
          .neq('status', 'disconnected')
          .order('created_at', ascending: true)
          .order('item_id', ascending: true);
      return (data as List?)
          ?.map((row) => PlaidConnection.fromJson(row))
          .toList(growable: false) ??
          [];
    } catch (error) {
      throw LedgerApiException('Could not load bank connections: $error');
    }
  }

  @override
  Future<String> createPlaidLinkToken(String platform) async {
    final payload = await _post(
      '/api/plaid/items/link-token?platform=${Uri.encodeQueryComponent(platform)}',
      const {},
    );
    final token = payload['link_token'];
    if (token is! String || token.isEmpty) {
      throw LedgerApiException(
        'The card service did not return a Plaid Link token.',
      );
    }
    return token;
  }

  @override
  Future<void> syncPlaidConnections() async {
    await _post('/api/plaid/items/sync', const {});
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

  @override
  Future<void> updateCreditCardDisplayName(
    String accountId,
    String? displayName,
  ) async {
    final userId = _currentUserId();
    try {
      await supabase
          .from('plaid_credit_accounts')
          .update({'display_name': displayName})
          .eq('account_id', accountId)
          .eq('user_id', userId);
    } catch (error) {
      throw LedgerApiException('Could not save the credit card name.');
    }
  }

  @override
  Future<void> assignTransaction(String transactionId, String? personId) async {
    final payload = await _post(
      '/api/plaid-transactions/$transactionId/assignment',
      {'person_id': personId},
    );
    if (!payload['ok']) {
      throw LedgerApiException('Could not assign transaction.');
    }
  }

  @override
  Future<void> setTransactionHouseholdVisible(String transactionId, bool visible) async {
    final payload = await _patch(
      '/api/plaid-transactions/$transactionId/household-visible',
      {'household_visible': visible},
    );
    if (!payload['ok']) {
      throw LedgerApiException('Could not update transaction visibility.');
    }
  }

  @override
  Future<void> setEventHouseholdVisible(String eventId, bool visible) async {
    final payload = await _patch(
      '/api/card-events/$eventId/household-visible',
      {'household_visible': visible},
    );
    if (!payload['ok']) {
      throw LedgerApiException('Could not update event visibility.');
    }
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
      id: json['id'] as String? ?? json['person_id'] as String,
      displayName: json['display_name'] as String,
      isDefault: json['is_default'] as bool? ?? false,
    );
  }
}

class HouseholdMember {
  const HouseholdMember({
    required this.userId,
    required this.role,
    required this.joinedAt,
  });

  final String userId;
  final String role;
  final String joinedAt;

  factory HouseholdMember.fromJson(Map<String, dynamic> json) {
    return HouseholdMember(
      userId: json['user_id'] as String,
      role: json['role'] as String,
      joinedAt: json['joined_at'] as String,
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
    this.reconciliationStatus,
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
  final String? reconciliationStatus;

  CardEventRecord copyWith({String? reconciliationStatus}) {
    return CardEventRecord(
      id: id,
      amount: amount,
      currency: currency,
      occurredAt: occurredAt,
      merchant: merchant,
      cardLabel: cardLabel,
      paymentLabel: paymentLabel,
      source: source,
      personId: personId,
      reconciliationStatus: reconciliationStatus ?? this.reconciliationStatus,
    );
  }

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
