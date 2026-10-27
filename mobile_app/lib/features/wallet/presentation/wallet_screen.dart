import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cardsemble/core/utils/currency.dart';
import 'package:cardsemble/theme/app_colors.dart';
import 'package:cardsemble/core/widgets/settings_gear_menu.dart';
import 'package:cardsemble/features/accounts/domain/accounts_domain.dart';
import 'package:cardsemble/features/accounts/presentation/accounts_notifier.dart';
import 'package:cardsemble/features/card_optimizer/data/card_optimizer_repository.dart';
import 'package:cardsemble/features/card_optimizer/presentation/card_optimizer_screen.dart';
import 'package:cardsemble/features/wallet/domain/wallet_card.dart';
import 'package:cardsemble/features/wallet/presentation/wallet_card_colors.dart';
import 'package:cardsemble/features/wallet/presentation/wallet_notifier.dart';
import 'package:cardsemble/features/wallet/presentation/widgets/wallet_card_panel.dart';
import 'package:cardsemble/features/wallet/presentation/widgets/wallet_card_carousel.dart';

/// Wallet landing tab.
///
/// Shows the cards that are actually in the user's wallet (connected accounts,
/// enriched with catalog reference data from the Research tab) under "Your
/// Cards", plus a "Household cards" section for cards owned by others in the
/// household (empty until household account data is served by the backend).
///
/// "Your cards" can be shown as a vertical stack or as a horizontal carousel,
/// toggled from the layout header. Tapping a card drops down its details pane
/// (annual fee, FX fee, benefits, travel perks).
class WalletScreen extends StatefulWidget {
  const WalletScreen({
    super.key,
    this.onOpenSettings,
    this.onOpenCardEvents,
    this.onOpenManageHousehold,
  });

  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenCardEvents;
  final VoidCallback? onOpenManageHousehold;

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  /// Whether "Your cards" is shown as a horizontal carousel (true) or a
  /// vertical stack (false).
  bool _useCarousel = true;

  /// Ids of cards whose details pane is expanded in the vertical layout.
  final Set<String> _expandedIds = <String>{};

  void _toggleCard(String id) {
    setState(() {
      if (_expandedIds.contains(id)) {
        _expandedIds.remove(id);
      } else {
        _expandedIds.add(id);
      }
    });
  }

  void _setLayout(bool useCarousel) => setState(() => _useCarousel = useCarousel);

