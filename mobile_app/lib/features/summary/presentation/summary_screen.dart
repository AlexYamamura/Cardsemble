import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cardsemble/core/utils/currency.dart';
import 'package:cardsemble/core/core.dart';
import 'package:cardsemble/features/accounts/presentation/accounts_notifier.dart';
import 'package:cardsemble/features/accounts/presentation/accounts_screen.dart';
import 'package:cardsemble/features/auth/presentation/auth_notifier.dart';
import 'package:cardsemble/features/household/domain/household_domain.dart';
import 'package:cardsemble/features/transactions/presentation/transactions_notifier.dart';
import 'package:cardsemble/features/transactions/domain/transactions_domain.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class SummaryScreen extends StatefulWidget {
  const SummaryScreen({
    super.key,
    required this.onShowTransactions,
    this.onOpenSettings,
  });

  final VoidCallback onShowTransactions;
  final VoidCallback? onOpenSettings;

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
   late DateTimeRange _summaryRange;
   bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    _summaryRange = _currentMonthRange();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<TransactionsNotifier>().loadSummaryTransactions(_summaryRange);
      final accounts = context.read<AccountsNotifier>();
      accounts.loadConnections();
      accounts.loadStatementCycles();
    });
  }

  DateTimeRange _currentMonthRange() {
    final today = DateUtils.dateOnly(DateTime.now());
    return DateTimeRange(
      start: DateTime(today.year, today.month),
      end: today,
    );
  }

  List<DateTime> _quickMonths() {
    final today = DateUtils.dateOnly(DateTime.now());
    return List<DateTime>.generate(
      12,
      (index) => DateTime(today.year, today.month - index, 1),
      growable: false,
    );
  }

  bool _rangeIsMonth(DateTime month) {
    final today = DateUtils.dateOnly(DateTime.now());
    final monthEnd = DateTime(month.year, month.month + 1, 0);
    final expectedEnd = monthEnd.isAfter(today) ? today : monthEnd;
    return _summaryRange.start == DateTime(month.year, month.month) &&
        _summaryRange.end == expectedEnd;
  }

  void _selectMonth(DateTime month) {
    final today = DateUtils.dateOnly(DateTime.now());
    final monthEnd = DateTime(month.year, month.month + 1, 0);
    final range = DateTimeRange(
      start: DateTime(month.year, month.month),
      end: monthEnd.isAfter(today) ? today : monthEnd,
    );
    setState(() {
      _summaryRange = range;
    });
    final notifier = context.read<TransactionsNotifier>();
    // Sync the transactions tab's date range so the chips stay connected, but do
    // not trigger a transactions list reload from the summary tab.
    notifier.setDateRange(range, reloadList: false);
    notifier.loadSummaryTransactions(range);
  }

  Future<void> _chooseSummaryRange() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(today.year + 2),
      initialDateRange: _summaryRange,
      helpText: 'Choose transaction date range',
      saveText: 'Apply range',
    );
    if (picked == null || !mounted) return;
    final range = DateTimeRange(
      start: DateUtils.dateOnly(picked.start),
      end: DateUtils.dateOnly(picked.end),
    );
    setState(() {
      _summaryRange = range;
    });
    final notifier = context.read<TransactionsNotifier>();
    // Sync the transactions tab's date range so the chips stay connected, but do
    // not trigger a transactions list reload from the summary tab.
    notifier.setDateRange(range, reloadList: false);
    notifier.loadSummaryTransactions(range);
  }

  Future<void> _refresh() async {
    await context.read<TransactionsNotifier>().refresh();
    if (!mounted) return;
    final accounts = context.read<AccountsNotifier>();
    await accounts.loadStatementCycles();
  }

  void _drilldownIntoTransactions({String? accountId, String? personId}) {
    final notifier = context.read<TransactionsNotifier>();
    notifier.setAccountFilter(accountId);
    notifier.setPersonFilter(personId);
    notifier.setDateRange(_summaryRange);
    widget.onShowTransactions();
  }

  Future<void> _editCardName(_AccountInfo account) async {
    final controller = TextEditingController(text: account.label);
    final accounts = context.read<AccountsNotifier>();
    final transactions = context.read<TransactionsNotifier>();

    final saved = await showDialog<String?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Rename card: ${account.label}'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Display name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == null) return;
    final displayName = saved.isEmpty ? null : saved;
    final success = await accounts.updateDisplayName(account.accountId, displayName);
    if (success) {
      await transactions.refresh();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(accounts.error ?? 'Failed to rename card')),
      );
    }
  }

   void _openAccounts() {
     Navigator.of(context).push(
       MaterialPageRoute<void>(builder: (_) => const AccountsScreen()),
     );
   }

   Future<void> _importCsv() async {
     final accountsNotifier = context.read<AccountsNotifier>();
     final statementSummary = accountsNotifier.statementSummary;
     if (statementSummary == null || statementSummary.accounts.isEmpty) {
       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('No accounts available. Please link a card first.')),
         );
       }
       return;
     }

     // Use the first account for simplicity; could be improved to let user choose.
     final accountId = statementSummary.accounts.first.accountId;

      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result == null) return;

      final file = result.files.first;
      Uint8List? csvBytes = file.bytes;
      if (csvBytes == null) {
        // Fallback to reading from path if available
        if (file.path != null && file.path!.isNotEmpty) {
          try {
            csvBytes = await File(file.path!).readAsBytes();
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error reading file: $e')),
              );
            }
            return;
          }
        }
      }

      if (csvBytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not read file.')),
          );
        }
        return;
      }
      final csvText = utf8.decode(csvBytes);

      if (!mounted) return;

      setState(() {
        _isImporting = true;
      });

      final previewResult = await context
          .read<TransactionsNotifier>()
          .previewCsvImport(accountId, csvText);

     if (!mounted) {
       setState(() {
         _isImporting = false;
       });
       return;
     }

      previewResult.fold(
        (preview) {
          setState(() {
            _isImporting = false;
          });
          _showImportPreviewDialog(preview, accountId, file.name);
        },
        (failure) {
          setState(() {
            _isImporting = false;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Preview failed: ${failure.message}')),
            );
          }
        },
      );
   }

   void _showImportPreviewDialog(CsvImportPreview preview, String accountId, String fileName) {
     showDialog(
       context: context,
       builder: (context) => AlertDialog(
         title: const Text('CSV Import Preview'),
         content: SingleChildScrollView(
           child: Column(
             mainAxisSize: MainAxisSize.min,
             children: [
               Text(
                   'New: ${preview.summary.newCount}, Duplicates: ${preview.summary.duplicateCount}, Errors: ${preview.summary.errorCount}'),
               const SizedBox(height: 10),
               if (preview.preview.isEmpty)
                 const Text('No rows to import.')
               else
                 DataTable(
                   columns: const [
                     DataColumn(label: Text('Date')),
                     DataColumn(label: Text('Description')),
                     DataColumn(label: Text('Amount')),
                     DataColumn(label: Text('Status')),
                   ],
                   rows: preview.preview.map((row) => DataRow(cells: [
                         DataCell(Text(row.row.transactionDate)),
                         DataCell(Text(row.row.description.length > 20
                             ? '${row.row.description.substring(0, 20)}...'
                             : row.row.description)),
                         DataCell(Text('${row.row.amount} ${row.row.currency}')),
                         DataCell(Text(row.status)),
                       ])).toList()),
             ],
           ),
         ),
         actions: [
           TextButton(
             onPressed: () => Navigator.pop(context),
             child: const Text('Cancel'),
           ),
           ElevatedButton(
             onPressed: preview.summary.newCount > 0
                 ? () async {
                     Navigator.pop(context);
                     setState(() {
                       _isImporting = true;
                     });
                     final newRows = preview.preview
                         .where((r) => r.status == 'new')
                         .map((r) => r.row)
                         .toList();
                     final confirmResult = await context
                         .read<TransactionsNotifier>()
                         .confirmCsvImport(accountId, newRows, fileName);
                     if (!mounted) {
                       setState(() {
                         _isImporting = false;
                       });
                       return;
                     }
                     confirmResult.fold(
                       (result) {
                         setState(() {
                           _isImporting = false;
                         });
                         if (mounted) {
                           ScaffoldMessenger.of(context).showSnackBar(
                             SnackBar(
                                 content: Text(
                                     'Imported ${result.inserted} transactions, ${result.errors.length} errors.')),
                           );
                         }
                         // Refresh transactions
                         context.read<TransactionsNotifier>().refresh();
                       },
                       (failure) {
                         setState(() {
                           _isImporting = false;
                         });
                         if (mounted) {
                           ScaffoldMessenger.of(context).showSnackBar(
                             SnackBar(
                                 content: Text('Import failed: ${failure.message}')),
                           );
                         }
                       },
                     );
                   }
                 : null,
             child: const Text('Import'),
           ),
         ],
       ),
     );
   }

   @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Monthly summary'),
        actions: [
          if (widget.onOpenSettings != null)
            IconButton(
              tooltip: 'Settings',
              onPressed: widget.onOpenSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            tooltip: 'Account',
            onSelected: (value) async {
              if (value != 'sign-out') return;
              await context.read<AuthNotifier>().signOut();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'sign-out', child: Text('Sign out')),
            ],
          ),
        ],
      ),
       body: Consumer<TransactionsNotifier>(
         builder: (context, notifier, _) {
           if (notifier.isSummaryLoading &&
               notifier.summaryTransactions.isEmpty &&
               notifier.people.isEmpty) {
             return const Center(child: CircularProgressIndicator());
           }



           return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: _buildSummaryContent(theme, notifier),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildSummaryContent(
    ThemeData theme,
    TransactionsNotifier notifier,
  ) {
    final included = notifier.summaryTransactions
        .where((transaction) {
          final date = transaction.parsedDate;
          if (date == null) return false;
          final day = DateUtils.dateOnly(date);
          return !transaction.pending &&
              !transaction.isPayment &&
              transaction.amountValue > 0 &&
              !day.isBefore(_summaryRange.start) &&
              !day.isAfter(_summaryRange.end);
        })
        .toList(growable: false);

    final totalsByCurrency = <String, double>{};
    final totalsByCard = <String, double>{};
    final currenciesByCard = <String, String>{};
    final totalsByPersonAndCurrency = <String, double>{};

    final accountsById = <String, _AccountInfo>{};
    for (final transaction in notifier.summaryTransactions) {
      final accountId = transaction.accountId;
      if (accountId == null || accountsById.containsKey(accountId)) continue;
      accountsById[accountId] = _AccountInfo(
        accountId: accountId,
        label: transaction.displayName ??
            transaction.accountName ??
            transaction.plaidName ??
            'Credit card',
        mask: transaction.accountMask,
      );
    }

    final peopleById = {for (final person in notifier.people) person.id: person};
    final primaryId =
        notifier.people.where((person) => person.isDefault).firstOrNull?.id;

    for (final transaction in included) {
      final amount = transaction.amountValue;
      final currency = transaction.currency;
      totalsByCurrency.update(
        currency,
        (total) => total + amount,
        ifAbsent: () => amount,
      );

      final cardId = transaction.accountId ?? 'unknown-card';
      final cardKey = '$cardId|$currency';
      totalsByCard.update(
        cardKey,
        (total) => total + amount,
        ifAbsent: () => amount,
      );
      currenciesByCard[cardKey] = currency;

      final personId = transaction.assignedPersonId ?? primaryId;
      final personKey = '${personId ?? 'unassigned'}|$currency';
      totalsByPersonAndCurrency.update(
        personKey,
        (total) => total + amount,
        ifAbsent: () => amount,
      );
    }

    final quickMonths = _quickMonths();

    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Household spending',
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
              const SizedBox(height: 4),
              Text(_rangeLabel(_summaryRange),
                  style: theme.textTheme.bodyMedium),
              const SizedBox(height: 12),
              if (totalsByCurrency.isEmpty)
                Text(
                  'No posted card charges in this date range.',
                  style: theme.textTheme.titleMedium,
                )
              else
                ...totalsByCurrency.entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      '${currencySymbol(entry.key)} ${_money(entry.value.toStringAsFixed(2))}',
                      style: theme.textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                '${included.length} posted charge${included.length == 1 ? '' : 's'}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: _chooseSummaryRange,
        icon: const Icon(Icons.date_range),
        label: const Text('Choose date range'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      const SizedBox(height: 4),
      SizedBox(
        height: 48,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: quickMonths.length,
          separatorBuilder: (context, index) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final month = quickMonths[index];
            final isSelected = _rangeIsMonth(month);
            return FilterChip(
              key: ValueKey('quick-month-${month.year}-${month.month}'),
              label: Text(_monthLabel(month)),
              selected: isSelected,
              onSelected: (_) => _selectMonth(month),
              selectedColor: theme.colorScheme.primary,
              checkmarkColor: Colors.white,
              labelStyle: TextStyle(
                color: isSelected
                    ? Colors.white
                    : theme.colorScheme.primary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
              side: BorderSide(color: theme.colorScheme.primary),
              backgroundColor: Colors.white,
            );
          },
        ),
      ),
      const SizedBox(height: 12),
      _BreakdownCard(
        title: 'By credit card',
        emptyMessage: 'No card charges in this period.',
        onEditRow: (row) {
          final info = accountsById[row.id];
          if (info != null) _editCardName(info);
        },
        onRowTap: (row) => _drilldownIntoTransactions(accountId: row.id),
        rows: totalsByCard.entries.map((entry) {
          final accountId = entry.key.split('|').first;
          final account = accountsById[accountId];
          return _BreakdownRow(
            id: accountId,
            label: account?.label ??
                (accountId == 'unknown-card' ? 'Card name unavailable' : 'Card'),
            currency: currenciesByCard[entry.key]!,
            amount: entry.value,
            editable: true,
          );
        }).toList(),
      ),
      const SizedBox(height: 8),
       Row(
         mainAxisAlignment: MainAxisAlignment.center,
         children: [
           FilledButton.icon(
             onPressed: _openAccounts,
             icon: const Icon(Icons.add, size: 18),
             label: const Text('Link a card'),
             style: FilledButton.styleFrom(
               padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
               textStyle:
                   const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
             ),
           ),
           const SizedBox(width: 12),
           FilledButton.icon(
             onPressed: _isImporting ? null : _importCsv,
             icon: const Icon(Icons.upload_file, size: 18),
             label: Text(_isImporting ? 'Importing...' : 'Import CSV'),
             style: FilledButton.styleFrom(
               padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
               textStyle:
                   const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
             ),
           ),
         ],
       ),
      const SizedBox(height: 12),
      _BreakdownCard(
        title: 'By household member',
        emptyMessage: 'No assigned charges in this period.',
        onRowTap: (row) => _drilldownIntoTransactions(personId: row.id),
        rows: totalsByPersonAndCurrency.entries.map((entry) {
          final parts = entry.key.split('|');
          final person = peopleById[parts.first];
          return _BreakdownRow(
            id: person?.id ?? 'unassigned',
            label: person?.displayName ?? 'Unassigned',
            currency: parts.last,
            amount: entry.value,
            color: person == null
                ? null
                : _personColor(person, notifier.people),
          );
        }).toList(),
      ),
      const SizedBox(height: 12),
      Text(
        'Counts positive, posted card charges by transaction date. Pending '
        'transactions, credits/refunds, and card payments are excluded. This '
        'is spending in the selected range, not the Plaid statement balance '
        'or a calculated amount to pay your partner.',
        style: theme.textTheme.bodySmall,
      ),
      if (notifier.summaryTransactions.isEmpty &&
          notifier.transactions.isEmpty &&
          !notifier.isSummaryLoading) ...[
        const SizedBox(height: 12),
        _emptyCard(theme, 'No Plaid transactions have been synced yet.'),
      ],
    ];
  }

  Widget _emptyCard(ThemeData theme, String message) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Text(message, style: theme.textTheme.bodyMedium),
      ),
    );
  }
}

