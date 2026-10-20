/// Reference data for one credit card in the catalog.
///
/// This model mirrors the catalog entry shape supplied for the future card
/// research/setup builder. Only reference data lives here; account-specific
/// benefit enrollment, usage, and redemption records belong to separate
/// account-scoped tables once those exist.
class CardCatalogCard {
  const CardCatalogCard({
    required this.id,
    this.schemaVersion,
    required this.name,
    this.localizedNames = const {},
    this.country,
    this.issuer,
    this.issuerId,
    this.network,
    this.networkTier,
    this.type,
    this.status,
    this.annualFee,
    this.apr,
    this.fxFee,
    this.creditRequired,
    this.rewards,
    this.signupBonus,
    this.benefits = const [],
    this.travelPerks,
    this.officialUrl,
    this.image,
    this.binHints = const [],
    this.lastVerified,
    this.sources = const [],
    this.notes,
    this.segment,
    this.extra = const {},
  });

  /// Stable catalog identifier, for example `us-chase-sapphire-preferred`.
  final String id;
  final String? schemaVersion;
  final String name;
  final Map<String, String> localizedNames;
  final String? country;
  final String? issuer;
  final String? issuerId;
  final String? network;
  final String? networkTier;
  final String? type;
  final String? status;
  final CardAnnualFee? annualFee;
  final CardApr? apr;
  final CardFxFee? fxFee;
  final CardCreditRequired? creditRequired;
  final CardRewards? rewards;
  final CardSignupBonus? signupBonus;
  final List<CardBenefit> benefits;
  final CardTravelPerks? travelPerks;
  final String? officialUrl;
  final CardImage? image;
  final List<String> binHints;
  final String? lastVerified;
  final List<String> sources;
  final String? notes;
  final String? segment;

  /// Unknown keys are preserved so a catalog schema addition does not get
  /// silently dropped when a card is cached and read back.
  final Map<String, dynamic> extra;

  /// Search text used by the setup builder. Kept local to the model so UI code
  /// does not have to know which catalog fields exist.
  String get searchText {
    return <String>[
      name,
      issuer ?? '',
      network ?? '',
      ...localizedNames.values,
    ].join(' ').toLowerCase();
  }

  factory CardCatalogCard.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    if (rawId is! String || rawId.isEmpty) {
      throw const FormatException('Card catalog entry is missing id.');
    }

    return CardCatalogCard(
      id: rawId,
      schemaVersion: _asString(json['schema_version']),
      name: _asString(json['name']) ?? rawId,
      localizedNames: _asStringMap(json['localized_names']),
      country: _asString(json['country']),
      issuer: _asString(json['issuer']),
      issuerId: _asString(json['issuer_id']),
      network: _asString(json['network']),
      networkTier: _asString(json['network_tier']),
      type: _asString(json['type']),
      status: _asString(json['status']),
      annualFee: json['annual_fee'] == null
          ? null
          : CardAnnualFee.fromJson(json['annual_fee']),
      apr: json['apr'] == null ? null : CardApr.fromJson(json['apr']),
      fxFee: json['fx_fee'] == null ? null : CardFxFee.fromJson(json['fx_fee']),
      creditRequired: json['credit_required'] == null
          ? null
          : CardCreditRequired.fromJson(json['credit_required']),
      rewards: json['rewards'] == null
          ? null
          : CardRewards.fromJson(json['rewards']),
      signupBonus: json['signup_bonus'] == null
          ? null
          : CardSignupBonus.fromJson(json['signup_bonus']),
      benefits: _asMapList(json['benefits'])
          .map(CardBenefit.fromJson)
          .toList(growable: false),
      travelPerks: json['travel_perks'] == null
          ? null
          : CardTravelPerks.fromJson(json['travel_perks']),
      officialUrl: _asString(json['official_url']),
      image: json['image'] == null ? null : CardImage.fromJson(json['image']),
      binHints: _asStringList(json['bin_hints']),
      lastVerified: _asString(json['last_verified']),
      sources: _asStringList(json['sources']),
      notes: _asString(json['notes']),
      segment: _asString(json['segment']),
      extra: _extraKeys(json, _knownKeys),
    );
  }

  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{
      'id': id,
      if (schemaVersion != null) 'schema_version': schemaVersion,
      'name': name,
      if (localizedNames.isNotEmpty) 'localized_names': localizedNames,
      if (country != null) 'country': country,
      if (issuer != null) 'issuer': issuer,
      if (issuerId != null) 'issuer_id': issuerId,
      if (network != null) 'network': network,
      if (networkTier != null) 'network_tier': networkTier,
      if (type != null) 'type': type,
      if (status != null) 'status': status,
      if (annualFee != null) 'annual_fee': annualFee!.toJson(),
      if (apr != null) 'apr': apr!.toJson(),
      if (fxFee != null) 'fx_fee': fxFee!.toJson(),
      if (creditRequired != null)
        'credit_required': creditRequired!.toJson(),
      if (rewards != null) 'rewards': rewards!.toJson(),
      if (signupBonus != null) 'signup_bonus': signupBonus!.toJson(),
      if (benefits.isNotEmpty)
        'benefits': benefits.map((e) => e.toJson()).toList(growable: false),
      if (travelPerks != null) 'travel_perks': travelPerks!.toJson(),
      if (officialUrl != null) 'official_url': officialUrl,
      if (image != null) 'image': image!.toJson(),
      if (binHints.isNotEmpty) 'bin_hints': binHints,
      if (lastVerified != null) 'last_verified': lastVerified,
      if (sources.isNotEmpty) 'sources': sources,
      if (notes != null) 'notes': notes,
      if (segment != null) 'segment': segment,
    };
    for (final entry in extra.entries) {
      result.putIfAbsent(entry.key, () => entry.value);
    }
    return result;
  }

  static const Set<String> _knownKeys = {
    'id',
    'schema_version',
    'name',
    'localized_names',
    'country',
    'issuer',
    'issuer_id',
    'network',
    'network_tier',
    'type',
    'status',
    'annual_fee',
    'apr',
    'fx_fee',
    'credit_required',
    'rewards',
    'signup_bonus',
    'benefits',
    'travel_perks',
    'official_url',
    'image',
    'bin_hints',
    'last_verified',
    'sources',
    'notes',
    'segment',
  };
}