  void _showCardDetails(BuildContext context, WalletCard card) {
    final color = WalletCardColors.accentColor(card);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      // showDragHandle injects a 48px-tall handle above the builder content,
      // so we drop the top padding to avoid growing the sheet visually.
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: CardDetails(card: card, color: color, scrollable: true),
      ),
    );
  }

  /// Re-authenticates a single errored Plaid item via Plaid Link update mode.
  Future<void> _resyncCard(BuildContext context, WalletCard card) async {
    final accounts = context.read<AccountsNotifier>();
    final wallet = context.read<WalletNotifier>();
    final itemId = card.itemId;
    if (itemId == null) return;

    final success = await accounts.relinkItem(itemId, card.displayName);

    if (!mounted) return;

    if (success) {
      // relinkItem() -> exchangePublicToken() refreshes the AccountsNotifier
      // snapshots; WalletNotifier's listener also rebuilds automatically.
      // Reload explicitly so persisted local state is re-applied.
      await wallet.load();
    }

    if (!mounted) return;

    final error = accounts.error;
    final warning = accounts.warning;
    final message = error ??
        warning ??
        (!success
            ? 'Could not re-authenticate the card. Please try again.'
            : 'Connection restored.');

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  /// Triggers a full Plaid sync (which writes to the Supabase DB) and then
  /// reloads the wallet. Awaits the sync so the wallet only reads fresh data
  /// after the backend has finished writing.
  Future<void> _syncAccounts() async {
    final accounts = context.read<AccountsNotifier>();
    final wallet = context.read<WalletNotifier>();
    if (accounts.isSyncing || wallet.isLoading) return;

    final success = await accounts.syncConnections();
    if (!mounted) return;

    // Capture the sync result before load() reuses the shared AccountsNotifier
    // error/warning channels.
    final syncError = accounts.error;
    final syncWarning = accounts.warning;

    // syncConnections() resolves only after the Edge Function wrote the sync
    // results and the notifier re-read the DB. load() is DB-only; it does not
    // call Plaid.
    await wallet.load();
    if (!mounted) return;

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(syncError ?? 'Could not sync accounts.')),
      );
      return;
    }

    if (syncWarning != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(syncWarning)),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<WalletNotifier>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        title: const Text('Wallet'),
        actions: [
          Consumer<WalletNotifier>(
            builder: (context, wallet, _) {
              final busy = wallet.isLoading || wallet.isSyncing;
              return IconButton(
                icon: busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.onPrimary,
                        ),
                      )
                    : const Icon(Icons.sync),
                onPressed: busy ? null : _syncAccounts,
                tooltip: busy ? 'Syncing accounts…' : 'Sync Plaid accounts',
              );
            },
          ),
          SettingsGearMenu(
            onOpenSettings: widget.onOpenSettings,
            onOpenCardEvents: widget.onOpenCardEvents,
            onOpenManageHousehold: widget.onOpenManageHousehold,
          ),
        ],
      ),
      body: Consumer<WalletNotifier>(
        builder: (context, notifier, child) {
          final summaryReady = notifier.walletSummary?.isFullySynced ?? false;

          // Wait for an in-flight sync before rendering the placeholder-heavy
          // wallet. If fully synced data already exists, keep it visible and
          // show the progress banner instead of blanking the page.
          if (notifier.isSyncing && !summaryReady) {
            return _WalletWaitingView(syncing: true);
          }

          // Show a loading spinner on first load, before any cards have been
          // assembled from the async data sources. Once `load()` has completed
          // at least once, fall back to the normal UI (including the empty
          // state) so pull-to-refresh and retry still render content.
          if (notifier.isLoading && notifier.yourCards.isEmpty) {
            return _WalletWaitingView(syncing: false);
          }
          final matchedCards = notifier.yourCards
              .where((card) => card.catalogCard != null)
              .map((card) => card.catalogCard!)
              .toList(growable: false);
          return RefreshIndicator(
            onRefresh: () async => await notifier.load(),
            child: CustomScrollView(
              slivers: [
                if (notifier.isSyncing)
                  const SliverToBoxAdapter(child: _SyncProgressBanner()),
                SliverToBoxAdapter(
                  child: _Header(
                    error: notifier.error,
                    onRetry: () => notifier.load(),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _WalletSummaryCard(
                    summary: notifier.walletSummary,
                    cards: notifier.yourCards.length,
                    isSyncing: notifier.isSyncing,
                  ),
                ),
                SliverToBoxAdapter(
                  child: _LayoutToggle(
                    useCarousel: _useCarousel,
                    onChanged: _setLayout,
                  ),
                ),
                if (_useCarousel)
                  _YourCardsCarouselSection(
                    notifier: notifier,
                    onCardTap: (card) => _showCardDetails(context, card),
                    onResync: (card) => _resyncCard(context, card),
                  )
                else
                  _YourCardsSection(
                    notifier: notifier,
                    expandedIds: _expandedIds,
                    onToggleCard: _toggleCard,
                    onResync: (card) => _resyncCard(context, card),
                  ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                  sliver: SliverToBoxAdapter(
                    child: SizedBox(
                      width: double.infinity,
                      child: Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => context.read<AccountsNotifier>().linkAccount(),
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Link a card'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                textStyle:
                                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: matchedCards.isEmpty
                                  ? null
                                  : () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) => CardOptimizerScreen(
                                            selectedCards: matchedCards,
                                            repository: context.read<CardOptimizerRepository>(),
                                          ),
                                        ),
                                      );
                                    },
                              icon: const Icon(Icons.auto_awesome, size: 18),
                              label: const Text('Optimize'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
                  sliver: SliverToBoxAdapter(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: _SectionHeader(
                          title: 'Household cards',
                          subtitle: 'Cards owned by others in your household',
                        ),
                      ),
                    ),
                  ),
                ),
                _HouseholdCardsSection(
                  notifier: notifier,
                  expandedIds: _expandedIds,
                  onToggleCard: _toggleCard,
                ),
                const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _LayoutToggle extends StatelessWidget {
  const _LayoutToggle({
    required this.useCarousel,
    required this.onChanged,
  });

  final bool useCarousel;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: SegmentedButton<bool>(
        selected: <bool>{useCarousel},
        onSelectionChanged: (selection) => onChanged(selection.first),
        segments: const <ButtonSegment<bool>>[
          ButtonSegment<bool>(
            value: true,
            icon: Icon(Icons.view_agenda_outlined, size: 18),
            label: Text('Carousel'),
          ),
          ButtonSegment<bool>(
            value: false,
            icon: Icon(Icons.view_list_outlined, size: 18),
            label: Text('List'),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({this.error, this.onRetry});

  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (error != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, size: 16, color: AppColors.error),
                  const SizedBox(width: 8),
                  Expanded(child: Text(error!, style: const TextStyle(fontSize: 12, color: AppColors.error))),
                  const SizedBox(width: 8),
                  if (onRetry != null)
                    TextButton(onPressed: onRetry, child: const Text('Retry')),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.subtitle, this.titleStyle});

  final String title;
  final String? subtitle;
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: titleStyle ?? const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.charcoal),
        ),
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ],
      ],
    );
  }
}

