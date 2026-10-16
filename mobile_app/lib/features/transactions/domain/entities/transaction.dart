/// Sentinel used so [CardTransaction.copyWith] can distinguish "leave the
/// nullable field unchanged" from "explicitly set it to null".
const Object _unset = Object();

class CardTransaction {
  const CardTransaction({
    required this.id,
    this.accountId,
    this.accountName,
    this.displayName,
    this.plaidName,
    this.officialName,
    this.accountMask,
    required this.amount,
    required this.currency,
    this.date,
    required this.name,
    this.merchant,
    required this.pending,
    this.transactionCode,
    this.assignedPersonId,
    required this.assignmentSource,
    this.hasSplits = false,
    this.householdVisible = true,
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
  final bool hasSplits;
  final bool householdVisible;

  CardTransaction copyWith({
    String? accountId,
    String? accountName,
    String? displayName,
    String? plaidName,
    String? officialName,
    String? accountMask,
    String? amount,
    String? currency,
    String? date,
    String? name,
    String? merchant,
    bool? pending,
    String? transactionCode,
    Object? assignedPersonId = _unset,
    String? assignmentSource,
    bool? hasSplits,
    bool? householdVisible,
  }) {
    return CardTransaction(
      id: id,
      accountId: accountId ?? this.accountId,
      accountName: accountName ?? this.accountName,
      displayName: displayName ?? this.displayName,
      plaidName: plaidName ?? this.plaidName,
      officialName: officialName ?? this.officialName,
      accountMask: accountMask ?? this.accountMask,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      date: date ?? this.date,
      name: name ?? this.name,
      merchant: merchant ?? this.merchant,
      pending: pending ?? this.pending,
      transactionCode: transactionCode ?? this.transactionCode,
      assignedPersonId: identical(assignedPersonId, _unset)
          ? this.assignedPersonId
          : assignedPersonId as String?,
      assignmentSource: assignmentSource ?? this.assignmentSource,
      hasSplits: hasSplits ?? this.hasSplits,
      householdVisible: householdVisible ?? this.householdVisible,
    );
  }

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
      hasSplits: json['has_splits'] as bool? ?? false,
      householdVisible: json['household_visible'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'transaction_id': id,
      'account_id': accountId,
      'account_name': accountName,
      'display_name': displayName,
      'plaid_name': plaidName,
      'official_name': officialName,
      'account_mask': accountMask,
      'amount': amount,
      'iso_currency_code': currency,
      'date': date,
      'name': name,
      'merchant_name': merchant,
      'pending': pending,
      'transaction_code': transactionCode,
      'assigned_person_id': assignedPersonId,
      'assignment_source': assignmentSource,
      'has_splits': hasSplits,
      'household_visible': householdVisible,
    };
  }

  double get amountValue => double.tryParse(amount) ?? 0.0;
  bool get isPositive => amountValue > 0;
  bool get isPayment => transactionCode?.toLowerCase() == 'payment';
  DateTime? get parsedDate => date != null ? DateTime.tryParse(date!) : null;
}

/// Server-confirmed assignment for a transaction. The server resolves an
/// unassigned transaction back to the household default person, so the
/// effective [personId] is never the source of truth for "unassigned".
class TransactionAssignment {
  const TransactionAssignment({
    required this.personId,
    required this.assignmentSource,
  });

  final String? personId;
  final String assignmentSource;

  factory TransactionAssignment.fromJson(Map<String, dynamic> json) {
    return TransactionAssignment(
      personId: json['person_id'] as String?,
      assignmentSource: json['assignment_source'] as String? ?? 'default',
    );
  }
}

/// Query parameters for a transactions page. Date bounds are inclusive and sent
/// to the server so the client never has to download the whole ledger.
class TransactionQuery {
  const TransactionQuery({
    this.limit = 100,
    this.offset = 0,
    this.accountId,
    this.dateFrom,
    this.dateTo,
    this.householdVisible,
  });

  final int limit;
  final int offset;
  final String? accountId;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final bool? householdVisible;

  TransactionQuery copyWith({
    int? limit,
    int? offset,
    String? accountId,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool? householdVisible,
  }) {
    return TransactionQuery(
      limit: limit ?? this.limit,
      offset: offset ?? this.offset,
      accountId: accountId ?? this.accountId,
      dateFrom: dateFrom ?? this.dateFrom,
      dateTo: dateTo ?? this.dateTo,
      householdVisible: householdVisible ?? this.householdVisible,
    );
  }

  Map<String, String> toQueryParameters() {
    return {
      'limit': '$limit',
      'offset': '$offset',
      if (accountId != null) 'account_id': accountId!,
      if (dateFrom != null) 'date_from': _formatDate(dateFrom!),
      if (dateTo != null) 'date_to': _formatDate(dateTo!),
      if (householdVisible != null)
        'household_visible': householdVisible! ? 'true' : 'false',
    };
  }

  static String _formatDate(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}

class TransactionPage {
  const TransactionPage({
    required this.items,
    required this.hasMore,
  });