class _AccountInfo {
  const _AccountInfo({
    required this.accountId,
    required this.label,
    this.mask,
  });

  final String accountId;
  final String label;
  final String? mask;
}

class _BreakdownRow {
  const _BreakdownRow({
    required this.id,
    required this.label,
    required this.currency,
    required this.amount,
    this.color,
    this.editable = false,
  });

  final String id;
  final String label;
  final String currency;
  final double amount;
  final Color? color;
  final bool editable;
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({
    required this.title,
    required this.emptyMessage,
    required this.onRowTap,
    this.onEditRow,
    required this.rows,
  });

  final String title;
  final String emptyMessage;
  final ValueChanged<_BreakdownRow> onRowTap;
  final ValueChanged<_BreakdownRow>? onEditRow;
  final List<_BreakdownRow> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grouped = <String, List<_BreakdownRow>>{};
    for (final row in rows) {
      grouped.putIfAbsent(row.currency, () => []).add(row);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleLarge),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Text(emptyMessage),
              )
            else
              ...grouped.entries.expand(
                (currencyGroup) => [
                  if (grouped.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 4),
                      child: Text(
                        currencyGroup.key,
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                  ...currencyGroup.value.map(
                    (row) => InkWell(
                      key: ValueKey('summary-row-${row.id}'),
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => onRowTap(row),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            if (row.color != null) ...[
                              CircleAvatar(
                                radius: 8,
                                backgroundColor: row.color,
                              ),
                              const SizedBox(width: 9),
                            ],
                            Expanded(
                              child: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      row.label,
                                      style: theme.textTheme.bodyLarge,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (onEditRow != null && row.editable) ...[
                                    const SizedBox(width: 8),
                                    IconButton(
                                      key: ValueKey('edit-card-name-${row.id}'),
                                      tooltip: 'Edit card name',
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 28,
                                        minHeight: 28,
                                      ),
                                      onPressed: () => onEditRow!(row),
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 18,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '${currencySymbol(row.currency)} ${_money(row.amount.toStringAsFixed(2))}',
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(width: 6),
                            if (onEditRow == null || !row.editable)
                              Icon(
                                Icons.chevron_right,
                                color: theme.colorScheme.outline,
                                size: 20,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

Color _personColor(HouseholdPerson person, List<HouseholdPerson> people) {
  const palette = [
    Color(0xFF176B5B),
    Color(0xFF4F46A5),
    Color(0xFFC2415D),
    Color(0xFF146A8A),
    Color(0xFF8A4E9B),
    Color(0xFF966000),
  ];
  final index = people.indexWhere((candidate) => candidate.id == person.id);
  if (index < 0) return palette.first;
  return palette[index % palette.length];
}

String _money(String value, {bool absolute = false}) {
  final parsed = double.tryParse(value);
  if (parsed == null) return value;
  return (absolute ? parsed.abs() : parsed).toStringAsFixed(2);
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

String _monthLabel(DateTime value) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return "${months[value.month - 1]} '${value.year.toString().substring(2)}";
}