/// Aggregation card shown above "Your Cards".
///
/// Surfaces real Plaid-derived totals: total credit limit, utilization,
/// number of cards, and the highest payment in the past 30 days. Renders
/// placeholders when the data has not yet been synced.
class _WalletSummaryCard extends StatelessWidget {
  const _WalletSummaryCard({
    required this.summary,
    required this.cards,
    required this.isSyncing,
  });

  final WalletSummary? summary;
  final int cards;
  final bool isSyncing;

  @override
  Widget build(BuildContext context) {
    if (cards == 0) return const SizedBox.shrink();

    final primary = summary?.primary;
    final isFullySynced = summary?.isFullySynced ?? false;

    final limitText = primary != null && primary.hasLimitData
        ? formatCurrency(primary.creditLimitCents / 100, primary.currency)
        : '—';
    final utilText = primary != null && primary.utilization != null
        ? '${(primary.utilization! * 100).round()}%'
        : '—';
    final payment = summary?.highestPayment;
    final paymentText = payment != null
        ? formatCurrency(payment.amountCents / 100, payment.currency)
        : '—';

    final captionParts = <String>[];
    if (summary != null && summary!.otherCurrencyCount > 0) {
      captionParts.add(
          'Showing ${summary!.primaryCurrency} · ${summary!.otherCurrencyCount} other currency not included');
    }
    if (!isFullySynced) {
      captionParts.add(
          'Partially synced (${primary?.accountsWithLimit ?? 0} of $cards cards)');
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _SectionHeader(
                title: 'Your Cards',
                titleStyle: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 12),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 2.0,
                children: [
                  _SummaryMetric(
                    label: 'Total credit limit',
                    value: limitText,
                    subtitle: primary == null || primary.hasLimitData
                        ? null
                        : 'Limit not yet synced',
                  ),
                  _SummaryMetric(
                    label: 'Utilization',
                    value: utilText,
                    subtitle: primary != null && primary.utilization != null
                        ? '${primary.cardCount} card(s)'
                        : null,
                  ),
          _SummaryMetric(
            label: 'Number of cards',
            value: summary?.cardCount.toString() ?? '0',
            subtitle: isFullySynced
                ? 'All synced'
                : (isSyncing ? 'Syncing…' : 'Partially synced'),
          ),
                  _SummaryMetric(
                    label: 'Highest payment',
                    value: paymentText,
                    subtitle: payment != null
                        ? 'Last 30 days · ${payment.date != null ? _formatDate(payment.date!) : '—'}'
                        : 'No payments found',
                  ),
                ],
              ),
              if (captionParts.isNotEmpty) ...[
                const SizedBox(height: 8),
                  Text(
                    captionParts.join('  •  '),
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.value,
    this.subtitle,
  });

  final String label;
  final String value;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.charcoal,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
      ],
    );
  }
}

