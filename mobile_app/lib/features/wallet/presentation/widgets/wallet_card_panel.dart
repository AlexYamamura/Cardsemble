import 'package:flutter/material.dart';
import 'package:cardsemble/core/utils/currency.dart';
import 'package:cardsemble/theme/app_colors.dart';
import 'package:cardsemble/features/wallet/domain/wallet_card.dart';

/// A panel/tile for one wallet card.
///
/// Shows the card name and issuing network, the current-month balance and
/// utilization (placeholders until per-account balances are served by the
/// backend), a dropdown of catalog benefits with usage state, and a welcome
/// bonus progress bar when the catalog defines one.
class WalletCardPanel extends StatelessWidget {
  const WalletCardPanel({
    super.key,
    required this.card,
    required this.onToggleBenefit,
    required this.onSetBonusSpend,
    this.onViewDetails,
  });

  final WalletCard card;
  final ValueChanged<WalletBenefit> onToggleBenefit;
  final ValueChanged<int> onSetBonusSpend;
  final VoidCallback? onViewDetails;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onViewDetails,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _CardName(card: card),
              const SizedBox(height: 8),
              _CardSubtitle(card: card),
              if (!card.isCatalogMatched) _CatalogMatchTag(card: card),
              const Divider(height: 24),
              _MonthlyInfo(card: card),
              const SizedBox(height: 12),
              if (card.benefits.isNotEmpty) ...[
                _BenefitsDropdown(
                  card: card,
                  onToggleBenefit: onToggleBenefit,
                ),
                const SizedBox(height: 12),
              ],
              if (card.welcomeBonus != null) ...[
                _WelcomeBonusProgress(
                  bonus: card.welcomeBonus!,
                  onSetSpend: onSetBonusSpend,
                ),
                const SizedBox(height: 12),
              ],
              if (onViewDetails != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: onViewDetails,
                    child: const Text('View details'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardName extends StatelessWidget {
  const _CardName({required this.card});

  final WalletCard card;

  @override
  Widget build(BuildContext context) {
    return Text(
      card.displayName,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.charcoal,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
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
      style: const TextStyle(fontSize: 13, color: Colors.grey),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Tag shown on cards that did not match a `card_catalog` row.
class _CatalogMatchTag extends StatelessWidget {
  const _CatalogMatchTag({required this.card});

  final WalletCard card;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 10, color: AppColors.error),
          const SizedBox(width: 6),
          const Text(
            'Not available for benefit checks',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.error,
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthlyInfo extends StatelessWidget {
  const _MonthlyInfo({required this.card});

  final WalletCard card;

  @override
  Widget build(BuildContext context) {
    return Column(
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
              ),
            ),
            Expanded(
              child: _MetricTile(
                label: 'Utilization',
                value: card.hasCreditLimit
                    ? '${(card.utilization! * 100).round()}%'
                    : '—',
              ),
            ),
          ],
        ),
        if (card.hasCreditLimit) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: card.utilization,
              minHeight: 6,
              backgroundColor: AppColors.outlineVariant,
              color: AppColors.primary,
            ),
          ),
        ],
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

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
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.charcoal,
          ),
        ),
      ],
    );
  }
}

/// A compact dropdown of the card's catalog benefits, each marked used or
/// available. Tapping a benefit toggles its usage state.
class _BenefitsDropdown extends StatefulWidget {
  const _BenefitsDropdown({
    required this.card,
    required this.onToggleBenefit,
  });

  final WalletCard card;
  final ValueChanged<WalletBenefit> onToggleBenefit;

  @override
  State<_BenefitsDropdown> createState() => _BenefitsDropdownState();
}

class _BenefitsDropdownState extends State<_BenefitsDropdown> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final usedCount = widget.card.benefits.where((b) => b.used).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 6),
                const Text(
                  'Benefits',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.sand.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$usedCount / ${widget.card.benefits.length} used',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          for (final benefit in widget.card.benefits) ...[
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                benefit.used ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 20,
                color: benefit.used ? AppColors.primary : Colors.grey,
              ),
              title: Text(
                benefit.title,
                style: const TextStyle(fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: benefit.category != null
                  ? Text(
                      benefit.category!,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    )
                  : null,
              trailing: benefit.source != null
                  ? Text(
                      benefit.source!,
                      style: const TextStyle(fontSize: 10, color: AppColors.primary),
                    )
                  : null,
              onTap: () => widget.onToggleBenefit(benefit),
            ),
            if (benefit != widget.card.benefits.last)
              const Divider(height: 1),
          ],
        ],
      ],
    );
  }
}

/// Welcome bonus progress bar for a card currently earning its signup bonus.
class _WelcomeBonusProgress extends StatelessWidget {
  const _WelcomeBonusProgress({
    required this.bonus,
    required this.onSetSpend,
  });

  final WalletBonus bonus;
  final ValueChanged<int> onSetSpend;

  @override
  Widget build(BuildContext context) {
    final spent = bonus.spentUnits;
    final required = bonus.spendRequiredUnits;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Welcome bonus',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            Text(
              '${(bonus.progress * 100).round()}%',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: bonus.progress,
            minHeight: 6,
            backgroundColor: AppColors.outlineVariant,
            color: bonus.isComplete ? AppColors.success : AppColors.primary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          bonus.isComplete
              ? 'Bonus earned'
              : '$spent of $required spent toward the ${bonus.amountUnits} bonus',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => _promptSpend(context),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 8),
              side: BorderSide(color: AppColors.outlineVariant),
            ),
            child: const Text('Update spend'),
          ),
        ),
      ],
    );
  }

  Future<void> _promptSpend(BuildContext context) async {
    final controller = TextEditingController(text: spent.toString());
    final saved = await showDialog<int?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Update bonus spend'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Spend toward bonus',
            helperText: bonus.spendCurrency != null
                ? 'in ${bonus.spendCurrency}'
                : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text.trim());
              if (value == null || value < 0) return;
              Navigator.pop(dialogContext, value);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != null) onSetSpend(saved);
  }

  int get spent => bonus.spentUnits;
}
