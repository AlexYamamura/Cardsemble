import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cardsemble/features/accounts/domain/entities/account.dart';
import 'package:cardsemble/features/accounts/domain/accounts_domain.dart';
import 'package:cardsemble/features/accounts/presentation/accounts_notifier.dart';
import 'package:cardsemble/features/household/domain/household_domain.dart';
import 'package:cardsemble/features/transactions/presentation/transactions_notifier.dart';

/// Bottom sheet for configuring a connected card's per-card settings:
/// whether it is an individual or household card, and its default assignee.
///
/// - Individual: always assigned to the household default person ("you").
/// - Household + person: assigned to you or another household person.
/// - Household + shared: excluded from the payer's "Pay" total.
/// - Household + split: split evenly across household people; only your share
///   counts toward the "Pay" total.
class CardConfigSheet extends StatefulWidget {
  const CardConfigSheet({
    super.key,
    required this.accountId,
    required this.accountName,
    required this.cardType,
    required this.defaultAssigneeMode,
    this.defaultAssigneePersonId,
    required this.people,
    required this.accountsNotifier,
    required this.transactionsNotifier,
  });

  final String accountId;
  final String accountName;
  final CardType cardType;
  final CardAssigneeMode defaultAssigneeMode;
  final String? defaultAssigneePersonId;
  final List<HouseholdPerson> people;
  final AccountsNotifier accountsNotifier;
  final TransactionsNotifier transactionsNotifier;

  @override
  State<CardConfigSheet> createState() => _CardConfigSheetState();
}

class _CardConfigSheetState extends State<CardConfigSheet> {
  late CardType _cardType;
  late CardAssigneeMode _mode;
  String? _personId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cardType = widget.cardType;
    _mode = widget.defaultAssigneeMode;
    _personId = widget.defaultAssigneePersonId;
  }

  List<HouseholdPerson> get _otherPeople =>
      widget.people.where((p) => !p.isDefault).toList(growable: false);

  bool get _isIndividual => _cardType == CardType.individual;

  bool get _canSplit => widget.people.length >= 2;

  Future<void> _save() async {
    if (_saving) return;
    final mode = _isIndividual ? CardAssigneeMode.person : _mode;
    final personId = _isIndividual || mode != CardAssigneeMode.person
        ? null
        : _personId;

    if (mode == CardAssigneeMode.split && !_canSplit) {
      setState(() => _error = 'Split requires at least two household people.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final success = await widget.accountsNotifier.updateCardConfig(
      accountId: widget.accountId,
      cardType: _cardType,
      defaultAssigneeMode: mode,
      defaultAssigneePersonId: personId,
    );

    if (!mounted) return;
    setState(() => _saving = false);

    if (success) {
      // Refresh the transaction list so the Pay total reflects the new config.
      unawaited(widget.transactionsNotifier.loadAccounts());
      if (context.mounted) Navigator.of(context).pop();
    } else {
      setState(() => _error = widget.accountsNotifier.error ?? 'Could not save the card configuration.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: color.outline.withValues(alpha: 100),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Text(
              'Card settings',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.accountName,
              style: TextStyle(
                fontSize: 14,
                color: color.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            // Card type
            const Text(
              'Card type',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 8),
            SegmentedButton<CardType>(
              selected: <CardType>{_cardType},
              onSelectionChanged: _saving ? null : (selection) {
                setState(() {
                  _cardType = selection.first;
                  if (!_isIndividual) {
                    _mode = CardAssigneeMode.person;
                    _personId = null;
                  }
                });
              },
              segments: const <ButtonSegment<CardType>>[
                ButtonSegment<CardType>(
                  value: CardType.individual,
                  label: Text('Individual'),
                ),
                ButtonSegment<CardType>(
                  value: CardType.household,
                  label: Text('Household'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (!_isIndividual) ...[
              const Text(
                'Default assignee',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 8),
              ..._buildAssigneeOptions(color),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildAssigneeOptions(ColorScheme color) {
    final options = <Widget>[];

    // You (the household default person).
    options.add(
      _RadioTile(
        title: 'You',
        subtitle: 'Household default person',
        value: 'person-you',
        groupValue: _selectedOption,
        onChanged: _saving ? null : () => _setPerson(null),
        selectedColor: color.primary,
      ),
    );

    // Other household people.
    for (final person in _otherPeople) {
      options.add(
        _RadioTile(
          title: person.displayName,
          subtitle: 'Another household member',
          value: 'person-${person.id}',
          groupValue: _selectedOption,
          onChanged: _saving ? null : () => _setPerson(person.id),
          selectedColor: color.primary,
        ),
      );
    }

    // Shared.
    options.add(
      _RadioTile(
        title: 'Shared',
        subtitle: 'Excluded from your Pay total',
        value: 'shared',
        groupValue: _selectedOption,
        onChanged: _saving ? null : () => _setShared(),
        selectedColor: color.primary,
      ),
    );

    // Split.
    options.add(
      _RadioTile(
        title: 'Split',
        subtitle: _canSplit
            ? 'Your even share counts toward Pay'
            : 'Needs at least two household people',
        value: 'split',
        groupValue: _selectedOption,
        onChanged: _canSplit && !_saving ? () => _setSplit() : null,
        selectedColor: color.primary,
        enabled: _canSplit,
      ),
    );

    return options;
  }

  String get _selectedOption {
    if (_isIndividual) return 'person-you';
    switch (_mode) {
      case CardAssigneeMode.person:
        return _personId == null ? 'person-you' : 'person-$_personId';
      case CardAssigneeMode.shared:
        return 'shared';
      case CardAssigneeMode.split:
        return 'split';
    }
  }

  void _setPerson(String? personId) {
    setState(() {
      _mode = CardAssigneeMode.person;
      _personId = personId;
      _error = null;
    });
  }

  void _setShared() {
    setState(() {
      _mode = CardAssigneeMode.shared;
      _personId = null;
      _error = null;
    });
  }

  void _setSplit() {
    setState(() {
      _mode = CardAssigneeMode.split;
      _personId = null;
      _error = null;
    });
  }
}

/// A single radio-style selectable row for the default assignee options.
class _RadioTile extends StatelessWidget {
  const _RadioTile({
    required this.title,
    this.subtitle,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    this.selectedColor,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final String value;
  final String groupValue;
  final VoidCallback? onChanged;
  final Color? selectedColor;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final selected = groupValue == value;
    return InkWell(
      onTap: enabled ? onChanged : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? (selectedColor ?? Theme.of(context).colorScheme.primary)
                  .withValues(alpha: 0.10)
              : null,
          border: Border.all(
            color: selected
                ? (selectedColor ?? Theme.of(context).colorScheme.primary)
                : Theme.of(context).colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: selected
                    ? (selectedColor ?? Theme.of(context).colorScheme.primary)
                    : null,
                border: Border.all(
                  color: selected
                      ? (selectedColor ?? Theme.of(context).colorScheme.primary)
                      : Theme.of(context).colorScheme.outline,
                  width: 2,
                ),
                shape: BoxShape.circle,
              ),
              child: selected
                  ? const Center(
                      child: Icon(
                        Icons.check,
                        size: 14,
                        color: Colors.white,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: enabled ? null : Colors.grey,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 12,
                        color: enabled
                            ? Colors.grey.shade600
                            : Colors.grey.shade400,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle,
                  color: selectedColor ?? Theme.of(context).colorScheme.primary),
          ],
        ),
      ),
    );
  }
}
