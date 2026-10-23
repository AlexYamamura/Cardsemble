import 'package:flutter/material.dart';
import 'package:cardsemble/core/utils/currency.dart';
import 'package:cardsemble/core/utils/date_utils.dart';
import 'package:cardsemble/theme/app_colors.dart';
import 'package:cardsemble/features/wallet/domain/wallet_card.dart';
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
/// accent color), issuer/network/last-four, balance and utilization. Tapping
/// the entire card drops down a details panel with the annual fee, foreign
/// transaction fee, benefits and travel perks — replacing the previous
/// "Update spend" button and "Statement Credits" dropdown.
class WalletCardPanel extends StatelessWidget {
  const WalletCardPanel({
    super.key,
    required this.card,
    this.mode = WalletCardPanelMode.expandable,
    this.expanded = false,
    this.onTap,
    this.onResync,
  });

  final WalletCard card;
  final WalletCardPanelMode mode;
  final bool expanded;
  final VoidCallback? onTap;
  final VoidCallback? onResync;

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
            // Wrap the body in a scrollable column so cards with full data
            // (balance, utilization, progress bar) never overflow the fixed
            // carousel height.
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  const Divider(height: 1),
                  _MonthlyInfo(card: card, color: color),
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
                    fontSize: 17,
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
      style: const TextStyle(fontSize: 13, color: Colors.white70),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _MonthlyInfo extends StatelessWidget {
  const _MonthlyInfo({required this.card, required this.color});

  final WalletCard card;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  label: 'Balance',
                  value: card.hasBalance
                      ? formatCurrency(card.balanceCents! / 100, card.currency ?? 'USD')
                      : '—',
                  color: color,
                ),
              ),
              Expanded(
                child: _MetricTile(
                  label: 'Utilization',
                  value: card.hasCreditLimit
                      ? '${(card.utilization! * 100).round()}%'
                      : '—',
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  label: 'Payment due',
                  value: card.hasPaymentDue
                      ? formatShortDate(card.paymentDueDate!)
                      : '—',
                  color: color,
                ),
              ),
              Expanded(
                child: _AutopayTile(card: card, color: color),
              ),
            ],
          ),
          if (card.hasCreditLimit) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: card.utilization,
                minHeight: 6,
                backgroundColor: AppColors.outlineVariant,
                color: color,
              ),
            ),
          ],
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
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// Autopay status tile: an 8px colored dot (green when on, grey otherwise)
/// followed by "On", "Off", or "—" when the backend has not reported a state.
class _AutopayTile extends StatelessWidget {
  const _AutopayTile({required this.card, required this.color});

  final WalletCard card;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final enabled = card.autopayEnabled;
    final active = enabled == true;
    final dotColor = active ? AppColors.success : AppColors.greyDisabled;
    final value = switch (enabled) {
      true => 'On',
      false => 'Off',
      null => '—',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Autopay',
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: active ? color : dotColor,
              ),
            ),
          ],
        ),
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
