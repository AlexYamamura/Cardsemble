import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cardsemble/theme/app_colors.dart';
import 'package:cardsemble/features/transactions/presentation/transactions_notifier.dart';
import 'package:cardsemble/features/transactions/domain/transactions_domain.dart';
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
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final ScrollController _scrollController = ScrollController();

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
                _TransactionFilterBar(
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
                if (notifier.hasActiveFilters)
                  _ActiveFilterChipsCard(
                    selectedAccountId: notifier.selectedAccountId,
                    selectedPersonId: notifier.selectedPersonId,
                    selectedDateRange: notifier.dateRange,
                    accounts: notifier.accounts,
                    people: notifier.people,
                    onRemoveAccount: () => notifier.setAccountFilter(null),
                    onRemovePerson: () => notifier.setPersonFilter(null),
                    onRemoveDateRange: notifier.clearDateRange,
                  ),
                if (notifier.error != null)
                  _ErrorBanner(
                    message: notifier.error!,
                    onRetry: () => _refresh(context),
                    onDismiss: notifier.clearError,
                  ),
                Expanded(
                  child: _buildList(
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCsvImportDialog(context),
        icon: const Icon(Icons.upload_file),
        label: const Text('Import CSV'),
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    TransactionsNotifier notifier,
    List<CardTransaction> displayTransactions,
  ) {
    if (displayTransactions.isEmpty) {
      return ListView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 72),
          _EmptyState(
            hasFilters: notifier.hasActiveFilters,
            hasAnyTransactions: notifier.transactions.isNotEmpty,
          ),
        ],
      );
    }

    final itemCount = displayTransactions.length + (notifier.hasMore ? 1 : 0);
    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index >= displayTransactions.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final tx = displayTransactions[index];
        return _TransactionTile(
          transaction: tx,
          people: notifier.people,
          onAssign: (personId) => _runAssignment(context, notifier, tx, personId),
          onSplit: (splits) => _runSplit(context, notifier, tx, splits),
          onToggleHouseholdVisible: (visible) =>
              _runVisibility(context, notifier, tx, visible),
        );
      },
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
        SnackBar(content: Text(notifier.error ?? 'Could not update assignment')),
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
    final ok = await notifier.assignTransactionSplit(tx.id, splits);
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(content: Text(notifier.error ?? 'Could not save the split')),
      );
    }
    return ok;
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
        SnackBar(content: Text(notifier.error ?? 'Could not update visibility')),
      );
    }
    return ok;
  }

  Future<void> _refresh(BuildContext context) async {
    await context.read<TransactionsNotifier>().loadAll();
  }

  void _showCsvImportDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import CSV'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Paste CSV content',
                hintText: 'Date,Description,Amount,...',
              ),
              maxLines: 10,
            ),
            const SizedBox(height: 16),
            const Text('Select account and paste CSV to preview import'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
            },
            child: const Text('Preview'),
          ),
        ],
      ),
    );
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
            Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer),
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
        : (hasAnyTransactions ? 'No transactions to show' : 'No transactions yet');
    final message = hasFilters
        ? 'Try clearing a filter or widening the date range.'
        : (hasAnyTransactions
            ? 'Pull down to refresh.'
            : 'Sync a card or import a CSV to see transactions here.');

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
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
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
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewPadding.bottom),
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
                    Text('Date range', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
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
                        final isSelected = selectedDateRange != null &&
                            selectedDateRange!.start.year == month.year &&
                            selectedDateRange!.start.month == month.month;
                        final monthEnd = DateTime(month.year, month.month + 1, 0);
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
                               onDateRangeChanged(null);
                               Navigator.pop(context);
                             },
                             child: const Text('All time'),
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
                                    colorScheme: Theme.of(context).colorScheme.copyWith(
                                      primary: AppColors.primary,
                                    ),
                                  ),
                                  child: child!,
                                ),
                              );
                              if (picked != null) {
                                navigator.pop(DateTimeRange(
                                  start: DateUtils.dateOnly(picked.start),
                                  end: DateUtils.dateOnly(picked.end),
                                ));
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
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Filters', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                if (hasActiveFilters)
                  TextButton.icon(
                    onPressed: onClearAll,
                    icon: const Icon(Icons.clear_all, size: 16),
                    label: const Text('Clear all'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _FilterMenuButton(
                  label: 'Credit card',
                  selectedValue: selectedAccountId,
                  items: [
                    const _FilterMenuItem(value: null, label: 'All cards'),
                    ...accounts.map((a) => _FilterMenuItem(
                      value: a.accountId,
                      label: a.displayName ?? a.accountName,
                    )),
                  ],
                  onChanged: onAccountChanged,
                ),
                _FilterMenuButton(
                  label: 'Assigned to',
                  selectedValue: selectedPersonId,
                  items: [
                    const _FilterMenuItem(value: null, label: 'Everyone'),
                    ...people.map((p) => _FilterMenuItem(
                      value: p.id,
                      label: p.displayName,
                    )),
                  ],
                  onChanged: onPersonChanged,
                ),
                _DateRangeFilterButton(
                  label: 'Date range',
                  selectedRange: selectedDateRange,
                  onChanged: onDateRangeChanged,
                  onPressed: () => _showDateRangeMenu(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Active filter chips rendered in their own card underneath the filter panel,
/// rather than crammed inside the same container as the filter menu buttons.
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
    final selectedAccount = accounts.where((a) => a.accountId == selectedAccountId).firstOrNull;
    final selectedPerson = people.where((p) => p.id == selectedPersonId).firstOrNull;

    final chips = <Widget>[];
    if (selectedAccountId != null) {
      chips.add(_FilterChip(label: selectedAccount?.accountName ?? 'Card', onRemove: onRemoveAccount));
    }
    if (selectedPersonId != null) {
      chips.add(_FilterChip(label: selectedPerson?.displayName ?? 'Person', onRemove: onRemovePerson));
    }
    if (selectedDateRange != null) {
      chips.add(_FilterChip(label: _rangeLabel(selectedDateRange!), onRemove: onRemoveDateRange));
    }

    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: chips,
      ),
    );
  }
}

String _rangeLabel(DateTimeRange range) {
  return '${_shortDate(range.start)} – ${_shortDate(range.end)}';
}

String _shortDate(DateTime value) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[value.month - 1]} ${value.day}, ${value.year}';
}

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

    return PopupMenuButton<String?>(
      initialValue: selectedValue,
      onSelected: onChanged,
      itemBuilder: (context) => items.map((item) => PopupMenuItem<String?>(
        value: item.value,
        child: Text(item.label),
      )).toList(),
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
            color: selectedValue != null
                ? theme.colorScheme.primaryContainer.withValues(alpha: 50)
                : null,
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

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.onRemove,
  });

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InputChip(
      label: Text(label),
      deleteIcon: const Icon(Icons.close, size: 18),
      onDeleted: onRemove,
      deleteButtonTooltipMessage: 'Clear filter',
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      side: BorderSide(color: theme.colorScheme.outline.withAlpha(100)),
      backgroundColor: theme.colorScheme.surfaceContainerHighest.withAlpha(50),
      labelStyle: theme.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w500,
      ),
      deleteIconColor: theme.colorScheme.onSurfaceVariant,
    );
  }
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
        backgroundColor: selectedRange != null
            ? theme.colorScheme.primaryContainer.withValues(alpha: 50)
            : null,
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
  });

  final CardTransaction transaction;
  final List<HouseholdPerson> people;
  final Future<bool> Function(String?) onAssign;
  final Future<bool> Function(List<TransactionSplit>) onSplit;
  final Future<bool> Function(bool) onToggleHouseholdVisible;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final assignedPerson = people.firstWhere(
      (p) => p.id == transaction.assignedPersonId,
      orElse: () => HouseholdPerson(id: '', displayName: 'Unassigned', isDefault: false),
    );

    final assigneeColor = transaction.assignedPersonId == null
        ? theme.colorScheme.primary
        : _personColor(transaction.assignedPersonId!, people);

     final personName = assignedPerson.displayName.isEmpty ? 'Unassigned' : assignedPerson.displayName;
     final statusColor = transaction.pending ? AppColors.pendingBg : AppColors.sageGreen;

    void openPersonSelector() {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _PersonSelectorSheet(
          title: 'Assign to',
          currentPersonId: transaction.assignedPersonId,
          people: people,
          onSelected: (personId) => onAssign(personId),
        ),
      );
    }

    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 8),
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
                        color: Colors.black87,
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
                        color: Colors.black87,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
           title: transaction.merchant != null
               ? Text(
                   transaction.merchant!,
                   style: theme.textTheme.titleLarge?.copyWith(
                     fontWeight: FontWeight.w700,
                     fontSize: 22,
                   ),
                   overflow: TextOverflow.ellipsis,
                   maxLines: 2,
                 )
               : Text(
                   personName,
                   style: theme.textTheme.titleLarge?.copyWith(
                     color: assigneeColor,
                     fontWeight: FontWeight.w700,
                     fontSize: 22,
                   ),
                   overflow: TextOverflow.ellipsis,
                   maxLines: 2,
                 ),
           subtitle: transaction.merchant != null
               ? Text(
                   personName,
                   style: theme.textTheme.bodySmall?.copyWith(
                     fontSize: 16,
                     color: assigneeColor,
                   ),
                   maxLines: 1,
                   overflow: TextOverflow.ellipsis,
                 )
               : null,
         trailing: Row(
           mainAxisSize: MainAxisSize.min,
           crossAxisAlignment: CrossAxisAlignment.center,
           children: [
             _TransactionAmountChip(
               amount: formatCurrency(transaction.amountValue, transaction.currency),
               pending: transaction.pending,
             ),
           ],
         ),
         children: [
           Padding(
             padding: const EdgeInsets.all(16),
             child: Column(
               crossAxisAlignment: CrossAxisAlignment.stretch,
               children: [
                 Text(
                   transaction.name,
                   style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                   maxLines: 2,
                   overflow: TextOverflow.ellipsis,
                 ),
                 const SizedBox(height: 12),
                 InkWell(
                   onTap: openPersonSelector,
                   borderRadius: BorderRadius.circular(16),
                   child: AnimatedContainer(
                     duration: const Duration(milliseconds: 150),
                     curve: Curves.easeOutCubic,
                     width: double.infinity,
                     padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                     decoration: BoxDecoration(
                       color: assigneeColor.withValues(alpha: 24),
                       borderRadius: BorderRadius.circular(16),
                       border: Border.all(
                         color: assigneeColor.withValues(alpha: 150),
                         width: 2,
                       ),
                     ),
                     child: Row(
                       children: [
                         CircleAvatar(
                           radius: 22,
                           backgroundColor: assigneeColor,
                           child: Text(
                             assignedPerson.displayName.isEmpty
                                 ? '?'
                                 : assignedPerson.displayName.substring(0, 1).toUpperCase(),
                             style: const TextStyle(
                               color: Colors.white,
                               fontSize: 17,
                               fontWeight: FontWeight.w700,
                             ),
                           ),
                         ),
                         const SizedBox(width: 12),
                         Expanded(
                           child: Column(
                             crossAxisAlignment: CrossAxisAlignment.start,
                             children: [
                               Text(
                                 'ASSIGNED TO',
                                 style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                   color: assigneeColor,
                                   fontWeight: FontWeight.w800,
                                   letterSpacing: 1.1,
                                 ),
                               ),
                               const SizedBox(height: 2),
                               Text(
                                 assignedPerson.displayName,
                                 style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                   color: assigneeColor,
                                   fontWeight: FontWeight.w800,
                                 ),
                                 maxLines: 1,
                                 overflow: TextOverflow.ellipsis,
                               ),
                             ],
                           ),
                         ),
                         const SizedBox(width: 8),
                         Icon(
                           Icons.chevron_right_rounded,
                           color: assigneeColor.withValues(alpha: 180),
                         ),
                       ],
                     ),
                   ),
                 ),
                 const SizedBox(height: 8),
                 SwitchListTile(
                   contentPadding: EdgeInsets.zero,
                   value: transaction.householdVisible,
                   onChanged: (value) => onToggleHouseholdVisible(value),
                   title: const Text('Visible to household'),
                   subtitle: const Text('Shared with other household members'),
                 ),
                 const SizedBox(height: 8),
                 if (people.length > 1) ...[
                   const Text('Split:', style: TextStyle(fontWeight: FontWeight.bold)),
                   const SizedBox(height: 8),
                   _SplitBuilder(
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
    );
  }
}

/// Slightly rounded rectangle chip showing the transaction amount in the
/// tile's trailing area. Color matches the pending/approved state of the box.
class _TransactionAmountChip extends StatelessWidget {
  const _TransactionAmountChip({
    required this.amount,
    required this.pending,
  });

  final String amount;
  final bool pending;

  @override
  Widget build(BuildContext context) {
      final color = pending ? Colors.orange.shade300 : AppColors.sageGreen;
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

class _SplitBuilder extends StatefulWidget {
  const _SplitBuilder({
    required this.transaction,
    required this.people,
    required this.onSplit,
  });

  final CardTransaction transaction;
  final List<HouseholdPerson> people;
  final Future<bool> Function(List<TransactionSplit>) onSplit;

  @override
  State<_SplitBuilder> createState() => _SplitBuilderState();
}

class _SplitBuilderState extends State<_SplitBuilder> {
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    for (final person in widget.people) {
      _controllers[person.id] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ...widget.people.map((person) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(child: Text(person.displayName)),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _controllers[person.id],
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () async {
            final splitList = <TransactionSplit>[];
            for (final person in widget.people) {
              final amt = double.tryParse(_controllers[person.id]?.text ?? '') ?? 0;
              if (amt > 0) {
                splitList.add(TransactionSplit(personId: person.id, amount: amt));
              }
            }
            if (splitList.isNotEmpty) {
              await widget.onSplit(splitList);
            }
          },
          child: const Text('Save Split'),
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
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));
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
              Icon(
                Icons.check_circle_rounded,
                color: color,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }
}