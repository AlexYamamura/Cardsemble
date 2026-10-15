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

  DateTime? get parsedOccurredAt => occurredAt.isNotEmpty ? DateTime.tryParse(occurredAt) : null;
  double get amountValue => double.tryParse(amount) ?? 0.0;
}