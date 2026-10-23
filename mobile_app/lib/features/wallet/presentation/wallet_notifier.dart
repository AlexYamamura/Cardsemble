import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cardsemble/features/accounts/domain/accounts_domain.dart';
import 'package:cardsemble/features/accounts/presentation/accounts_notifier.dart';
import 'package:cardsemble/features/card_catalog/data/card_catalog_repository.dart';
import 'package:cardsemble/features/card_catalog/domain/entities/card_catalog_card.dart';
import 'package:cardsemble/features/wallet/domain/wallet_card.dart';

/// State holder for the Wallet landing tab.
///
/// Loads the connected accounts (Plaid items + statement accounts), matches each
/// to its card catalog entry (the same reference data used by the Research tab),
/// and assembles "Your Cards" and "Household cards" lists. Per-account balance,
/// utilization, benefit usage, and welcome-bonus spend are not yet served by the
/// backend, so they render as placeholders; benefit usage and bonus spend are
/// tracked locally in SharedPreferences and can be migrated to backend tables
/// later.
class WalletNotifier extends ChangeNotifier {
  WalletNotifier({required AccountsNotifier accounts, required CardCatalogRepository catalog})
      : _accounts = accounts,
        _catalog = catalog;

  final AccountsNotifier _accounts;
  final CardCatalogRepository _catalog;

  List<WalletCard> _yourCards = [];
  List<WalletCard> _householdCards = [];
  bool _isLoading = false;
  String? _error;
  DateTime? _lastUpdated;

  /// Locally persisted benefit usage: cardId -> {benefitId: used}.
  final Map<String, Map<String, bool>> _benefitUsage = {};
  /// Locally persisted benefit used-at timestamps: cardId -> {benefitId: ISO-8601}.
  final Map<String, Map<String, String>> _benefitUsedAt = {};
  /// Locally persisted bonus spend: cardId -> spent units.
  final Map<String, int> _bonusSpend = {};

  List<WalletCard> get yourCards => _yourCards;
  List<WalletCard> get householdCards => _householdCards;
  WalletSummary? get walletSummary => _accounts.walletSummary;
  bool get isLoading => _isLoading;
  String? get error => _error;
  DateTime? get lastUpdated => _lastUpdated;

  static const String _benefitUsageKeyPrefix = 'wallet.benefit_usage.v1.';
  static const String _benefitUsedAtKeyPrefix = 'wallet.benefit_used_at.v1.';
  static const String _bonusSpendKeyPrefix = 'wallet.bonus_spend.v1.';

  Future<SharedPreferences> _prefs() async => SharedPreferences.getInstance();

  /// Loads connections, statement cycles, and catalog cards, then assembles the
  /// card panels. Safe to call multiple times; reloads on each invocation.
  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await Future.wait<void>([
        _accounts.loadConnections(),
        _accounts.loadStatementCycles(),
        _accounts.loadWalletSummary(),
        _loadCatalog(),
      ]);