  final List<CardTransaction> items;
  final bool hasMore;
}

class TransactionSplit {
  const TransactionSplit({
    required this.personId,
    required this.amount,
  });

  final String personId;
  final double amount;

  Map<String, dynamic> toJson() {
    return {
      'person_id': personId,
      'amount': amount,
    };
  }

  factory TransactionSplit.fromJson(Map<String, dynamic> json) {
    return TransactionSplit(
      personId: json['person_id'] as String,
      amount: (json['amount'] as num).toDouble(),
    );
  }
}

class CsvImportRow {
  const CsvImportRow({
    required this.transactionDate,
    required this.postDate,
    required this.description,
    required this.category,
    required this.type,
    required this.amount,
    required this.memo,
    this.currency = 'USD',
  });

  final String transactionDate;
  final String postDate;
  final String description;
  final String category;
  final String type;
  final double amount;
  final String memo;
  final String currency;

  factory CsvImportRow.fromJson(Map<String, dynamic> json) {
    return CsvImportRow(
      transactionDate: json['transactionDate'] as String,
      postDate: json['postDate'] as String,
      description: json['description'] as String,
      category: json['category'] as String,
      type: json['type'] as String,
      amount: (json['amount'] as num).toDouble(),
      memo: json['memo'] as String,
      currency: json['currency'] as String? ?? 'USD',
    );
  }

  Map<String, dynamic> toJson() => {
        'transactionDate': transactionDate,
        'postDate': postDate,
        'description': description,
        'category': category,
        'type': type,
        'amount': amount,
        'memo': memo,
        'currency': currency,
      };
}

class CsvImportPreviewRow {
  const CsvImportPreviewRow({
    required this.row,
    required this.status,
    this.match,
    this.matchScore,
    this.error,
  });

  final CsvImportRow row;
  final String status; // 'new' | 'duplicate' | 'error'
  final Map<String, dynamic>? match;
  final double? matchScore;
  final String? error;

  factory CsvImportPreviewRow.fromJson(Map<String, dynamic> json) {
    return CsvImportPreviewRow(
      row: CsvImportRow.fromJson(json['row']),
      status: json['status'] as String,
      match: json['match'] as Map<String, dynamic>?,
      matchScore: (json['matchScore'] as num?)?.toDouble(),
      error: json['error'] as String?,
    );
  }
}

class CsvImportSummary {
  const CsvImportSummary({
    required this.newCount,
    required this.duplicateCount,
    required this.errorCount,
  });

  final int newCount;
  final int duplicateCount;
  final int errorCount;

  factory CsvImportSummary.fromJson(Map<String, dynamic> json) {
    return CsvImportSummary(
      newCount: json['new'] as int,
      duplicateCount: json['duplicate'] as int,
      errorCount: json['error'] as int,
    );
  }
}

class CsvAccountValidation {
  const CsvAccountValidation({
    required this.matched,
    this.warning,
  });

  final bool matched;
  final String? warning;

  factory CsvAccountValidation.fromJson(Map<String, dynamic> json) {
    return CsvAccountValidation(
      matched: json['matched'] as bool,
      warning: json['warning'] as String?,
    );
  }
}

class CsvImportPreview {
  const CsvImportPreview({
    required this.preview,
    required this.summary,
    this.accountValidation,
  });

  final List<CsvImportPreviewRow> preview;
  final CsvImportSummary summary;
  final CsvAccountValidation? accountValidation;

  factory CsvImportPreview.fromJson(Map<String, dynamic> json) {
    return CsvImportPreview(
      preview: (json['preview'] as List)
          .map((e) => CsvImportPreviewRow.fromJson(e))
          .toList(growable: false),
      summary: CsvImportSummary.fromJson(json['summary']),
      accountValidation: json['accountValidation'] != null
          ? CsvAccountValidation.fromJson(json['accountValidation'])
          : null,
    );
  }
}

class CsvImportResult {
  const CsvImportResult({
    required this.inserted,
    required this.errors,
  });

  final int inserted;
  final List<String> errors;

  factory CsvImportResult.fromJson(Map<String, dynamic> json) {
    return CsvImportResult(
      inserted: json['inserted'] as int,
      errors: (json['errors'] as List).map((e) => e.toString()).toList(growable: false),
    );
  }
}

class CsvImportHistory {
  const CsvImportHistory({
    required this.id,
    required this.accountId,
    required this.filename,
    required this.totalRows,
    required this.newCount,
    required this.duplicateCount,
    required this.errorCount,
    required this.createdAt,
  });

  final String id;
  final String accountId;
  final String filename;
  final int totalRows;
  final int newCount;
  final int duplicateCount;
  final int errorCount;
  final String createdAt;

  factory CsvImportHistory.fromJson(Map<String, dynamic> json) {
    return CsvImportHistory(
      id: json['id'] as String,
      accountId: json['account_id'] as String,
      filename: json['filename'] as String,
      totalRows: json['total_rows'] as int,
      newCount: json['new_count'] as int,
      duplicateCount: json['duplicate_count'] as int,
      errorCount: json['error_count'] as int,
      createdAt: json['created_at'] as String,
    );
  }
}