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
    };
  }

  double get amountValue => double.tryParse(amount) ?? 0.0;
  bool get isPositive => amountValue > 0;
  bool get isPayment => transactionCode?.toLowerCase() == 'payment';
  DateTime? get parsedDate => date != null ? DateTime.tryParse(date!) : null;
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