      _assembleCards();
      await _loadPersistedState();
      _applyPersistedState();
      _lastUpdated = DateTime.now();
    } catch (error) {
      _error = error.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadCatalog() async {
    final result = await _catalog.getAllCards();
    return result.fold(
      (cards) => _catalogCards = cards,
      (failure) {
        // Catalog backend may not be deployed yet; degrade gracefully so the
        // connected accounts still show with institution-level info.
        _catalogCards = const [];
        _error = failure.message;
      },
    );
  }

  List<CardCatalogCard> _catalogCards = [];

  /// Reads locally persisted benefit usage and bonus spend for the known card
  /// ids so the panels reflect the user's prior marks.
  Future<void> _loadPersistedState() async {
    final prefs = await _prefs();
    final ids = <String>{};
    ids.addAll(_yourCards.map((c) => c.id));
    ids.addAll(_householdCards.map((c) => c.id));

    for (final id in ids) {
      final usageRaw = prefs.getString('$_benefitUsageKeyPrefix$id');
      if (usageRaw != null) {
        try {
          final decoded = jsonDecode(usageRaw) as Map<String, dynamic>;
          _benefitUsage[id] = <String, bool>{
            for (final entry in decoded.entries)
              if (entry.value is bool) entry.key: entry.value as bool,
          };
        } catch (_) {
          _benefitUsage[id] = const {};
        }
      }
      final usedAtRaw = prefs.getString('$_benefitUsedAtKeyPrefix$id');
      if (usedAtRaw != null) {
        try {
          final decoded = jsonDecode(usedAtRaw) as Map<String, dynamic>;
          _benefitUsedAt[id] = <String, String>{
            for (final entry in decoded.entries)
              if (entry.value is String) entry.key: entry.value as String,
          };
        } catch (_) {
          _benefitUsedAt[id] = const {};
        }
      }
      final spendRaw = prefs.getString('$_bonusSpendKeyPrefix$id');
      if (spendRaw != null) {
        try {
          _bonusSpend[id] = int.tryParse(spendRaw) ?? 0;
        } catch (_) {
          _bonusSpend[id] = 0;
        }
      }
    }
  }

  /// Re-applies locally persisted benefit usage and bonus spend to the
  /// assembled cards so they survive a reload. Must be called after
  /// [_assembleCards] and [_loadPersistedState].
  void _applyPersistedState() {
    _yourCards = _yourCards.map((card) {
      final usedMap = _benefitUsage[card.id];
      final spent = _bonusSpend[card.id];
      if ((usedMap == null || usedMap.isEmpty) && spent == null) return card;
      return WalletCard(
        id: card.id,
        displayName: card.displayName,
        issuer: card.issuer,
        network: card.network,
        mask: card.mask,
        subtype: card.subtype,
        status: card.status,
        catalogCard: card.catalogCard,
        statementAccount: card.statementAccount,
        balanceCents: card.balanceCents,
        currency: card.currency,
        creditLimitCents: card.creditLimitCents,
        paymentDueDate: card.paymentDueDate,
        itemId: card.itemId,
        benefits: card.benefits.map((b) {
          final used = usedMap?[b.id] ?? b.used;
          return b.copyWith(used: used);
        }).toList(growable: false),
        welcomeBonus: card.welcomeBonus != null && spent != null
            ? WalletBonus(
                amountUnits: card.welcomeBonus!.amountUnits,
                currency: card.welcomeBonus!.currency,
                spendRequiredUnits: card.welcomeBonus!.spendRequiredUnits,
                spendCurrency: card.welcomeBonus!.spendCurrency,
                months: card.welcomeBonus!.months,
                description: card.welcomeBonus!.description,
                spentUnits: spent,
              )
            : card.welcomeBonus,
        catalogMatchStatus: card.catalogMatchStatus,
      );
    }).toList(growable: false);
    notifyListeners();
  }

  void _assembleCards() {
    final connections = _accounts.connections;
    final statementSummary = _accounts.statementSummary;
    final statementAccounts = statementSummary?.accounts ?? <StatementAccount>[];

    final byItemId = <String, StatementAccount>{};
    for (final account in statementAccounts) {
      if (account.itemId != null) {
        byItemId[account.itemId!] = account;
      }
    }

    final yourCards = <WalletCard>[];
    for (final connection in connections) {
      final statementAccount = byItemId[connection.itemId];
      final catalogCard = _matchCatalogCard(connection, statementAccount);
      final id = statementAccount?.accountId ?? connection.itemId;

      final benefits = _buildBenefits(catalogCard, id);
      final welcomeBonus = _buildBonus(catalogCard, id);

      yourCards.add(WalletCard(
        id: id,
        displayName: catalogCard?.name ?? connection.institutionName,
        issuer: catalogCard?.issuer ?? connection.institutionName,
        network: catalogCard?.network,
        mask: statementAccount?.mask,
        subtype: statementAccount?.subtype,
        status: connection.status,
        catalogCard: catalogCard,
        statementAccount: statementAccount,
        // Per-account balance, credit limit, currency, and payment due date
        // come from the synced Plaid credit account (fetched via statement
        // cycles). They are null until a sync has populated
        // plaid_credit_accounts, in which case the panel renders a "—"
        // placeholder.
        balanceCents: statementAccount?.currentBalanceCents,
        currency: statementAccount?.currency,
        creditLimitCents: statementAccount?.creditLimitCents,
        paymentDueDate: statementAccount?.nextPaymentDueDate,
        itemId: connection.itemId,
        benefits: benefits,
        welcomeBonus: welcomeBonus,
        catalogMatchStatus:
            catalogCard != null ? CatalogMatchStatus.matched : CatalogMatchStatus.unmatched,
      ));
    }
    yourCards.sort((a, b) => a.displayName.compareTo(b.displayName));

    // Household cards are not yet served by a backend endpoint (transaction and
    // account data remains user-scoped), so the section starts empty. The
    // structure is in place for when household account data becomes available.
    _yourCards = yourCards;
    _householdCards = const [];
  }

  CardCatalogCard? _matchCatalogCard(
    PlaidConnection connection,
    StatementAccount? statementAccount,
  ) {
    // Collect candidate names, split by specificity:
    // - stmtCandidates: full card names from the statement account
    //   (displayName, plaidName, officialName, accountName) — most precise
    // - instCandidates: institution names (connection + statement) — less specific
    final stmtCandidates = <String>[];
    final instCandidates = <String>[];

    final stmtDisplay = statementAccount?.displayName?.toLowerCase().trim();
    if (stmtDisplay != null && stmtDisplay.isNotEmpty) stmtCandidates.add(stmtDisplay);
    final stmtPlaid = statementAccount?.plaidName?.toLowerCase().trim();
    if (stmtPlaid != null && stmtPlaid.isNotEmpty) stmtCandidates.add(stmtPlaid);
    final stmtOfficial = statementAccount?.officialName?.toLowerCase().trim();
    if (stmtOfficial != null && stmtOfficial.isNotEmpty) stmtCandidates.add(stmtOfficial);
    final stmtAccountName = statementAccount?.accountName.toLowerCase().trim();
    if (stmtAccountName != null && stmtAccountName.isNotEmpty) stmtCandidates.add(stmtAccountName);

    final connectionName = connection.institutionName.toLowerCase().trim();
    if (connectionName.isNotEmpty) instCandidates.add(connectionName);
    final stmtInst = statementAccount?.institutionName?.toLowerCase().trim();
    if (stmtInst != null && stmtInst.isNotEmpty) instCandidates.add(stmtInst);

    if (stmtCandidates.isEmpty && instCandidates.isEmpty) return null;

    // 1. Exact full-name match against catalog card name (most precise).
    // Uses statement account names only, so "Chase Freedom Unlimited" matches
    // the catalog "Chase Freedom Unlimited" and not "Chase Aer Lingus".
    for (final card in _catalogCards) {
      final name = card.name.toLowerCase().trim();
      if (name.isEmpty) continue;
      if (stmtCandidates.any((c) => c == name)) return card;
    }

    // 2. Prefix match on catalog card name (e.g. candidate "Chase Freedom"
    // matches catalog "Chase Freedom Unlimited"). Statement account names only.
    CardCatalogCard? best;
    for (final card in _catalogCards) {
      final name = card.name.toLowerCase().trim();
      if (name.isEmpty) continue;
      final prefix = stmtCandidates.any(
        (c) => c.startsWith(name) || name.startsWith(c),
      );
      if (!prefix) continue;
      if (best == null || name.length > best.name.length) {
        best = card;
      }
    }
    if (best != null) return best;

    // 3. Issuer match only when there's exactly one card for that issuer.
    // If multiple cards share an issuer (e.g. Chase Freedom + Chase Aer Lingus),
    // don't guess — leave it unmatched so it shows the tag.
    //
    // Connection institution names may differ from catalog issuers (e.g.
    // "Chase Bank" vs "Chase"), so match when one contains the other rather than
    // requiring exact equality.
    final instSet = instCandidates.toSet();
    for (final card in _catalogCards) {
      final issuer = (card.issuer ?? '').toLowerCase().trim();
      if (issuer.isEmpty) continue;
      final matchesInst = instSet.any(
        (inst) => inst.contains(issuer) || issuer.contains(inst),
      );
      if (!matchesInst) continue;
      final sameIssuerCards = _catalogCards.where(
        (c) => instSet.any(
          (inst) => (c.issuer ?? '').toLowerCase().trim().contains(inst) || inst.contains((c.issuer ?? '').toLowerCase().trim()),
        ),
      ).toList(growable: false);
      if (sameIssuerCards.length == 1) return sameIssuerCards.single;
    }

    return null;
  }

  List<WalletBenefit> _buildBenefits(CardCatalogCard? catalogCard, String cardId) {
    final usedMap = _benefitUsage[cardId];
    final source = catalogCard?.benefits ?? const <CardBenefit>[];
    return source.map((benefit) {
      final id = benefit.id ?? benefit.title ?? '';
      final used = usedMap?[id] ?? false;
      final usedAt = _benefitUsedAt[cardId]?[id];
      return WalletBenefit(
        id: id,
        title: benefit.title ?? benefit.id ?? 'Benefit',
        category: benefit.category,
        source: benefit.source,
        description: benefit.description,
        amount: benefit.amount,
        currency: benefit.currency,
        expiresAt: benefit.expiresAt != null ? DateTime.tryParse(benefit.expiresAt!) : null,
        periodLength: benefit.periodLength,
        used: used,
        usedAt: usedAt != null ? DateTime.tryParse(usedAt) : null,
      );
    }).toList(growable: false);
  }

  WalletBonus? _buildBonus(CardCatalogCard? catalogCard, String cardId) {
    final sb = catalogCard?.signupBonus;
    if (sb == null || sb.amount == null || sb.spendRequired == null) return null;
    return WalletBonus(
      amountUnits: sb.amount!.toInt(),
      currency: sb.unit,
      spendRequiredUnits: sb.spendRequired!.toInt(),
      spendCurrency: sb.spendCurrency ?? sb.unit,
      months: sb.months,
      description: sb.description,
      spentUnits: _bonusSpend[cardId] ?? 0,
    );
  }

  /// Marks a benefit as used or unused and persists the choice.
  Future<void> toggleBenefit(String cardId, String benefitId, bool used) async {
    final map = <String, bool>{...(_benefitUsage[cardId] ?? const {})};
    map[benefitId] = used;
    _benefitUsage[cardId] = map;

    final usedAtMap = <String, String>{...(_benefitUsedAt[cardId] ?? const {})};
    if (used) {
      usedAtMap[benefitId] = DateTime.now().toIso8601String();
    } else {
      usedAtMap.remove(benefitId);
    }
    _benefitUsedAt[cardId] = usedAtMap;

    final index = _yourCards.indexWhere((c) => c.id == cardId);
    if (index != -1) {
      final card = _yourCards[index];
      _yourCards[index] = WalletCard(
        id: card.id,
        displayName: card.displayName,
        issuer: card.issuer,
        network: card.network,
        mask: card.mask,
        subtype: card.subtype,
        status: card.status,
        catalogCard: card.catalogCard,
        statementAccount: card.statementAccount,
        balanceCents: card.balanceCents,
        currency: card.currency,
        creditLimitCents: card.creditLimitCents,
        paymentDueDate: card.paymentDueDate,
        itemId: card.itemId,
        benefits: card.benefits.map((b) {
          if (b.id == benefitId) {
            return b.copyWith(used: used, usedAt: used ? DateTime.now() : null);
          }
          return b;
        }).toList(growable: false),
        welcomeBonus: card.welcomeBonus,
        catalogMatchStatus: card.catalogMatchStatus,
      );
    }
    notifyListeners();
    await _persistBenefitUsage(cardId);
    await _persistBenefitUsedAt(cardId);
  }

  /// Sets the spend counted toward a card's welcome bonus and persists it.
  Future<void> setBonusSpend(String cardId, int spentUnits) async {
    _bonusSpend[cardId] = spentUnits.clamp(0, 100000000);

    final index = _yourCards.indexWhere((c) => c.id == cardId);
    if (index != -1) {
      final card = _yourCards[index];
      final bonus = card.welcomeBonus;
      if (bonus != null) {
        _yourCards[index] = WalletCard(
          id: card.id,
          displayName: card.displayName,
          issuer: card.issuer,
          network: card.network,
          mask: card.mask,
          subtype: card.subtype,
          status: card.status,
          catalogCard: card.catalogCard,
          statementAccount: card.statementAccount,
        balanceCents: card.balanceCents,
        currency: card.currency,
        creditLimitCents: card.creditLimitCents,
        paymentDueDate: card.paymentDueDate,
        itemId: card.itemId,
        benefits: card.benefits,
          welcomeBonus: WalletBonus(
            amountUnits: bonus.amountUnits,
            currency: bonus.currency,
            spendRequiredUnits: bonus.spendRequiredUnits,
            spendCurrency: bonus.spendCurrency,
            months: bonus.months,
            description: bonus.description,
            spentUnits: spentUnits,
          ),
          catalogMatchStatus: card.catalogMatchStatus,
        );
      }
    }
    notifyListeners();
    await _persistBonusSpend(cardId);
  }

  Future<void> _persistBenefitUsage(String cardId) async {
    final prefs = await _prefs();
    final usageMap = _benefitUsage[cardId];
    if (usageMap != null) {
      await prefs.setString('$_benefitUsageKeyPrefix$cardId', jsonEncode(usageMap));
    }
    final usedAtMap = _benefitUsedAt[cardId];
    if (usedAtMap != null) {
      await prefs.setString('$_benefitUsedAtKeyPrefix$cardId', jsonEncode(usedAtMap));
    }
  }

  Future<void> _persistBenefitUsedAt(String cardId) async {
    final prefs = await _prefs();
    final map = _benefitUsedAt[cardId];
    if (map != null) {
      await prefs.setString('$_benefitUsedAtKeyPrefix$cardId', jsonEncode(map));
    }
  }

  Future<void> _persistBonusSpend(String cardId) async {
    final prefs = await _prefs();
    final spend = _bonusSpend[cardId];
    if (spend == null) return;
    await prefs.setString('$_bonusSpendKeyPrefix$cardId', spend.toString());
  }

  /// Rebuilds the card list from the currently loaded source data, re-applying
  /// locally persisted benefit usage and bonus spend.
  Future<void> refresh() => load();
}

extension _WalletBenefitCopy on WalletBenefit {
  WalletBenefit copyWith({
    bool? used,
    DateTime? usedAt,
  }) {
    return WalletBenefit(
      id: id,
      title: title,
      category: category,
      source: source,
      description: description,
      amount: amount,
      currency: currency,
      expiresAt: expiresAt,
      periodLength: periodLength,
      used: used ?? this.used,
      usedAt: usedAt ?? this.usedAt,
    );
  }
}
