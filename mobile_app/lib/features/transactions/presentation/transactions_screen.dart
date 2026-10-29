import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cardsemble/core/error/failure.dart';
import 'package:cardsemble/core/widgets/settings_gear_menu.dart';
import 'package:cardsemble/core/utils/date_utils.dart';
import 'package:cardsemble/theme/app_colors.dart';
import 'package:cardsemble/features/transactions/presentation/transactions_notifier.dart';
import 'package:cardsemble/features/transactions/presentation/widgets/pay_action_sheet.dart';
import 'package:cardsemble/features/transactions/domain/transactions_domain.dart';
import 'package:cardsemble/features/transactions/domain/split_math.dart';
import 'package:cardsemble/features/transactions/presentation/widgets/unified_split_slider.dart';
import 'package:cardsemble/features/household/domain/household_domain.dart';
import 'package:cardsemble/features/accounts/domain/accounts_domain.dart';
import 'package:cardsemble/core/utils/currency.dart';

const _personPalette = [
  Color(0xFF176B5B),
  Color(0xFF4F46A5),
  Color(0xFFC2415D),
  Color(0xFF146A8A),
  Color(0xFF8A4E9B),
  Color(0xFF966000),
];

Color _personColor(String personId, List<HouseholdPerson> people) {
  final index = people.indexWhere((person) => person.id == personId);
  if (index < 0) return _personPalette.first;
  return _personPalette[index % _personPalette.length];
}

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({
    super.key,
    this.onOpenSettings,
    this.onOpenCardEvents,
    this.onOpenManageHousehold,
  });

  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenCardEvents;
  final VoidCallback? onOpenManageHousehold;

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      context.read<TransactionsNotifier>().loadMoreTransactions();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: () => _refresh(context),
            tooltip: 'Refresh',
          ),
          SettingsGearMenu(
            onOpenSettings: widget.onOpenSettings,
            onOpenCardEvents: widget.onOpenCardEvents,
            onOpenManageHousehold: widget.onOpenManageHousehold,
          ),
        ],
      ),
      body: Consumer<TransactionsNotifier>(
        builder: (context, notifier, _) {
          final displayTransactions = notifier.filteredTransactions;
          if (notifier.isLoading && displayTransactions.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          return RefreshIndicator(
            onRefresh: () => _refresh(context),
            child: Column(
              children: [
                if (notifier.filteredTotal > 0 || notifier.hasActiveFilters)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Row(
                      children: [
                        if (notifier.filteredTotal > 0)
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 260),
                            child: PayButton(),
                          ),
                        if (notifier.hasActiveFilters) ...[
                          const Spacer(),
                          TextButton.icon(
                            onPressed: notifier.clearAllFilters,
                            icon: const Icon(Icons.clear_all, size: 16),
                            label: const Text('Clear all'),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                if (notifier.error != null)
                  _ErrorBanner(
                    message: notifier.error!,
                    onRetry: () => _refresh(context),
                    onDismiss: notifier.clearError,
                  ),
                Expanded(
                  child: _buildScrollableList(
                    context,
                    notifier,
                    displayTransactions,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildScrollableList(
    BuildContext context,
    TransactionsNotifier notifier,
    List<CardTransaction> displayTransactions,
  ) {
    final filterHeader = SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _TransactionFilterBar(
          accounts: notifier.accounts,
          people: notifier.people,
          selectedAccountId: notifier.selectedAccountId,
          selectedPersonId: notifier.selectedPersonId,
          selectedDateRange: notifier.dateRange,
          onAccountChanged: notifier.setAccountFilter,
          onPersonChanged: notifier.setPersonFilter,
          onDateRangeChanged: notifier.setDateRange,
          onClearAll: notifier.clearAllFilters,
          hasActiveFilters: notifier.hasActiveFilters,
          onRemoveAccount: () => notifier.setAccountFilter(null),
          onRemovePerson: () => notifier.setPersonFilter(null),
          onRemoveDateRange: notifier.clearDateRange,
        ),
      ),
    );

            if (displayTransactions.isEmpty) {
              return CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  filterHeader,
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 72),
                        _EmptyState(
                          hasFilters: notifier.hasActiveFilters,
                          hasAnyTransactions: notifier.transactions.isNotEmpty,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }

    final itemCount = displayTransactions.length + (notifier.hasMore ? 1 : 0);
    return CustomScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        filterHeader,
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              if (index >= displayTransactions.length) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final tx = displayTransactions[index];
              final hidden = notifier.isTransactionHidden(tx.id);
              return _TransactionTile(
                transaction: tx,
                people: notifier.people,
                hidden: hidden,
                onLongPress: () => notifier.toggleTransactionHidden(tx.id),
                onAssign: (personId) =>
                    _runAssignment(context, notifier, tx, personId),
                onSplit: (splits) => _runSplit(context, notifier, tx, splits),
                onToggleHouseholdVisible: (visible) =>
                    _runVisibility(context, notifier, tx, visible),
              );
            }, childCount: itemCount),
          ),
        ),
      ],
    );
  }

  Future<bool> _runAssignment(
    BuildContext context,
    TransactionsNotifier notifier,
    CardTransaction tx,
    String? personId,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await notifier.assignTransaction(tx.id, personId);
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(notifier.error ?? 'Could not update assignment'),
        ),
      );
    }
    return ok;
  }

   Future<bool> _runSplit(
     BuildContext context,
     TransactionsNotifier notifier,
     CardTransaction tx,
     List<TransactionSplit> splits,
   ) async {
     final messenger = ScaffoldMessenger.of(context);
     try {
       final totalAmount = tx.amountValue.abs();
        final participantIds =
            notifier.people.take(4).map((p) => p.id).toList();
       final percentages = percentagesFromExistingSplits(
         splits,
         totalAmount,
         allPersonIds: participantIds,
       );
       final ok = await notifier.saveTransactionSplit(
         transactionId: tx.id,
         totalAmount: totalAmount,
         percentages: percentages,
         orderedPersonIds: participantIds,
       );
       if (!ok) {
         messenger.showSnackBar(
           SnackBar(content: Text(notifier.error ?? 'Could not save the split')),
         );
       }
       return ok;
     } catch (e) {
       messenger.showSnackBar(
         SnackBar(content: Text('Error processing split: $e')),
       );
       return false;
     }
   }

  Future<bool> _runVisibility(
    BuildContext context,
    TransactionsNotifier notifier,
    CardTransaction tx,
    bool visible,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await notifier.setHouseholdVisible(tx.id, visible);
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(notifier.error ?? 'Could not update visibility'),
        ),
      );
    }
    return ok;
  }

  Future<void> _refresh(BuildContext context) async {
    await context.read<TransactionsNotifier>().loadAll();
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.message,
    required this.onRetry,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        child: Row(
          children: [
            Icon(
              Icons.error_outline,
              color: theme.colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
            IconButton(
              tooltip: 'Dismiss',
              onPressed: onDismiss,
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.hasFilters,
    required this.hasAnyTransactions,
  });

  final bool hasFilters;
  final bool hasAnyTransactions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = hasFilters
        ? Icons.filter_alt_off_outlined
        : (hasAnyTransactions
              ? Icons.receipt_long_outlined
              : Icons.credit_card_outlined);
    final title = hasFilters
        ? 'No transactions match these filters'
        : (hasAnyTransactions
              ? 'No transactions to show'
              : 'No transactions yet');
    final message = hasFilters
        ? 'Try clearing a filter or widening the date range.'
        : (hasAnyTransactions
              ? 'Pull down to refresh.'
              : 'Sync a card to see transactions here.');

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _TransactionFilterBar extends StatelessWidget {
  const _TransactionFilterBar({
    required this.accounts,
    required this.people,
    required this.selectedAccountId,
    required this.selectedPersonId,
    required this.selectedDateRange,
    required this.onAccountChanged,
    required this.onPersonChanged,
    required this.onDateRangeChanged,
    required this.onClearAll,
    required this.hasActiveFilters,
    this.onRemoveAccount,
    this.onRemovePerson,
    this.onRemoveDateRange,
  });

  final List<StatementAccount> accounts;
  final List<HouseholdPerson> people;
  final String? selectedAccountId;
  final String? selectedPersonId;
  final DateTimeRange? selectedDateRange;
  final ValueChanged<String?> onAccountChanged;
  final ValueChanged<String?> onPersonChanged;
  final ValueChanged<DateTimeRange?> onDateRangeChanged;
  final VoidCallback onClearAll;
  final bool hasActiveFilters;
  final VoidCallback? onRemoveAccount;
  final VoidCallback? onRemovePerson;
  final VoidCallback? onRemoveDateRange;

  List<DateTime> get _quickMonths {
    final today = DateTime.now();
    return List<DateTime>.generate(
      12,
      (index) => DateTime(today.year, today.month - index, 1),
    );
  }

  String _monthLabel(DateTime value) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return "${months[value.month - 1]} '${value.year.toString().substring(2)}";
  }

  Future<void> _showDateRangeMenu(BuildContext context) async {
    final theme = Theme.of(context);
    final picked = await showModalBottomSheet<DateTimeRange?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewPadding.bottom,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outline.withValues(alpha: 100),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    Text(
                      'Date range',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Quick select', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _quickMonths.map((month) {
                        final isSelected =
                            selectedDateRange != null &&
                            selectedDateRange!.start.year == month.year &&
                            selectedDateRange!.start.month == month.month;
                        final monthEnd = DateTime(
                          month.year,
                          month.month + 1,
                          0,
                        );
                        final today = DateUtils.dateOnly(DateTime.now());
                        final range = DateTimeRange(
                          start: month,
                          end: monthEnd.isAfter(today) ? today : monthEnd,
                        );
                        return FilterChip(
                          label: Text(_monthLabel(month)),
                          selected: isSelected,
                          onSelected: (_) => Navigator.pop(context, range),
                          visualDensity: VisualDensity.compact,
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              onDateRangeChanged(monthRange(DateTime.now()));
                              Navigator.pop(context);
                            },
                            child: const Text('This month'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () async {
                              final navigator = Navigator.of(context);
                              final picked = await showDateRangePicker(
                                context: context,
                                firstDate: DateTime(2000),
                                lastDate: DateTime.now(),
                                initialDateRange: selectedDateRange,
                                builder: (context, child) => Theme(
                                  data: Theme.of(context).copyWith(
                                    colorScheme: Theme.of(context).colorScheme
                                        .copyWith(primary: AppColors.primary),
                                  ),
                                  child: child!,
                                ),
                              );
                              if (picked != null) {
                                navigator.pop(
                                  DateTimeRange(
                                    start: DateUtils.dateOnly(picked.start),
                                    end: DateUtils.dateOnly(picked.end),
                                  ),
                                );
                              }
                            },
                            child: const Text('Custom range'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) onDateRangeChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Horizontal scroll container for filter dropdowns
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _FilterMenuButton(
                label: 'Credit card',
                selectedValue: selectedAccountId,
                items: [
                  const _FilterMenuItem(value: null, label: 'All cards'),
                  ...accounts.map(
                    (a) => _FilterMenuItem(
                      value: a.accountId,
                      label: a.displayName ?? a.accountName,
                    ),
                  ),
                ],
                onChanged: onAccountChanged,
              ),
              const SizedBox(width: 8),
              _FilterMenuButton(
                label: 'Assigned to',
                selectedValue: selectedPersonId,
                items: [
                  const _FilterMenuItem(value: null, label: 'Everyone'),
                  ...people.map(
                    (p) => _FilterMenuItem(value: p.id, label: p.displayName),
                  ),
                ],
                onChanged: onPersonChanged,
              ),
              const SizedBox(width: 8),
              _DateRangeFilterButton(
                label: 'Date range',
                selectedRange: selectedDateRange,
                onChanged: onDateRangeChanged,
                onPressed: () => _showDateRangeMenu(context),
              ),
            ],
          ),
        ),
        if (hasActiveFilters)
          _ActiveFilterChipsCard(
            selectedAccountId: selectedAccountId,
            selectedPersonId: selectedPersonId,
            selectedDateRange: selectedDateRange,
            accounts: accounts,
            people: people,
            onRemoveAccount: onRemoveAccount ?? () {},
            onRemovePerson: onRemovePerson ?? () {},
            onRemoveDateRange: onRemoveDateRange ?? () {},
          ),
      ],
    );
  }
}