class _WalletWaitingView extends StatelessWidget {
  const _WalletWaitingView({required this.syncing});

  final bool syncing;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              syncing ? 'Syncing your cards…' : 'Loading your wallet…',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            if (syncing) ...[
              const SizedBox(height: 6),
              const Text(
                'Waiting for balances and payment dates to finish syncing.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SyncProgressBanner extends StatelessWidget {
  const _SyncProgressBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppColors.cream,
      child: const Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text('Syncing your cards…', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _YourCardsSection extends StatelessWidget {
  const _YourCardsSection({
    required this.notifier,
    required this.expandedIds,
    required this.onToggleCard,
    required this.onResync,
  });

  final WalletNotifier notifier;
  final Set<String> expandedIds;
  final ValueChanged<String> onToggleCard;
  final Future<void> Function(WalletCard) onResync;

  @override
  Widget build(BuildContext context) {
    final cards = notifier.yourCards;
    if (cards.isEmpty) {
      return SliverToBoxAdapter(
        child: _EmptyState(
          icon: Icons.credit_card_outlined,
          title: 'No cards in your wallet yet',
          body: 'Link a credit card account to see your cards, benefits, and welcome bonus progress here.',
        ),
      );
    }
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final card = cards[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: WalletCardPanel(
                  card: card,
                  mode: WalletCardPanelMode.expandable,
                  expanded: expandedIds.contains(card.id),
                  onTap: () => onToggleCard(card.id),
                  onResync: card.needsRelink ? () => onResync(card) : null,
                ),
              ),
            ),
          );
        },
        childCount: cards.length,
      ),
    );
  }
}

class _YourCardsCarouselSection extends StatelessWidget {
  const _YourCardsCarouselSection({
    required this.notifier,
    required this.onCardTap,
    required this.onResync,
  });

  final WalletNotifier notifier;
  final ValueChanged<WalletCard> onCardTap;
  final Future<void> Function(WalletCard) onResync;

  @override
  Widget build(BuildContext context) {
    final cards = notifier.yourCards;
    if (cards.isEmpty) {
      return SliverToBoxAdapter(
        child: _EmptyState(
          icon: Icons.credit_card_outlined,
          title: 'No cards in your wallet yet',
          body: 'Link a credit card account to see your cards, benefits, and welcome bonus progress here.',
        ),
      );
    }
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          WalletCardCarousel(
            cards: cards,
            onCardTap: onCardTap,
            onResync: onResync,
            carouselHeight: _carouselItemHeight,
          ),
        ],
      ),
    );
  }
}

class _HouseholdCardsSection extends StatelessWidget {
  const _HouseholdCardsSection({
    required this.notifier,
    required this.expandedIds,
    required this.onToggleCard,
  });

  final WalletNotifier notifier;
  final Set<String> expandedIds;
  final ValueChanged<String> onToggleCard;

  @override
  Widget build(BuildContext context) {
    final cards = notifier.householdCards;
    if (cards.isEmpty) {
      return SliverToBoxAdapter(
        child: _EmptyState(
          icon: Icons.people_outlined,
          title: 'No household cards shared yet',
          body: 'Cards owned by others in your household will appear here once household account data is available.',
        ),
      );
    }
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final card = cards[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: WalletCardPanel(
                  card: card,
                  mode: WalletCardPanelMode.expandable,
                  expanded: expandedIds.contains(card.id),
                  onTap: () => onToggleCard(card.id),
                ),
              ),
            ),
          );
        },
        childCount: cards.length,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.charcoal),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(fontSize: 13, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Height of one collapsed card inside the horizontal carousel.
const double _carouselItemHeight = 264;
