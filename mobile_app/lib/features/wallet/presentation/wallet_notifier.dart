import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cardsemble/features/accounts/domain/accounts_domain.dart';
import 'package:cardsemble/features/accounts/presentation/accounts_notifier.dart';
import 'package:cardsemble/features/card_catalog/data/card_catalog_repository.dart';
import 'package:cardsemble/features/card_catalog/domain/entities/card_catalog_card.dart';
import 'package:cardsemble/features/transactions/presentation/transactions_notifier.dart';
import 'package:cardsemble/features/wallet/domain/wallet_card.dart';
import 'package:cardsemble/features/wallet/domain/benefit_spending.dart';

/// State holder for the Wallet landing tab.
///
/// Loads the connected accounts (Plaid items + statement accounts), matches each
/// to its card catalog entry (the same reference data used by the Research tab),
/// and assembles "Your Cards" and "Household cards" lists. The wallet summary
/// metrics (card count, highest cost transaction) are computed client-side: card count
/// comes from the connected items and the highest cost transaction is derived from the loaded
/// transaction list. Benefit usage and welcome-bonus spend are tracked locally
/// in SharedPreferences and can be migrated to backend tables later.
class WalletNotifier extends ChangeNotifier {
  WalletNotifier({
    required AccountsNotifier accounts,
    required CardCatalogRepository catalog,
    required TransactionsNotifier transactions,
  })  : _accounts = accounts,
        _catalog = catalog,
        _transactions = transactions {
    _accounts.addListener(_onAccountsChanged);
    _transactions.addListener(_onTransactionsChanged);
  }

  final AccountsNotifier _accounts;
  final CardCatalogRepository _catalog;
  final TransactionsNotifier _transactions;

  List<WalletCard> _yourCards = [];
  List<WalletCard> _householdCards = [];
  bool _isLoading = false;
  String? _error;
  DateTime? _lastUpdated;

  /// Prevents the AccountsNotifier listener from re-entering while it is
  /// rebuilding the card panels.
  bool _applyingAccountsUpdate = false;

  /// A non-sync AccountsNotifier change arrived while load() was running.
  bool _accountsRefreshPending = false;

  /// load() was requested while a sync was in flight; retry it once the sync
  /// completion notification arrives.
  bool _pendingLoadAfterSync = false;

  /// Whether the catalog load has completed (success or failure). Once true a
  /// failed load is not retried, so card colors are determined once at first
  /// paint and never change on a later retry.
  bool _catalogLoaded = false;

  /// Whether a load / initial assembly has begun. Distinguishes "not started"
  /// (show empty state immediately) from "preparing" (show the waiting wheel).
  bool _hasStarted = false;

  /// Whether the first catalog + accounts + transactions assembly has
  /// completed. Once true, silent listener-driven reassemblies do not re-show
  /// the waiting view (cards are retained).
  bool _initialAssemblyDone = false;

  /// Whether the first *complete* assembly is still pending. The screen shows
  /// the waiting view for this whole window so partially-assembled cards are
  /// never painted. Unlike [isPreparing], this stays true until accounts have
  /// fully settled (connections + statement cycles), not just until
  /// _isLoading flips.
  bool get isInitialAssemblyPending =>
      _hasStarted && !_disposed && !_initialAssemblyDone;

  /// Whether dispose() has been called.
  bool _disposed = false;

  /// Whether the wallet is still assembling its initial card data: accounts,
  /// catalog research data matched to the connected accounts, and the first
  /// transaction load. While preparing, the screen shows the loading wheel
  /// instead of an empty/partial wallet. The wheel covers the whole load()
  /// window (including the final transaction load) via _isLoading, and silent
  /// reassemblies after the first assembly never re-show it.
  bool get isPreparing =>
      _hasStarted && !_disposed && (_isLoading || !_initialAssemblyDone);

  /// Issuer resolved on the first complete assembly, keyed by the stable Plaid
  /// item id. Later assemblies (sync, rename, statement reload, catalog retry)
  /// reuse it, so a card's accent color can never change after first paint.
  final Map<String, String> _issuerByItemId = {};

  /// Locally persisted benefit usage: cardId -> {benefitId: used}.
  final Map<String, Map<String, bool>> _benefitUsage = {};
  /// Locally persisted benefit used-at timestamps: cardId -> {benefitId: ISO-8601}.
  final Map<String, Map<String, String>> _benefitUsedAt = {};
  /// Locally persisted bonus spend: cardId -> spent units.
  final Map<String, int> _bonusSpend = {};

  List<WalletCard> get yourCards => _yourCards;
  List<WalletCard> get householdCards => _householdCards;
  bool get isLoading => _isLoading;
  bool get isSyncing => _accounts.isSyncing;
  String? get error => _error;
  DateTime? get lastUpdated => _lastUpdated;

