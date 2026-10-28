/// Shared category-label normalization utilities.
///
/// Maps free-text category labels (from the card catalog benefits and from Plaid
/// personal finance categories) into canonical grouping keys so the wallet's
/// "spending toward benefits" metric and the card optimizer's rewards ranking
/// agree on what belongs together.
library;

/// Canonical category keys used across the wallet and card optimizer features.
///
/// The keys mirror the buckets the card catalog groups benefits under when a
/// `category` is present. New buckets can be added here as catalog data evolves.
const Set<String> kCanonicalCategoryKeys = {
  'dining',
  'groceries',
  'gas',
  'travel',
  'transit',
  'online_retail',
  'drugstores',
  'streaming',
  'entertainment',
  'other',
};

/// Synonyms that map to each canonical key. Matching is case-insensitive
/// substring (a label containing any synonym maps to that key).
const Map<String, List<String>> kCategoryAliases = {
  'dining': [
    'dining',
    'restaurants',
    'food',
    'eating',
    'bars',
    'nightlife',
  ],
  'groceries': ['groceries', 'grocery stores', 'supermarkets', 'grocery'],
  'gas': ['gas', 'gas stations', 'fuel', 'petrol', 'ev charging', 'ev charging stations'],
  'travel': [
    'travel',
    'hotels',
    'airlines',
    'airfare',
    'flights',
    'transportation',
    'rideshare',
  ],
  'transit': ['transit', 'commuter', 'toll', 'parking', 'public transport'],
  'online_retail': ['online', 'retail', 'shopping', 'amazon', 'ebay', 'internet'],
  'drugstores': ['drugstores', 'pharmacy', 'pharmacies', 'drugstore'],
  'streaming': ['streaming', 'netflix', 'spotify', 'subscription'],
  'entertainment': ['entertainment', 'movies', 'concerts', 'theater'],
};

/// Maps a Plaid `personal_finance_category_detailed` value to a canonical key.
///
/// Plaid PFC detailed values are uppercase with underscores (e.g.
/// `FOOD_AND_DRINK_RESTAURANTS`, `TRAVEL_AIR_AND_NTIRELINE`). We strip the shared
/// primary prefix and normalize. Falls back to deriving from the primary.
const Map<String, String> kPlaidDetailedCategoryMap = {
  // Food and drink
  'FOOD_AND_DRINK_RESTAURANTS': 'dining',
  'FOOD_AND_DRINK_COFFEE_SHOPS': 'dining',
  'FOOD_AND_DRINK_BARS': 'dining',
  'FOOD_AND_DRINK_OTHER': 'dining',
  'FOOD_AND_DRINK_GROCERIES': 'groceries',
  'FOOD_AND_DRINK_NON_GROCERY_STORES': 'online_retail',
  // Travel
  'TRAVEL_AIR_AND_NTIRELINE': 'travel',
  'TRAVEL_CAR_RENTAL': 'travel',
  'TRAVEL_OTHER_TRAVEL': 'travel',
  'TRAVEL_FERRIES': 'travel',
  'TRAVEL_RAIL': 'travel',
  // Transportation
  'TRANSPORTATION_FUEL': 'gas',
  'TRANSPORTATION_PUBLIC': 'transit',
  'TRANSPORTATION_TAXIS': 'transit',
  'TRANSPORTATION_RIDESHARE': 'transit',
  'TRANSPORTATION_PARKING': 'transit',
  'TRANSPORTATION_TOLLS': 'transit',
  'TRANSPORTATION_OTHER': 'transit',
  // General merchandise
  'GENERAL_MERCHANDISE_TELECOM': 'online_retail',
  'GENERAL_MERCHANDISE_ONLINE_RETRAIL': 'online_retail',
  'GENERAL_MERCHANDISE_APPAREL': 'online_retail',
  'GENERAL_MERCHANDISE_ENTERTAINMENT': 'entertainment',
  'GENERAL_MERCHANDISE_PHARMACIES': 'drugstores',
  // Other
  'OTHER_MERCHANDISE_STORES': 'online_retail',
  'OTHER_GENERAL_SERVICES': 'other',
  'OTHER_PERSONAL_SERVICES': 'other',
  'OTHER_GOVERNMENT': 'other',
  'OTHER_INVOICE_AND_DEBTS': 'other',
  'OTHER_DONATIONS': 'other',
  'OTHER_CHILD_SUPPORT': 'other',
  'OTHER_RETIREMENT': 'other',
  'UNCATEGORIZED': 'other',
};