/// Active filter chips rendered underneath the filter bubbles,
/// showing each currently selected filter with a remove affordance.
class _ActiveFilterChipsCard extends StatelessWidget {
  const _ActiveFilterChipsCard({
    required this.selectedAccountId,
    required this.selectedPersonId,
    required this.selectedDateRange,
    required this.accounts,
    required this.people,
    required this.onRemoveAccount,
    required this.onRemovePerson,
    required this.onRemoveDateRange,
  });

  final String? selectedAccountId;
  final String? selectedPersonId;
  final DateTimeRange? selectedDateRange;
  final List<StatementAccount> accounts;
  final List<HouseholdPerson> people;
  final VoidCallback onRemoveAccount;
  final VoidCallback onRemovePerson;
  final VoidCallback onRemoveDateRange;

  @override
  Widget build(BuildContext context) {
    final selectedAccount = accounts
        .where((a) => a.accountId == selectedAccountId)
        .firstOrNull;
    final selectedPerson = people
        .where((p) => p.id == selectedPersonId)
        .firstOrNull;

    final chips = <Widget>[];
    if (selectedAccountId != null) {
      chips.add(
        _FilterChip(
          label: selectedAccount?.accountName ?? 'Card',
          onRemove: onRemoveAccount,
        ),
      );
    }
    if (selectedPersonId != null) {
      chips.add(
        _FilterChip(
          label: selectedPerson?.displayName ?? 'Person',
          onRemove: onRemovePerson,
        ),
      );
    }
    if (selectedDateRange != null) {
      chips.add(
        _FilterChip(
          label: _rangeLabel(selectedDateRange!),
          onRemove: onRemoveDateRange,
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
      child: Wrap(spacing: 8, runSpacing: 8, children: chips),
    );
  }
}

String _rangeLabel(DateTimeRange range) {
  return '${_shortDate(range.start)} – ${_shortDate(range.end)}';
}

String _shortDate(DateTime value) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[value.month - 1]} ${value.day}, ${value.year}';
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxChipWidth = MediaQuery.of(context).size.width * 0.3;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxChipWidth),
      child: InputChip(
        label: Text(
          label,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        deleteIcon: const Icon(Icons.close, size: 16),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        onDeleted: onRemove,
        deleteButtonTooltipMessage: 'Clear filter',
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: BorderSide(color: theme.colorScheme.outline.withAlpha(100)),
        backgroundColor: theme.colorScheme.surfaceContainerHighest.withAlpha(
          50,
        ),
        deleteIconColor: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}


// Sentinel value used by filter menu buttons so the "All" / "Everyone" /
// reset option is a real, non-null `PopupMenuItem` value. `null` is treated
// as a menu cancel by `PopupMenuButton.showButtonMenu` and never reaches
// `onSelected`, so a non-null improbable constant is used instead.
const String _kAllFilter = '__cardsemble_all__';

class _FilterMenuButton extends StatelessWidget {
  const _FilterMenuButton({
    required this.label,
    required this.selectedValue,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final String? selectedValue;
  final List<_FilterMenuItem> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopupMenuButton<String>(
      initialValue: selectedValue ?? _kAllFilter,
      onSelected: (value) => onChanged(value == _kAllFilter ? null : value),
      itemBuilder: (context) => items
          .map(
            (item) => PopupMenuItem<String>(
              value: item.value ?? _kAllFilter,
              child: Text(item.label),
            ),
          )
          .toList(),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selectedValue != null
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
            ),
            color: Colors.white,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: selectedValue != null
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_drop_down,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterMenuItem {
  const _FilterMenuItem({required this.value, required this.label});
  final String? value;
  final String label;
}

class _DateRangeFilterButton extends StatelessWidget {
  const _DateRangeFilterButton({
    required this.label,
    required this.selectedRange,
    required this.onChanged,
    required this.onPressed,
  });

  final String label;
  final DateTimeRange? selectedRange;
  final ValueChanged<DateTimeRange?> onChanged;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        side: BorderSide(
          color: selectedRange != null
              ? theme.colorScheme.primary
              : theme.colorScheme.outline,
        ),
        backgroundColor: Colors.white,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: selectedRange != null
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.arrow_drop_down,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}



class _TransactionTile extends StatelessWidget {
  const _TransactionTile({
    required this.transaction,
    required this.people,
    required this.onAssign,
    required this.onSplit,
    required this.onToggleHouseholdVisible,
    this.hidden = false,
    this.onLongPress,
  });

  final CardTransaction transaction;
  final List<HouseholdPerson> people;
  final Future<bool> Function(String?) onAssign;
  final Future<bool> Function(List<TransactionSplit>) onSplit;
  final Future<bool> Function(bool) onToggleHouseholdVisible;

  /// Whether this row is hidden (long-pressed): greyed out and excluded from
  /// the Pay total, but still visible in the list.
  final bool hidden;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
     final assignedPerson = people.firstWhere(
        (p) => p.id == transaction.assignedPersonId,
        orElse: () =>
            HouseholdPerson(id: '', displayName: 'Unassigned', isDefault: false),
      );

     final assigneeColor = transaction.assignedPersonId == null
        ? theme.colorScheme.primary
        : _personColor(transaction.assignedPersonId!, people);

      final String label = transaction.hasSplits ? 'Split' : assignedPerson.displayName;

      final statusColor = transaction.pending
          ? AppColors.pendingBg
           : AppColors.sageGreen;

      // Hidden rows are greyed out to signal a disabled/dismissed state.
      final Color cardColor = hidden ? Colors.grey.shade100 : Colors.white;
      final Color mutedText = Colors.grey.shade600;

      return Card(
       color: cardColor,
       margin: const EdgeInsets.only(bottom: 8),
       child: GestureDetector(
         onLongPress: onLongPress,
         child: ExpansionTile(
         leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  transaction.parsedDate != null
                      ? DateFormat('MMM').format(transaction.parsedDate!)
                      : '??',
                  style: TextStyle(
                    color: hidden ? mutedText : Colors.black87,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  transaction.parsedDate != null
                      ? DateFormat('d').format(transaction.parsedDate!)
                      : '',
                  style: TextStyle(
                    color: hidden ? mutedText : Colors.black87,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Title shows the merchant when known, otherwise the transaction name.
          title: Text(
            transaction.merchant ?? transaction.name,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w400,
              fontSize: 20,
              color: hidden ? mutedText : null,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        // Assignee selector lives in the main row's subtitle: tappable,
        // indented and "raised" to signal interactivity. Keeping it out of
        // `trailing` means the fixed-size amount chip can remain the only
        // trailing child, so ListTile's "trailing consumes the entire tile
        // width" contract always holds.
          subtitle: Align(
            alignment: Alignment.centerLeft,
             child: InkWell(
               onTap: () {
                 final notifier = context.read<TransactionsNotifier>();
                 final DateTime? lastUpdated = notifier.lastUpdated;
                 final String updatedText = lastUpdated != null
                     ? DateFormat.yMMMd().format(lastUpdated)
                     : '';
                 final String byWho = transaction.assignmentSource;
                 showModalBottomSheet(
                   context: context,
                   isScrollControlled: true,
                   backgroundColor: Colors.transparent,
                   builder: (_) => Container(
                     decoration: BoxDecoration(
                       color: Theme.of(context).colorScheme.surface,
                       borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                     ),
                     child: SafeArea(
                       child: Column(
                         mainAxisSize: MainAxisSize.min,
                         children: [
                           Padding(
                             padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                             child: Row(
                               children: [
                                 Expanded(
                                   child: Text(
                                     label,
                                     style: theme.textTheme.titleLarge?.copyWith(
                                       fontWeight: FontWeight.w700,
                                     ),
                                   ),
                                 ),
                                 IconButton(
                                   tooltip: 'Close',
                                   onPressed: () => Navigator.pop(context),
                                   icon: const Icon(Icons.close_rounded),
                                 ),
                               ],
                             ),
                           ),
                           const Divider(height: 1),
                           Padding(
                             padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                             child: Column(
                               crossAxisAlignment: CrossAxisAlignment.start,
                               children: [
                                 Text(
                                   'Last updated: $updatedText',
                                   style: theme.textTheme.bodyMedium,
                                 ),
                                 const SizedBox(height: 4),
                                 Text(
                                   'Edited by: $byWho',
                                   style: theme.textTheme.bodyMedium,
                                 ),
                               ],
                             ),
                           ),
                           const Divider(height: 1),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                              child: SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                value: !transaction.householdVisible,
                                onChanged: (value) => onToggleHouseholdVisible(!value),
                                title: const Text('Hide from household members'),
                                subtitle: const Text('Not shared with other household members'),
                              ),
                            ),
                         ],
                       ),
                     ),
                   ),
                 );
               },
               borderRadius: BorderRadius.circular(8),
               child: Container(
                 margin: const EdgeInsets.only(top: 4),
                 padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                 decoration: BoxDecoration(
                   color: assigneeColor.withValues(alpha: 24 / 255),
                   borderRadius: BorderRadius.circular(8),
                   border: Border.all(
                     color: assigneeColor.withValues(alpha: 150 / 255),
                     width: 1,
                   ),
                   boxShadow: [
                     BoxShadow(
                       color: Colors.black.withValues(alpha: 0.08),
                       blurRadius: 2,
                       offset: const Offset(0, 1),
                     ),
                   ],
                 ),
                 child: Text(
                   label,
                   style: theme.textTheme.bodySmall?.copyWith(
                     color: assigneeColor,
                     fontWeight: FontWeight.w600,
                   ),
                 ),
               ),
             ),
          ),
        // Fixed-size amount chip only, so the ListTile trailing contract holds.
        trailing: _TransactionAmountChip(
          amount: formatCurrency(
            transaction.amountValue,
            transaction.currency,
          ),
          pending: transaction.pending,
          hidden: hidden,
        ),
         children: [
           Padding(
             padding: const EdgeInsets.all(16),
             child: Column(
               crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    transaction.name,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w400,
                      fontSize: 20,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                 const SizedBox(height: 8),
                 if (people.length > 1) ...[
                    _SplitSection(
                      transaction: transaction,
                      people: people,
                      onSplit: onSplit,
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

/// Slightly rounded rectangle chip showing the transaction amount in the
/// tile's trailing area. Color matches the pending/approved state of the box.
class _TransactionAmountChip extends StatelessWidget {
  const _TransactionAmountChip({required this.amount, required this.pending, this.hidden = false});

  final String amount;
  final bool pending;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final color = hidden
        ? Colors.grey.shade400
        : (pending ? Colors.orange.shade700 : AppColors.sageGreen);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        amount,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Loads a transaction's existing splits once, derives the initial percentage
/// allocation (backfilled for every displayed participant), and renders the
/// unified split slider. Fetching once here — rather than in the parent's
/// `build` — avoids re-hitting the network on every rebuild.
class _SplitSection extends StatefulWidget {
  const _SplitSection({
    required this.transaction,
    required this.people,
    required this.onSplit,
  });

  final CardTransaction transaction;
  final List<HouseholdPerson> people;
  final Future<bool> Function(List<TransactionSplit>) onSplit;

  @override
  State<_SplitSection> createState() => _SplitSectionState();
}

class _SplitSectionState extends State<_SplitSection> {
   late Future<Result<Map<String, double>>> _splitsFuture;

  @override
  void initState() {
    super.initState();
    final notifier = context.read<TransactionsNotifier>();
    final transaction = widget.transaction;
    final participants = widget.people.length > 4 ? widget.people.take(4).toList() : widget.people;
    final personIds = participants.map((p) => p.id).toList();
    _splitsFuture = notifier.loadSplitDraft(
      transactionId: transaction.id,
      totalAmount: transaction.amountValue.abs(),
      participantIds: personIds,
    );
  }

  void _retry() {
    setState(() {
      final notifier = context.read<TransactionsNotifier>();
      final transaction = widget.transaction;
      final participants = widget.people.length > 4 ? widget.people.take(4).toList() : widget.people;
      final personIds = participants.map((p) => p.id).toList();
      _splitsFuture = notifier.loadSplitDraft(
        transactionId: transaction.id,
        totalAmount: transaction.amountValue.abs(),
        participantIds: personIds,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // 2-4 participants; households larger than 4 default to the first 4.
    final List<HouseholdPerson> participants =
        widget.people.length > 4 ? widget.people.take(4).toList() : widget.people;
    if (participants.length < 2) {
      return const Text('Need at least 2 people to split');
    }

    final List<String> personIds = participants.map((p) => p.id).toList();

     return FutureBuilder<Result<Map<String, double>>>(
       future: _splitsFuture,
       builder: (context, snapshot) {
         if (snapshot.connectionState == ConnectionState.waiting) {
           return const Center(child: CircularProgressIndicator());
         }
         if (snapshot.hasError) {
           return Center(
             child: Column(
               mainAxisSize: MainAxisSize.min,
               children: [
                 Text(
                   'Failed to load split data: ${snapshot.error}',
                   style: Theme.of(context).textTheme.bodySmall?.copyWith(
                     color: Theme.of(context).colorScheme.error,
                   ),
                 ),
                 const SizedBox(height: 8),
                 ElevatedButton(
                   onPressed: _retry,
                   child: const Text('Retry'),
                 ),
               ],
             ),
           );
         }
         final result = snapshot.data;
         if (result == null) {
           return const Center(child: CircularProgressIndicator());
         }

         return result.fold(
           (percentages) {
             final finalPercentages = percentages.isEmpty
                 ? equalSplitPercentages(personIds)
                 : percentages;

             return _UnifiedSplitSliderBuilder(
               transaction: widget.transaction,
               people: participants,
               initialPercentages: finalPercentages,
               onSplit: widget.onSplit,
             );
           },
           (failure) => Center(
             child: Column(
               mainAxisSize: MainAxisSize.min,
               children: [
                 Text(
                   'Failed to load split data: ${failure.message}',
                   style: Theme.of(context).textTheme.bodySmall?.copyWith(
                     color: Theme.of(context).colorScheme.error,
                   ),
                 ),
                 const SizedBox(height: 8),
                 ElevatedButton(
                   onPressed: _retry,
                   child: const Text('Retry'),
                 ),
               ],
             ),
           ),
         );
       },
     );
  }
}

class _UnifiedSplitSliderBuilder extends StatefulWidget {
  const _UnifiedSplitSliderBuilder({
    required this.transaction,
    required this.people,
    required this.initialPercentages,
    required this.onSplit,
  });

  final CardTransaction transaction;
  final List<HouseholdPerson> people;
  final Map<String, double> initialPercentages;
  final Future<bool> Function(List<TransactionSplit>) onSplit;

  @override
  State<_UnifiedSplitSliderBuilder> createState() =>
      _UnifiedSplitSliderBuilderState();
}

class _UnifiedSplitSliderBuilderState extends State<_UnifiedSplitSliderBuilder> {
  late Map<String, double> _percentages;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _percentages = Map<String, double>.from(widget.initialPercentages);
  }

  Future<void> _saveSplit() async {
    setState(() => _isLoading = true);
    try {
      final splits =
          percentagesToCents(widget.transaction.amountValue.abs(), _percentages,
              widget.people.map((p) => p.id).toList());
      // Failures are surfaced by the notifier via SnackBar in `_runSplit`.
      await widget.onSplit(splits);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Side-by-side participant names, each in its own flexible column.
        // Long names fade via overflow ellipsis so 3–4 columns always fit.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int index = 0; index < widget.people.length; index++) ...[
              if (index > 0) const SizedBox(width: 4),
              Expanded(
                child: _buildParticipantColumn(context, widget.people[index]),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        // The unified slider itself - shared across all participants
        SizedBox(
          height: 50,
          child: UnifiedSplitSlider(
            participants: widget.people
                .map((p) => ParticipantInfo(
                      id: p.id,
                      name: p.displayName,
                      color: _personColor(p.id, widget.people),
                    ))
                .toList(),
            percentages: _percentages,
            onChanged: (percentages) {
              setState(() {
                _percentages = Map<String, double>.from(percentages);
              });
            },
          ),
        ),
         const SizedBox(height: 24),
        // Cancel / Save actions
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 12,
          children: [
            FilledButton(
              onPressed: _isLoading ? null : _saveSplit,
              child: _isLoading
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save Split'),
            ),
            TextButton(
              onPressed: _isLoading
                  ? null
                  : () => ExpansibleController.maybeOf(context)?.collapse(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ],
    );
  }

  /// Builds a single participant's column for the side-by-side header row:
  /// name (truncated with ellipsis) above an enlarged price + percentage.
  Widget _buildParticipantColumn(
    BuildContext context,
    HouseholdPerson person,
  ) {
    final Color personColor = _personColor(person.id, widget.people);
    final double percentage = _percentages[person.id] ?? 0.0;
    final double amount =
        (percentage / 100.0) * widget.transaction.amountValue.abs();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
         // Person name with bold style, truncated when too long
         Text(
           person.displayName,
           key: ValueKey('split-name-${person.id}'),
           style: Theme.of(context).textTheme.titleLarge?.copyWith(
                 color: personColor,
                 fontWeight: FontWeight.w800,
                 fontSize: 18,
               ),
           maxLines: 1,
           overflow: TextOverflow.ellipsis,
         ),
        const SizedBox(height: 4),
        // Enlarged price alongside the percentage
        Text(
          formatCurrency(amount, widget.transaction.currency),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          '${percentage.toStringAsFixed(1)}%',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: personColor,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
        ),
      ],
    );
  }
}

class _PersonSelectorSheet extends StatefulWidget {
  const _PersonSelectorSheet({
    required this.title,
    required this.currentPersonId,
    required this.people,
    required this.onSelected,
  });

  final String title;
  final String? currentPersonId;
  final List<HouseholdPerson> people;
  final ValueChanged<String?> onSelected;

  @override
  State<_PersonSelectorSheet> createState() => _PersonSelectorSheetState();
}

class _PersonSelectorSheetState extends State<_PersonSelectorSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 30),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 5,
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outline.withValues(alpha: 100),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          widget.title,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          softWrap: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: widget.people.length + 1,
                    separatorBuilder: (context, index) =>
                        Divider(height: 1, indent: 56, endIndent: 16),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        final isSelected = widget.currentPersonId == null;
                        return _PersonSelectorTileItem(
                          person: null,
                          displayName: 'Household default',
                          isSelected: isSelected,
                          color: theme.colorScheme.primary,
                          onTap: () {
                            Navigator.pop(context);
                            widget.onSelected(null);
                          },
                        );
                      }
                      final person = widget.people[index - 1];
                      final isSelected = widget.currentPersonId == person.id;
                      return _PersonSelectorTileItem(
                        person: person,
                        displayName: person.displayName,
                        isSelected: isSelected,
                        color: _personColor(person.id, widget.people),
                        onTap: () {
                          Navigator.pop(context);
                          widget.onSelected(person.id);
                        },
                      );
                    },
                  ),
                ),
                SizedBox(height: MediaQuery.of(context).viewPadding.bottom + 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PersonSelectorTileItem extends StatelessWidget {
  const _PersonSelectorTileItem({
    required this.person,
    required this.displayName,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  final HouseholdPerson? person;
  final String displayName;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: isSelected ? color : color.withValues(alpha: 40),
              child: Text(
                displayName.isEmpty
                    ? '?'
                    : displayName.substring(0, 1).toUpperCase(),
                style: TextStyle(
                  color: isSelected ? Colors.white : color,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                displayName,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? color : theme.colorScheme.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded, color: color, size: 24),
          ],
        ),
      ),
    );
  }
}