class CardAnnualFee {
  const CardAnnualFee({
    this.amount,
    this.currency,
    this.firstYear,
    this.waiverConditions,
  });

  final num? amount;
  final String? currency;
  final num? firstYear;
  final String? waiverConditions;

  factory CardAnnualFee.fromJson(Object? json) {
    if (json is num) return CardAnnualFee(amount: json);
    final map = _asMap(json);
    if (map == null) return const CardAnnualFee();
    return CardAnnualFee(
      amount: _asNum(map['amount']),
      currency: _asString(map['currency']),
      firstYear: _asNum(map['first_year']),
      waiverConditions: _asString(map['waiver_conditions']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (amount != null) 'amount': amount,
      if (currency != null) 'currency': currency,
      if (firstYear != null) 'first_year': firstYear,
      if (waiverConditions != null) 'waiver_conditions': waiverConditions,
    };
  }
}

class CardAprRange {
  const CardAprRange({this.min, this.max, this.type});

  final num? min;
  final num? max;
  final String? type;

  factory CardAprRange.fromJson(Object? json) {
    if (json is num) return CardAprRange(min: json, max: json);
    final map = _asMap(json);
    if (map == null) return const CardAprRange();
    return CardAprRange(
      min: _asNum(map['min']),
      max: _asNum(map['max']),
      type: _asString(map['type']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (min != null) 'min': min,
      if (max != null) 'max': max,
      if (type != null) 'type': type,
    };
  }
}

class CardApr {
  const CardApr({
    this.purchase,
    this.balanceTransfer,
    this.cashAdvance,
    this.notes,
  });

  final CardAprRange? purchase;
  final CardAprRange? balanceTransfer;
  final CardAprRange? cashAdvance;
  final String? notes;

  factory CardApr.fromJson(Object? json) {
    if (json is num) return CardApr(purchase: CardAprRange.fromJson(json));
    final map = _asMap(json);
    if (map == null) return const CardApr();
    return CardApr(
      purchase: map['purchase'] == null
          ? null
          : CardAprRange.fromJson(map['purchase']),
      balanceTransfer: map['balance_transfer'] == null
          ? null
          : CardAprRange.fromJson(map['balance_transfer']),
      cashAdvance: map['cash_advance'] == null
          ? null
          : CardAprRange.fromJson(map['cash_advance']),
      notes: _asString(map['notes']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (purchase != null) 'purchase': purchase!.toJson(),
      if (balanceTransfer != null) 'balance_transfer': balanceTransfer!.toJson(),
      if (cashAdvance != null) 'cash_advance': cashAdvance!.toJson(),
      if (notes != null) 'notes': notes,
    };
  }
}

class CardFxFee {
  const CardFxFee({this.percent, this.notes});

