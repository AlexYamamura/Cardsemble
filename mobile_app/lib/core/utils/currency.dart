String formatCurrency(double amount, String currency) {
  final symbol = currencySymbol(currency);
  final formatted = amount.toStringAsFixed(2);
  return '$symbol $formatted';
}

String formatCurrencyString(String amount, String currency) {
  final parsed = double.tryParse(amount);
  if (parsed == null) return '${currencySymbol(currency)} $amount';
  return formatCurrency(parsed, currency);
}

String currencySymbol(String currency) {
  switch (currency.toUpperCase()) {
    case 'USD':
      return r'$';
    case 'EUR':
      return '€';
    case 'GBP':
      return '£';
    case 'CAD':
      return 'CA\$';
    case 'AUD':
      return 'A\$';
    case 'JPY':
      return '¥';
    case 'CNY':
      return '¥';
    default:
      return currency;
  }
}

double parseAmount(String amount) {
  return double.tryParse(amount) ?? 0.0;
}

bool isPositiveAmount(String amount) {
  final parsed = double.tryParse(amount);
  return parsed != null && parsed > 0;
}