/// Maps a Plaid `personal_finance_category_primary` value to a canonical key.
const Map<String, String> kPlaidPrimaryCategoryMap = {
  'FOOD_AND_DRINK': 'dining',
  'FOOD_AND_DRINK_GROCERIES': 'groceries',
  'TRAVEL': 'travel',
  'TRANSPORTATION': 'transit',
  'GENERAL_MERCHANDISE': 'online_retail',
  'GENERAL_MERCHANDISE_PHARMACIES': 'drugstores',
  'ENTERTAINMENT': 'entertainment',
  'OTHER': 'other',
  'UNCATEGORIZED': 'other',
  'INCOME': 'other',
  'TRANSFER': 'other',
  'LOAN': 'other',
  'BANK_FEES': 'other',
};

/// Normalizes a free-text category label (from the card catalog) into a
/// canonical grouping key.
///
/// Uses substring matching against the alias tables so that "Restaurants" maps
/// to `dining`, "Gas Stations" maps to `gas`, etc. Unrecognized labels return
/// their own lowercased form.
String normalizeCategoryKey(String label) {
  final key = label.trim().toLowerCase();
  if (key.isEmpty) return 'other';
  for (final entry in kCategoryAliases.entries) {
    if (entry.value.any((alias) => key.contains(alias))) {
      return entry.key;
    }
  }
  return key;
}

/// Derives a canonical category key from a Plaid personal finance category.
///
/// Prefers the detailed category (more specific), then the primary, then
/// returns `'other'`. Returns `null` if neither PFC value is present.
String? categoryKeyFromPlaid({
  String? primary,
  String? detailed,
}) {
  if (detailed != null && detailed.isNotEmpty) {
    final mapped = kPlaidDetailedCategoryMap[detailed.toUpperCase()];
    if (mapped != null) return mapped;
    return _mapPlaidPrefix(detailed);
  }
  if (primary != null && primary.isNotEmpty) {
    final mapped = kPlaidPrimaryCategoryMap[primary.toUpperCase()];
    if (mapped != null) return mapped;
    return _mapPlaidPrefix(primary);
  }
  return null;
}

/// Fallback for any Plaid PFC value not in the explicit maps: strip the shared
/// prefix (everything before the last segment) and lower-case it, so
/// `TRAVEL_AIR_AND_NTIRELINE` → `travel` and `FOOD_AND_DRINK_RESTAURANTS` →
/// `food_and_drink_restaurants` (which the alias matcher will still catch).
String _mapPlaidPrefix(String pfc) {
  final upper = pfc.toUpperCase();
  final mapped = kPlaidDetailedCategoryMap[upper];
  if (mapped != null) return mapped;

  // Split on underscores and try combining prefixes against the alias table.
  final parts = upper.split('_');
  if (parts.length < 2) return upper.toLowerCase();

  // Try the full string against known aliases first.
  final fullLower = upper.toLowerCase();
  for (final entry in kCategoryAliases.entries) {
    if (entry.value.any((a) => fullLower.contains(a))) return entry.key;
  }

  // Try progressively shorter prefixes: TRAVEL_AIR_AND_NTIRELINE ->
  // "TRAVEL" then match aliases.
  for (var i = parts.length - 1; i >= 1; i--) {
    final prefix = parts.sublist(0, i).join('_').toLowerCase();
    final matched = normalizeCategoryKey(prefix);
    if (matched != prefix && matched != 'other') {
      return matched;
    }
  }

  // Try the last segment alone.
  return normalizeCategoryKey(parts.last.toLowerCase());
}