  final num? percent;
  final String? notes;

  factory CardFxFee.fromJson(Object? json) {
    if (json is num) return CardFxFee(percent: json);
    final map = _asMap(json);
    if (map == null) return const CardFxFee();
    return CardFxFee(
      percent: _asNum(map['percent']),
      notes: _asString(map['notes']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (percent != null) 'percent': percent,
      if (notes != null) 'notes': notes,
    };
  }
}

class CardCreditRequired {
  const CardCreditRequired({this.scoreBand, this.notes});

  final String? scoreBand;
  final String? notes;

  factory CardCreditRequired.fromJson(Object? json) {
    final map = _asMap(json);
    if (map == null) return const CardCreditRequired();
    return CardCreditRequired(
      scoreBand: _asString(map['score_band']),
      notes: _asString(map['notes']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (scoreBand != null) 'score_band': scoreBand,
      if (notes != null) 'notes': notes,
    };
  }
}

class CardRewardRate {
  const CardRewardRate({this.pointsPerDollar, this.description});

  final num? pointsPerDollar;
  final String? description;

  factory CardRewardRate.fromJson(Object? json) {
    if (json is num) return CardRewardRate(pointsPerDollar: json);
    final map = _asMap(json);
    if (map == null) return const CardRewardRate();
    return CardRewardRate(
      pointsPerDollar: _asNum(map['points_per_dollar']),
      description: _asString(map['description']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (pointsPerDollar != null) 'points_per_dollar': pointsPerDollar,
      if (description != null) 'description': description,
    };
  }
}

class CardRewardCategory {
  const CardRewardCategory({
    this.label,
    this.pointsPerDollar,
    this.cap,
  });

  final String? label;
  final num? pointsPerDollar;
  final Object? cap;

  factory CardRewardCategory.fromJson(Map<String, dynamic> json) {
    return CardRewardCategory(
      label: _asString(json['label']),
      pointsPerDollar: _asNum(json['points_per_dollar']),
      cap: json['cap'],
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (label != null) 'label': label,
      if (pointsPerDollar != null) 'points_per_dollar': pointsPerDollar,
      if (cap != null) 'cap': cap,
    };
  }
}

class CardRewards {
  const CardRewards({
    this.currency,
    this.currencyLabel,
    this.structure,
    this.baseRate,
    this.categories = const [],
    this.redemptionNotes,
    this.rateType,
  });

  final String? currency;
  final String? currencyLabel;
  final String? structure;
  final CardRewardRate? baseRate;
  final List<CardRewardCategory> categories;
  final String? redemptionNotes;
  final String? rateType;

  factory CardRewards.fromJson(Object? json) {
    final map = _asMap(json);
    if (map == null) return const CardRewards();
    return CardRewards(
      currency: _asString(map['currency']),
      currencyLabel: _asString(map['currency_label']),
      structure: _asString(map['structure']),
      baseRate: map['base_rate'] == null
          ? null
          : CardRewardRate.fromJson(map['base_rate']),
      categories: _asMapList(map['categories'])
          .map(CardRewardCategory.fromJson)
          .toList(growable: false),
      redemptionNotes: _asString(map['redemption_notes']),
      rateType: _asString(map['rate_type']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (currency != null) 'currency': currency,
      if (currencyLabel != null) 'currency_label': currencyLabel,
      if (structure != null) 'structure': structure,
      if (baseRate != null) 'base_rate': baseRate!.toJson(),
      if (categories.isNotEmpty)
        'categories': categories.map((e) => e.toJson()).toList(growable: false),
      if (redemptionNotes != null) 'redemption_notes': redemptionNotes,
      if (rateType != null) 'rate_type': rateType,
    };
  }
}

class CardSignupBonus {
  const CardSignupBonus({
    this.amount,
    this.unit,
    this.spendRequired,
    this.spendCurrency,
    this.months,
    this.description,
    this.asOf,
  });

  final num? amount;
  final String? unit;
  final num? spendRequired;
  final String? spendCurrency;
  final int? months;
  final String? description;
  final String? asOf;

