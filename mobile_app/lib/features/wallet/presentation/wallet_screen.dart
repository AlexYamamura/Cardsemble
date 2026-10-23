import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cardsemble/theme/app_colors.dart';
import 'package:cardsemble/core/widgets/settings_gear_menu.dart';
import 'package:cardsemble/features/accounts/presentation/accounts_notifier.dart';
import 'package:cardsemble/features/card_optimizer/data/card_optimizer_repository.dart';
import 'package:cardsemble/features/card_optimizer/presentation/card_optimizer_screen.dart';
import 'package:cardsemble/features/wallet/domain/wallet_card.dart';
import 'package:cardsemble/features/wallet/presentation/wallet_card_colors.dart';
import 'package:cardsemble/features/wallet/presentation/wallet_notifier.dart';
import 'package:cardsemble/features/wallet/presentation/widgets/wallet_card_panel.dart';

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
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: CardDetails(card: card, color: color, scrollable: true),
      ),
    );
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
          SettingsGearMenu(
            onOpenSettings: widget.onOpenSettings,
            onOpenCardEvents: widget.onOpenCardEvents,
            onOpenManageHousehold: widget.onOpenManageHousehold,
          ),
        ],
      ),
      body: Consumer<WalletNotifier>(
        builder: (context, notifier, child) {
          final matchedCards = notifier.yourCards
              .where((card) => card.catalogCard != null)
              .map((card) => card.catalogCard!)
              .toList(growable: false);
          return RefreshIndicator(
            onRefresh: () async => await notifier.load(),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _Header(
                    error: notifier.error,
                    onRetry: () => notifier.load(),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  sliver: SliverToBoxAdapter(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: _SectionHeader(title: 'Your Cards', subtitle: 'Connected credit card accounts'),
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                  sliver: SliverToBoxAdapter(
                    child: SizedBox(
                      width: double.infinity,
                      child: Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: () => context.read<AccountsNotifier>().linkAccount(),
                              child: const Text('Link a card'),
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
                  )
                else
                  _YourCardsSection(
                    notifier: notifier,
                    expandedIds: _expandedIds,
                    onToggleCard: _toggleCard,
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
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.charcoal),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }
}

class _YourCardsSection extends StatelessWidget {
  const _YourCardsSection({
    required this.notifier,
    required this.expandedIds,
    required this.onToggleCard,
  });

  final WalletNotifier notifier;
  final Set<String> expandedIds;
  final ValueChanged<String> onToggleCard;

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
  });

  final WalletNotifier notifier;
  final ValueChanged<WalletCard> onCardTap;

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: _carouselItemHeight,
            child: PageView.builder(
              itemCount: cards.length,
              itemBuilder: (_, index) {
                final card = cards[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: WalletCardPanel(
                        card: card,
                        mode: WalletCardPanelMode.collapsed,
                        onTap: () => onCardTap(card),
                      ),
                    ),
                  ),
                );
              },
            ),
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
          body: 'Cards owned by others in your household will appear here once household accounts are connected.',
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
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.charcoal),
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
const double _carouselItemHeight = 230;
