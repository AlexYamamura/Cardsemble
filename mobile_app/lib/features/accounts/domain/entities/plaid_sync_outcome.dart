/// A single Plaid item that could not be synced during a sync run.
class PlaidItemSyncError {
  const PlaidItemSyncError({
    required this.itemId,
    required this.message,
    this.institutionName,
    this.errorCode,
  });

  final String itemId;
  final String message;
  final String? institutionName;
  final String? errorCode;

  /// True when the connection is stale and the user has to sign in again.
  bool get needsReauthentication =>
      errorCode == 'ITEM_LOGIN_REQUIRED' ||
      errorCode == 'INVALID_ACCESS_TOKEN' ||
      errorCode == 'REAUTH_REQUIRED';

  factory PlaidItemSyncError.fromJson(Map<String, dynamic> json) {
    final itemId = json['item_id'];
    final institutionName = json['institution_name'];
    final errorCode = json['error_code'];
    final message = json['message'];
    return PlaidItemSyncError(
      itemId: itemId is String ? itemId : '',
      message: message is String ? message : '',
      institutionName: institutionName is String ? institutionName : null,
      errorCode: errorCode is String ? errorCode : null,
    );
  }
}

/// The result of a Plaid sync run, including per-item warnings.
class PlaidSyncOutcome {
  const PlaidSyncOutcome({this.itemErrors = const []});

  final List<PlaidItemSyncError> itemErrors;

  bool get hasWarnings => itemErrors.isNotEmpty;

  /// Tolerant of older deployments that do not return `item_errors` at all.
  factory PlaidSyncOutcome.fromJson(Map<String, dynamic> json) {
    final raw = json['item_errors'];
    final errors = <PlaidItemSyncError>[];
    if (raw is List) {
      for (final entry in raw) {
        if (entry is! Map) continue;
        final itemId = entry['item_id'];
        if (itemId is! String || itemId.isEmpty) continue;
        try {
          errors.add(
            PlaidItemSyncError.fromJson(Map<String, dynamic>.from(entry)),
          );
        } catch (_) {
          continue;
        }
      }
    }
    return PlaidSyncOutcome(itemErrors: List.unmodifiable(errors));
  }
}
