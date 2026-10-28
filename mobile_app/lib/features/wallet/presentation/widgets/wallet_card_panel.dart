import 'package:flutter/material.dart';
import 'package:cardsemble/core/utils/currency.dart';
import 'package:cardsemble/theme/app_colors.dart';
import 'package:cardsemble/features/wallet/domain/wallet_card.dart';
import 'package:cardsemble/features/wallet/domain/benefit_spending.dart';
import 'package:cardsemble/features/card_catalog/domain/entities/card_catalog_card.dart';
import 'package:cardsemble/features/wallet/presentation/wallet_card_colors.dart';

/// How a [WalletCardPanel] is presented.
///
/// [expandable] panels live in the vertical list layout and drop down a details
/// pane when tapped. [collapsed] panels live inside the horizontal carousel and
/// stay fixed-height; tapping them opens the details in a bottom sheet instead
/// (handled by the parent screen) so expanding cards don't overflow the row.
enum WalletCardPanelMode {
  expandable,
  collapsed,
}

/// A panel/tile for one wallet card.
///
/// The collapsed pane shows the card name (themed with a bank/card-derived
/// accent color), issuer/network/last-four, spending toward benefits, and an
/// expando of benefit usage progress bars. Tapping the entire card drops down a
/// details panel with the annual fee, foreign transaction fee, benefits and
/// travel perks — replacing the previous "Update spend" button and
/// "Statement Credits" dropdown.
class WalletCardPanel extends StatelessWidget {
  const WalletCardPanel({
    super.key,
    required this.card,
    this.mode = WalletCardPanelMode.expandable,
    this.expanded = false,
    this.onTap,
    this.onResync,
    this.benefitSpending,
    this.isTransactionsLoading = false,
  });

  final WalletCard card;
  final WalletCardPanelMode mode;
  final bool expanded;
  final VoidCallback? onTap;
  final VoidCallback? onResync;

  /// Spending toward this card's benefits, derived from the loaded transaction
  /// list. May be null when transactions haven't loaded or the card has no
  /// mappable benefit categories.
  final WalletBenefitSpending? benefitSpending;

  /// Whether the transaction list is still loading for the first time.
  final bool isTransactionsLoading;