  /// Whether the transaction list has not yet finished its first successful
  /// load. The highest-cost transaction metric is not meaningful until
  /// transactions are available.
  bool get isTransactionsLoading => !_transactions.hasLoadedTransactions;

  static const String _benefitUsageKeyPrefix = 'wallet.benefit_usage.v1.';
  static const String _benefitUsedAtKeyPrefix = 'wallet.benefit_used_at.v1.';
  static const String _bonusSpendKeyPrefix = 'wallet.bonus_spend.v1.';

  Future<SharedPreferences> _prefs() async => SharedPreferences.getInstance();

  /// Assembles the card panels from the account / statement-cycle data.
  /// Connections and statement cycles are fetched once at app startup by
  /// MainTabs and shared across tabs via AccountsNotifier; this method falls
  /// back to fetching them directly if they haven't been loaded yet (e.g. when
  /// called before startup completes or in tests). No Plaid API is involved —
  /// both calls read from the local Supabase mirror of synced Plaid data.
  /// Loads (or refreshes) the wallet cards.
  ///
  /// When [refreshAccounts] is true the shared account/statement data is
  /// re-fetched while [_isLoading] is true, so the waiting view/spinner is
  /// shown until the full card data is reassembled. Existing cards are cleared
  /// at the start of a refresh so stale cards are not visible during reload.
  /// The default (cached) load only reassembles from already-loaded accounts
  /// and does not clear or refetch, avoiding flicker on silent reloads/resume.
  Future<void> load({bool refreshAccounts = false}) async {
    // Never read mid-sync snapshots. The sync-completion listener will rerun
    // this load after the server writes and AccountsNotifier reloads land.
    if (_accounts.isSyncing) {
      _pendingLoadAfterSync = true;
      _isLoading = true;
      _error = null;
      _hasStarted = true;
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = null;
    _hasStarted = true;
    // Clear existing panels so the waiting view (spinner) shows while fresh
    // card data is fetched and assembled, instead of leaving stale cards
    // visible during a reload.
    if (refreshAccounts) {
      _yourCards = [];
      _householdCards = [];
    }
    notifyListeners();

    try {
      // MainTabs loads accounts once at startup. Refreshes (and direct loads
      // before startup completes) re-fetch the shared account/statement data
      // so the panels assemble from current data. Only assemble once both
      // connections and statement cycles have settled so a card's issuer is
      // resolved from complete data and its color never changes mid-session.
      if (
        refreshAccounts ||
        !_accounts.isSnapshotSettled
      ) {
        await Future.wait<void>([
          _accounts.loadConnections(),
          _accounts.loadStatementCycles(),
        ]);
      }

      await _applyAccountsSnapshot();

      // The wallet is not ready until the first transaction load has settled.
      // loadAll() coalesces with MainTabs' startup load and completes on
      // failure, so this cannot hang on a failed transaction fetch.
      if (!_transactions.hasLoadedTransactions) {
        await _transactions.loadAll();
      }
    } catch (error) {
      _error = error.toString();
    } finally {
      _isLoading = false;
      notifyListeners();

      if (_accountsRefreshPending && !_disposed && !_accounts.isSyncing) {
        _accountsRefreshPending = false;
        await _applyAccountsSnapshot();
      }
    }
  }

  /// Listens for AccountsNotifier changes (sync start/stop, snapshot refreshes)
  /// and relays them so the wallet UI stays current without extra Plaid calls.
  /// The guard flags prevent re-entrancy loops with load().
  void _onAccountsChanged() {
    if (_disposed) return;

    if (_accounts.isSyncing) {
      // Surface the sync state to the screen, but do not touch the snapshots
      // until the sync's post-write reloads have completed.
      notifyListeners();
      return;
    }

    if (_pendingLoadAfterSync) {
      _pendingLoadAfterSync = false;
      _isLoading = false;
      _hasStarted = true;
      unawaited(load());
      return;
    }

    if (_applyingAccountsUpdate) {
      _accountsRefreshPending = true;
      return;
    }

    if (_isLoading) {
      _accountsRefreshPending = true;
      return;
    }

    // Mark that account activity has begun so the screen shows the waiting
    // view while the initial catalog research load assembles cards.
    _hasStarted = true;

    // Never assemble from a half-populated account snapshot. Both connections
    // and statement cycles must settle first so the issuer (and color) is
    // resolved from complete data once.
    if (!_accounts.isSnapshotSettled) return;

    // The initial assembly must run through load() so the spinner covers the
    // catalog fetch and the first transaction load. Once the wallet has been
    // assembled once, silent listener-driven reassemblies stay flicker-free.
    if (!_initialAssemblyDone) {
      unawaited(load());
      return;
    }

    unawaited(_applyAccountsSnapshot());
  }

  /// Listens for TransactionsNotifier changes so the highest-cost transaction
  /// metric (derived from the loaded transaction list) updates when new
  /// transactions arrive.
  void _onTransactionsChanged() {
    if (_disposed) return;
    notifyListeners();
  }

  /// The largest charge (cost) found in the loaded transactions within the
  /// currently selected date range (e.g. a month chip picked in the
  /// Transactions tab). Falls back to the trailing 30 days from now when no
  /// range is selected (e.g. after "Clear all"). Considers only positive
  /// amounts (Plaid charges are positive), excluding pending rows, explicit
  /// payments (`transaction_code == 'payment'`), and transactions without a
  /// parseable date. Returns null when no transactions have been loaded yet or
  /// no qualifying charge is found in the window.
  WalletCostTransaction? get highestCostTransaction {
    final txs = _transactions.transactions;
    if (txs.isEmpty) return null;

    // Respect the active date range so the metric matches the transactions the
    // user is viewing; otherwise fall back to the trailing 30 days from now.
    // The +/- 1 day buffer mirrors filteredTransactions so a charge on the
    // range boundary is still counted.
    final selectedRange = _transactions.dateRange;
    final rangeStart = selectedRange?.start;
    final rangeEnd = selectedRange?.end;
    final fallbackCutoff = DateTime.now().subtract(const Duration(days: 30));

    WalletCostTransaction? best;
    double? bestAmount;

    for (final tx in txs) {
      if (tx.pending) continue;
      if (tx.isPayment) continue; // skip explicit payment rows
      final date = tx.parsedDate;
      if (date == null) continue;
      if (rangeStart != null && date.isBefore(rangeStart.subtract(const Duration(days: 1)))) continue;
      if (rangeEnd != null && date.isAfter(rangeEnd.add(const Duration(days: 1)))) continue;
      if (rangeStart == null && date.isBefore(fallbackCutoff)) continue;
      final amount = tx.amountValue;
      if (amount <= 0) continue; // charges are positive in Plaid

      if (best == null || amount > bestAmount!) {
        best = WalletCostTransaction(
          transactionId: tx.id,
          accountId: tx.accountId,
          accountName: tx.displayName ?? tx.accountName ?? tx.plaidName,
          amountCents: (amount * 100).round(),
          currency: tx.currency,
          date: date,
          name: tx.name,
          merchantName: tx.merchant,
        );
        bestAmount = amount;
      }
    }

    return best;
  }

  /// Label describing the window [highestCostTransaction] scans: the selected
  /// month when a date chip is active (start of month to current/selected date),
  /// otherwise the trailing 30 days. Shown without a year. Used by the wallet
  /// summary card so the subtitle matches the window actually used.
  String get highestCostWindow {
    final selectedRange = _transactions.dateRange;
    if (selectedRange != null) {
      final start = DateFormat.MMMd().format(selectedRange.start);
      final end = DateFormat.MMMd().format(selectedRange.end);
      return '$start – $end';
    }
    return 'Last 30 days';
  }

  /// Computes spending toward this card's benefits from the loaded transaction
  /// list. Returns null when the card has no statement account or no mappable
  /// benefit categories.
  WalletBenefitSpending? benefitSpendingFor(WalletCard card) {
    return calculateBenefitSpending(
      card: card,
      transactions: _transactions.transactions,
    );
  }

  /// Rebuilds the card panels from the connections / statement cycles / wallet
  /// summary that AccountsNotifier already refreshed. This reads no network
  /// resources; the only I/O is the local SharedPreferences state.
  Future<void> _applyAccountsSnapshot() async {
    if (_disposed || _applyingAccountsUpdate) return;
    _applyingAccountsUpdate = true;

    try {
      if (!_catalogLoaded) {
        await _loadCatalog();
      }
      _assembleCards();
      await _loadPersistedState();
      if (_disposed) return;
      _applyPersistedState(); // notifies listeners
      _lastUpdated = DateTime.now();
      // The first catalog + accounts + persisted-state assembly is complete.
      // From here on, silent listener-driven reassemblies do not re-show the
      // waiting view (cards are retained).
      _initialAssemblyDone = true;
    } finally {
      _applyingAccountsUpdate = false;
      // If an AccountsNotifier change arrived while we were rebuilding, re-apply
      // from the fresh data so the UI never shows a stale empty snapshot.
      if (_accountsRefreshPending) {
        _accountsRefreshPending = false;
        unawaited(_applyAccountsSnapshot());
      }
    }
  }

  Future<void> _loadCatalog() async {
    final result = await _catalog.getAllCards();
    result.fold(
      (cards) {
        _catalogCards = cards;
        _catalogLoaded = true;
      },
      (failure) {
        // Catalog backend may not be deployed yet; degrade gracefully so the
        // connected accounts still show with institution-level info. Mark the
        // catalog as loaded so a failed load is final — card colors are
        // determined once at first paint and never change on a later retry.
        _catalogCards = const [];
        _catalogLoaded = true;
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
      return card.copyWith(
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
      );
    }).toList(growable: false);
    notifyListeners();
  }

  void _assembleCards() {
    final connections = _accounts.connections;
    final statementSummary = _accounts.statementSummary;
    final statementAccounts = statementSummary?.accounts ?? <StatementAccount>[];

    // Index connections by item_id so each statement account can resolve its
    // owning Plaid connection (institution name, status, item id).
    final byItemId = <String, PlaidConnection>{};
    for (final connection in connections) {
      byItemId[connection.itemId] = connection;
    }

    final yourCards = <WalletCard>[];
    final coveredItemIds = <String>{};
    for (final account in statementAccounts) {
      final connection = byItemId[account.itemId ?? ''];
      if (account.itemId != null) coveredItemIds.add(account.itemId!);
      final catalogCard = _matchCatalogCard(connection ?? _placeholderConnection(account), account);
      final id = account.accountId;

      final benefits = _buildBenefits(catalogCard, id);
      final welcomeBonus = _buildBonus(catalogCard, id);

      yourCards.add(WalletCard(
        id: id,
        displayName: account.displayName ??
            catalogCard?.name ??
            connection?.institutionName ??
            account.accountName,
        issuer: _issuerByItemId.putIfAbsent(
          account.itemId ?? id,
          () {
            final catalogIssuer = catalogCard?.issuer?.trim();
            return (catalogIssuer != null && catalogIssuer.isNotEmpty)
                ? catalogIssuer
                : connection?.institutionName ?? account.institutionName ?? account.accountName;
          },
        ),
        network: catalogCard?.network,
        mask: account.mask,
        subtype: account.subtype,
        status: connection?.status ?? 'connected',
        catalogCard: catalogCard,
        statementAccount: account,
        currency: account.currency,
        paymentDueDate: account.nextPaymentDueDate,
        itemId: account.itemId,
        benefits: benefits,
        welcomeBonus: welcomeBonus,
        catalogMatchStatus:
            catalogCard != null ? CatalogMatchStatus.matched : CatalogMatchStatus.unmatched,
        cardType: account.cardType,
        defaultAssigneeMode: account.defaultAssigneeMode,
        defaultAssigneePersonId: account.defaultAssigneePersonId,
        defaultAssigneeName: account.defaultAssigneeName,
      ));
    }

    // Connections without a statement account (e.g. not yet synced) still
    // appear as cards so no connected card is hidden from the wallet.
    for (final connection in connections) {
      if (coveredItemIds.contains(connection.itemId)) continue;
      final id = connection.itemId;
      final catalogCard = _matchCatalogCard(connection, null);
      yourCards.add(WalletCard(
        id: id,
        displayName: catalogCard?.name ?? connection.institutionName,
        issuer: _issuerByItemId.putIfAbsent(
          connection.itemId,
          () {
            final catalogIssuer = catalogCard?.issuer?.trim();
            return (catalogIssuer != null && catalogIssuer.isNotEmpty)
                ? catalogIssuer
                : connection.institutionName;
          },
        ),
        network: catalogCard?.network,
        status: connection.status,
        catalogCard: catalogCard,
        statementAccount: null,
        currency: null,
        paymentDueDate: null,
        itemId: connection.itemId,
        benefits: _buildBenefits(catalogCard, id),
        welcomeBonus: _buildBonus(catalogCard, id),
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

  /// A stand-in connection used when a statement account exists but its Plaid
  /// item is not (yet) in the connections list. Keeps catalog matching working
  /// using the account's own identifying fields.
  PlaidConnection _placeholderConnection(StatementAccount account) {
    return PlaidConnection(
      itemId: account.itemId ?? account.accountId,
      institutionName: account.institutionName ?? account.accountName,
      status: 'connected',
    );
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
      _yourCards[index] = card.copyWith(
        benefits: card.benefits.map((b) {
          if (b.id == benefitId) {
            return b.copyWith(used: used, usedAt: used ? DateTime.now() : null);
          }
          return b;
        }).toList(growable: false),
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
        _yourCards[index] = card.copyWith(
          welcomeBonus: WalletBonus(
            amountUnits: bonus.amountUnits,
            currency: bonus.currency,
            spendRequiredUnits: bonus.spendRequiredUnits,
            spendCurrency: bonus.spendCurrency,
            months: bonus.months,
            description: bonus.description,
            spentUnits: spentUnits,
          ),
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

  @override
  void dispose() {
    _disposed = true;
    _accounts.removeListener(_onAccountsChanged);
    _transactions.removeListener(_onTransactionsChanged);
    super.dispose();
  }
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