  factory CardSignupBonus.fromJson(Object? json) {
    final map = _asMap(json);
    if (map == null) return const CardSignupBonus();
    return CardSignupBonus(
      amount: _asNum(map['amount']),
      unit: _asString(map['unit']),
      spendRequired: _asNum(map['spend_required']),
      spendCurrency: _asString(map['spend_currency']),
      months: _asInt(map['months']),
      description: _asString(map['description']),
      asOf: _asString(map['as_of']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (amount != null) 'amount': amount,
      if (unit != null) 'unit': unit,
      if (spendRequired != null) 'spend_required': spendRequired,
      if (spendCurrency != null) 'spend_currency': spendCurrency,
      if (months != null) 'months': months,
      if (description != null) 'description': description,
      if (asOf != null) 'as_of': asOf,
    };
  }
}

class CardBenefit {
  const CardBenefit({
    this.id,
    this.title,
    this.category,
    this.source,
    this.description,
    this.details,
  });

  final String? id;
  final String? title;
  final String? category;
  final String? source;
  final String? description;
  final Map<String, dynamic>? details;

  factory CardBenefit.fromJson(Map<String, dynamic> json) {
    return CardBenefit(
      id: _asString(json['id']),
      title: _asString(json['title']),
      category: _asString(json['category']),
      source: _asString(json['source']),
      description: _asString(json['description']),
      details: _asMap(json['details']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (category != null) 'category': category,
      if (source != null) 'source': source,
      if (description != null) 'description': description,
      if (details != null) 'details': details,
    };
  }
}

class CardTravelPerks {
  const CardTravelPerks({
    this.loungeAccess,
    this.tsaPrecheckCredit,
    this.globalEntryCredit,
    this.freeCheckedBags,
    this.hotelStatus,
    this.other = const [],
  });

  final Object? loungeAccess;
  final Object? tsaPrecheckCredit;
  final Object? globalEntryCredit;
  final Object? freeCheckedBags;
  final Object? hotelStatus;
  final List<String> other;

  factory CardTravelPerks.fromJson(Object? json) {
    final map = _asMap(json);
    if (map == null) return const CardTravelPerks();
    return CardTravelPerks(
      loungeAccess: map['lounge_access'],
      tsaPrecheckCredit: map['tsa_precheck_credit'],
      globalEntryCredit: map['global_entry_credit'],
      freeCheckedBags: map['free_checked_bags'],
      hotelStatus: map['hotel_status'],
      other: _asStringList(map['other']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (loungeAccess != null) 'lounge_access': loungeAccess,
      if (tsaPrecheckCredit != null)
        'tsa_precheck_credit': tsaPrecheckCredit,
      if (globalEntryCredit != null)
        'global_entry_credit': globalEntryCredit,
      if (freeCheckedBags != null) 'free_checked_bags': freeCheckedBags,
      if (hotelStatus != null) 'hotel_status': hotelStatus,
      if (other.isNotEmpty) 'other': other,
    };
  }
}

class CardImage {
  const CardImage({this.url, this.attribution, this.localPath});

  final String? url;
  final String? attribution;
  final String? localPath;

  factory CardImage.fromJson(Object? json) {
    final map = _asMap(json);
    if (map == null) return const CardImage();
    return CardImage(
      url: _asString(map['url']),
      attribution: _asString(map['attribution']),
      localPath: _asString(map['local_path']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (url != null) 'url': url,
      if (attribution != null) 'attribution': attribution,
      if (localPath != null) 'local_path': localPath,
    };
  }
}

Map<String, dynamic>? _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    try {
      return Map<String, dynamic>.from(value);
    } catch (_) {
      return null;
    }
  }
  return null;
}

List<Map<String, dynamic>> _asMapList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((entry) {
        try {
          return Map<String, dynamic>.from(entry);
        } catch (_) {
          return <String, dynamic>{};
        }
      })
      .where((entry) => entry.isNotEmpty)
      .toList(growable: false);
}

Map<String, String> _asStringMap(Object? value) {
  final map = _asMap(value);
  if (map == null) return const {};
  return <String, String>{
    for (final entry in map.entries)
      if (entry.value is String) entry.key: entry.value as String,
  };
}

List<String> _asStringList(Object? value) {
  if (value is! List) return const [];
  return value.whereType<String>().toList(growable: false);
}

num? _asNum(Object? value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value);
  return null;
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

String? _asString(Object? value) => value is String ? value : null;

Map<String, dynamic> _extraKeys(
  Map<String, dynamic> json,
  Set<String> knownKeys,
) {
  return <String, dynamic>{
    for (final entry in json.entries)
      if (!knownKeys.contains(entry.key)) entry.key: entry.value,
  };
}