  @override
  Widget build(BuildContext context) {
    final color = WalletCardColors.accentColor(card);
    final showToggle = mode == WalletCardPanelMode.expandable;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _CardHeader(
              card: card,
              color: color,
              expanded: expanded,
              showToggle: showToggle,
              onResync: onResync,
            ),
            ClipRect(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
              const Divider(height: 1),
              _MonthlyInfo(
                card: card,
                color: color,
                compact: mode == WalletCardPanelMode.collapsed,
                benefitSpending: benefitSpending,
                isTransactionsLoading: isTransactionsLoading,
              ),
                  if (card.catalogCard != null) ...[
                    const SizedBox(height: 12),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeInOut,
                      child: expanded && showToggle
                          ? CardDetails(card: card, color: color)
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.card,
    required this.color,
    required this.expanded,
    required this.showToggle,
    this.onResync,
  });

  final WalletCard card;
  final Color color;
  final bool expanded;
  final bool showToggle;
  final VoidCallback? onResync;

  @override
  Widget build(BuildContext context) {
    final onColor = WalletCardColors.onColor(color);
    final needsRelink = card.needsRelink;
    return Container(
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                card.displayName,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: onColor,
                ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (needsRelink && onResync != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    onTap: onResync,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: onColor.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.refresh, size: 18, color: Colors.white),
                    ),
                  ),
                ),
              if (showToggle)
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: onColor,
                ),
            ],
          ),
          const SizedBox(height: 4),
          _CardSubtitle(card: card),
          // In expandable mode, show the reconnection message and button below
          // the subtitle. In collapsed/carousel mode the circular refresh icon
          // in the header is sufficient and avoids overflow.
          if (needsRelink && showToggle) ...[
            const SizedBox(height: 6),
            Text(
              'Connection needs reconnection',
              style: TextStyle(
                fontSize: 12,
                color: onColor.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onResync,
                style: TextButton.styleFrom(
                  foregroundColor: onColor,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Fix connection', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CardSubtitle extends StatelessWidget {
  const _CardSubtitle({required this.card});

  final WalletCard card;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    final issuer = card.issuer;
    if (issuer != null && issuer.isNotEmpty) parts.add(issuer);
    final network = card.network;
    if (network != null && network.isNotEmpty) parts.add(network);
    if (card.lastFour != null) parts.add('• ${card.lastFour}');
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(
      parts.join('  ·  '),
      style: const TextStyle(fontSize: 14, color: Colors.white70),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Monthly/period info shown inside a card panel.
///
/// In compact mode (used inside the horizontal carousel) only the "Spending
/// toward benefits" metric is shown, keeping the card height bounded. In
/// expandable/list mode, the full benefit usage progress bars are also rendered.
class _MonthlyInfo extends StatelessWidget {
  const _MonthlyInfo({
    required this.card,
    required this.color,
    this.compact = false,
    this.benefitSpending,
    this.isTransactionsLoading = false,
  });

  final WalletCard card;
  final Color color;
  final bool compact;
  final WalletBenefitSpending? benefitSpending;
  final bool isTransactionsLoading;

  @override
  Widget build(BuildContext context) {
    final hasBenefits = card.benefits.isNotEmpty;

    // In compact mode, show only the spending-toward-benefits metric to keep
    // the carousel card height bounded. The full benefit progress bars are
    // shown in expandable/list mode and the details sheet.
    if (compact) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSpendingMetric(),
            if (hasBenefits) ...[
              const SizedBox(height: 8),
              _BenefitsUsedSummary(card: card),
            ],
          ],
        ),
      );
    }

    // Expandable/list mode: full benefit progress bars.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSpendingMetric(),
          if (hasBenefits) ...[
            const SizedBox(height: 14),
            ...card.benefits.map(
              (benefit) => _BenefitProgressTile(
                benefit: benefit,
                color: color,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSpendingMetric() {
    final spending = benefitSpending;
    final txCount = spending?.transactionCount ?? 0;
    final hasSpending = spending != null && txCount > 0;

    final value = isTransactionsLoading
        ? '—'
        : hasSpending
            ? formatCurrency(
                spending.totalAmountCents / 100,
                spending.amountCentsByCurrency.keys.first,
              )
            : '—';

    final subtitle = isTransactionsLoading
        ? 'Loading transactions…'
        : spending == null
            ? 'No benefits with spending categories'
            : hasSpending
                ? '$txCount matching ${txCount == 1 ? 'transaction' : 'transactions'} in the loaded period'
                : 'No matching transactions yet';

    return _MetricTile(
      label: 'Spending toward benefits',
      value: value,
      subtitle: subtitle,
      color: color,
    );
  }
}

/// A one-line summary of how many of a card's benefits have been marked used.
class _BenefitsUsedSummary extends StatelessWidget {
  const _BenefitsUsedSummary({required this.card});

  final WalletCard card;

  @override
  Widget build(BuildContext context) {
    final usedCount = card.benefits.where((b) => b.used).length;
    final totalCount = card.benefits.length;
    return Text(
      '$usedCount of $totalCount benefits used',
      style: const TextStyle(fontSize: 12, color: Colors.grey),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Renders a single [WalletBenefit] as a labelled horizontal progress bar.
///
/// The bar fills to 100% when the benefit has been used this period, and is
/// empty when it is still available. Dollar-amount credits use the benefit's
/// existing `amountLabel` (minor-unit `amount` + `currency`); non-dollar
/// benefits show a simple "Used"/"Available" label.
class _BenefitProgressTile extends StatelessWidget {
  const _BenefitProgressTile({
    required this.benefit,
    required this.color,
  });

  final WalletBenefit benefit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final used = benefit.used;
    final barColor = used ? color : color.withValues(alpha: 0.25);
    final value = benefit.amountLabel ?? (used ? 'Used' : 'Available');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  benefit.title,
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: used ? color : Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: used ? 1.0 : 0.0,
              minHeight: 6,
              backgroundColor: AppColors.outlineVariant,
              color: barColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.color,
    this.subtitle,
  });

  final String label;
  final String value;
  final Color color;
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
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: color,
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

/// Expanded details pane shown when a card is tapped.
///
/// Displays annual fee, foreign transaction fee, catalog benefits and travel
/// perks. Read-only reference data; benefit usage marking has moved out of this
/// panel.
class CardDetails extends StatelessWidget {
  const CardDetails({
    super.key,
    required this.card,
    required this.color,
    this.scrollable = false,
  });

  final WalletCard card;
  final Color color;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final catalog = card.catalogCard;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (catalog != null && catalog.annualFee?.amount != null) ...[
            _DetailRow(
              label: 'Annual fee',
              value: formatCurrency(
                catalog.annualFee!.amount!.toDouble(),
                catalog.annualFee!.currency ?? 'USD',
              ),
              color: color,
            ),
            const SizedBox(height: 10),
          ],
          if (catalog != null && catalog.fxFee?.percent != null) ...[
            _DetailRow(
              label: 'Foreign transaction fee',
              value: '${catalog.fxFee!.percent!.toStringAsFixed(2)}%',
              color: color,
            ),
            const SizedBox(height: 10),
          ],
          if (catalog != null && catalog.benefits.isNotEmpty) ...[
            const Text(
              'Benefits',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.charcoal,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: catalog.benefits
                  .map((benefit) => _BenefitChip(
                        title: benefit.title ?? 'Benefit',
                        description: benefit.description,
                        color: color,
                      ))
                  .toList(growable: false),
            ),
            const SizedBox(height: 10),
          ],
          if (catalog != null && catalog.travelPerks != null) ...[
            const Text(
              'Travel perks',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.charcoal,
              ),
            ),
            const SizedBox(height: 6),
            _TravelPerks(perks: catalog.travelPerks!, color: color),
            const SizedBox(height: 10),
          ],
          if (catalog == null) ...[
            const Text(
              'No catalog reference data available for this card.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
           ],
           ],
          ),
         );

      if (scrollable) {
       return Container(
         width: double.infinity,
         decoration: BoxDecoration(
           color: WalletCardColors.paneBackground(color),
           borderRadius: BorderRadius.circular(12),
         ),
         child: SingleChildScrollView(child: content),
       );
     }
     return content;
   }
 }

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.charcoal,
                ),
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  TextSpan(text: value),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TravelPerks extends StatelessWidget {
  const _TravelPerks({required this.perks, required this.color});

  final CardTravelPerks perks;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final items = <String>[];
    if (perks.loungeAccess != null) {
      items.add('Lounge access: ${_perkValue(perks.loungeAccess)}');
    }
    if (perks.tsaPrecheckCredit != null) {
      items.add('TSA Pre\u2713 credit: ${_perkValue(perks.tsaPrecheckCredit)}');
    }
    if (perks.globalEntryCredit != null) {
      items.add('Global Entry credit: ${_perkValue(perks.globalEntryCredit)}');
    }
    if (perks.freeCheckedBags != null) {
      items.add('Free checked bags: ${_perkValue(perks.freeCheckedBags)}');
    }
    if (perks.hotelStatus != null) {
      items.add('Hotel status: ${_perkValue(perks.hotelStatus)}');
    }
    items.addAll(perks.other);

    if (items.isEmpty) {
      return const Text(
        'None listed',
        style: TextStyle(fontSize: 13, color: Colors.grey),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: items
          .map((item) => _PerkChip(label: item, color: color))
          .toList(growable: false),
    );
  }

  String _perkValue(Object? value) {
    if (value == null) return '—';
    if (value is bool) return value ? 'Yes' : 'No';
    return value.toString();
  }
}

class _PerkChip extends StatelessWidget {
  const _PerkChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// One catalog benefit shown as a digestible chip: title followed by its
/// description, with no category label. Taps to expand/collapse long text.
class _BenefitChip extends StatefulWidget {
  const _BenefitChip({
    required this.title,
    required this.description,
    required this.color,
  });

  final String title;
  final String? description;
  final Color color;

  @override
  State<_BenefitChip> createState() => _BenefitChipState();
}

class _BenefitChipState extends State<_BenefitChip> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final hasDescription = (widget.description ?? '').isNotEmpty;
    final showToggle = hasDescription;
    return GestureDetector(
      onTap: showToggle ? () => setState(() => _expanded = !_expanded) : null,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: 0.10),
          border: Border.all(color: widget.color.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            RichText(
              maxLines: _expanded ? null : 2,
              overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.charcoal,
                  height: 1.25,
                ),
                children: [
                  TextSpan(
                    text: widget.title,
                    style: TextStyle(fontWeight: FontWeight.w700, color: widget.color),
                  ),
                  if (hasDescription) TextSpan(text: '  ${widget.description}'),
                ],
              ),
            ),
            if (showToggle)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _expanded ? 'Show less' : 'Show more',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: widget.color,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
