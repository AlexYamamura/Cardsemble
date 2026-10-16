import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cardsemble/features/household/presentation/household_notifier.dart';
import 'package:cardsemble/features/household/domain/household_domain.dart';


class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key});

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _nameController = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HouseholdNotifier>().loadPeople();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Household People'),
      ),
      body: Consumer<HouseholdNotifier>(
        builder: (context, notifier, _) {
          if (notifier.isLoading && notifier.people.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (notifier.error != null && notifier.people.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(notifier.error!),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => notifier.loadPeople(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [

              _buildPersonFilterBar(context, notifier),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  children: [
                    if (notifier.people.isEmpty)
                      // No people at all.
                      ...[
                        const Icon(Icons.people_outline,
                            size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        const Text('No household people yet'),
                        const SizedBox(height: 8),
                        const Text(
                            'Use the buttons below to add household people'),
                      ]
                    else if (notifier.filteredPeople.isEmpty)
                      // People exist but none match the active filters.
                      ...[
                        const Icon(Icons.people_outline,
                            size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        const Text('No people match these filters'),
                        const SizedBox(height: 8),
                        const Text(
                            'Try adjusting your search or filter criteria'),
                      ]
                    else
                      ...[
                        for (final person in notifier.filteredPeople)
                          Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: person.isDefault
                                    ? const Color(0xFF244A3A)
                                    : Colors.grey.shade300,
                                child: Icon(
                                  person.isDefault ? Icons.star : Icons.person,
                                  color: person.isDefault
                                      ? Colors.white
                                      : Colors.grey.shade600,
                                ),
                              ),
                              title: Text(person.displayName),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (!person.isDefault)
                                    TextButton.icon(
                                      icon: const Icon(Icons.star_outline,
                                          size: 18),
                                      label: const Text('Default'),
                                      onPressed: () => _setDefault(
                                          context, notifier, person),
                                    ),
                                  PopupMenuButton<String>(
                                    onSelected: (value) => _handleMenuAction(
                                        context, notifier, person, value),
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Row(
                                          children: [
                                            Icon(Icons.edit, size: 18),
                                            SizedBox(width: 8),
                                            Text('Edit'),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(Icons.delete,
                                                size: 18, color: Colors.red),
                                            SizedBox(width: 8),
                                            Text('Delete',
                                                style: TextStyle(
                                                    color: Colors.red)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              subtitle: person.isDefault
                                  ? const Text(
                                      'Default person',
                                      style: TextStyle(
                                          color: Color(0xFF244A3A)),
                                    )
                                  : null,
                            ),
                          ),
                      ],
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: _buildAddButtons(context),
                ),
              ),
            ],
          );
        },
      ),
    );
  }


  /// Compact single-row filter bar: the search field, the "Default status"
  /// dropdown, and "Clear all" all share one box so the bar stays short.
  Widget _buildPersonFilterBar(
      BuildContext context, HouseholdNotifier notifier) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 190,
              child: TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search by name',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: notifier.nameQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            _nameController.clear();
                            notifier.setNameQuery('');
                          },
                        )
                      : null,
                  border: const OutlineInputBorder(),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
                onChanged: notifier.setNameQuery,
              ),
            ),
            _PersonDefaultFilterButton(
              value: notifier.defaultFilter,
              onChanged: notifier.setDefaultFilter,
            ),
            if (notifier.hasActiveFilters)
              TextButton.icon(
                onPressed: () {
                  _nameController.clear();
                  notifier.clearAllFilters();
                },
                icon: const Icon(Icons.clear_all, size: 16),
                label: const Text('Clear all'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddButtons(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.icon(
            key: const ValueKey('add-household-member-button'),
            onPressed: () => _scanQrCode(context),
            icon: const Icon(Icons.person_add),
            label: const Text('Add household member'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('add-manually-button'),
            onPressed: () => _showAddPersonDialog(context),
            icon: const Icon(Icons.person_outline),
            label: const Text('Add manually'),
          ),
        ],
      ),
    );
  }

  void _showAddPersonDialog(BuildContext context) {
    final controller = TextEditingController();
    bool isDefault = false;
    final notifier = context.read<HouseholdNotifier>();

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add Person'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Display Name',
                  hintText: 'e.g., John, Sarah',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                title: const Text('Set as default'),
                value: isDefault,
                onChanged: (value) => setState(() => isDefault = value ?? false),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isEmpty) return;
                final success =
                    await notifier.createPerson(name, isDefault: isDefault);
                if (success && dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _setDefault(BuildContext context, HouseholdNotifier notifier,
      HouseholdPerson person) async {
    final success = await notifier.updatePerson(person.id, person.displayName,
        isDefault: true);
    if (!success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(notifier.error ?? 'Failed to set default')),
      );
    }
  }

  void _handleMenuAction(BuildContext context, HouseholdNotifier notifier,
      HouseholdPerson person, String action) {
    switch (action) {
      case 'edit':
        _showEditDialog(context, notifier, person);
        break;
      case 'delete':
        _showDeleteConfirm(context, notifier, person);
        break;
    }
  }

  void _showEditDialog(BuildContext context, HouseholdNotifier notifier,
      HouseholdPerson person) {
    final controller = TextEditingController(text: person.displayName);
    bool isDefault = person.isDefault;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Edit Person'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(labelText: 'Display Name'),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                title: const Text('Set as default'),
                value: isDefault,
                onChanged: (value) => setState(() => isDefault = value ?? false),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isEmpty) return;
                final success = await notifier.updatePerson(person.id, name,
                    isDefault: isDefault);
                if (success && dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirm(BuildContext context, HouseholdNotifier notifier,
      HouseholdPerson person) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Person?'),
        content: Text('Are you sure you want to delete "${person.displayName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final success = await notifier.deletePerson(person.id);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (!success && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(notifier.error ?? 'Failed to delete')),
                );
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _scanQrCode(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Scan QR Code to Add Person',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: MobileScanner(
                onDetect: (capture) {
                  final List<Barcode> barcodes = capture.barcodes;
                  if (barcodes.isNotEmpty) {
                    final String code = barcodes.first.rawValue ?? '';
                    if (code.isNotEmpty) {
                      // Process the scanned code
                      _processScannedCode(context, code.trim());
                    }
                  }
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _processScannedCode(BuildContext context, String code) async {
    final notifier = context.read<HouseholdNotifier>();
    // Try to add as member first (assuming code is a userId)
    final successAdd = await notifier.addMember(code);
    if (successAdd) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Person added successfully!')),
        );
      }
    } else {
      // If adding as member fails, try to join by invite code
      final successJoin = await notifier.joinByInviteCode(code);
      if (successJoin) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Joined household successfully!')),
          );
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(notifier.error ?? 'Failed to process QR code')),
          );
        }
      }
    }
  }
}

/// Compact chip-style dropdown used by the People filter bar. Mirrors the
/// transactions `_FilterMenuButton` so the two screens look consistent, while
/// keeping "Clear all" inline in the same box.
class _PersonDefaultFilterButton extends StatelessWidget {
  const _PersonDefaultFilterButton({
    required this.value,
    required this.onChanged,
  });

  /// null = all, true = default only, false = others.
  final bool? value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = value != null;
    final label = switch (value) {
      null => 'Default status',
      true => 'Default only',
      false => 'Others',
    };

    return PopupMenuButton<bool?>(
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (context) => const [
        PopupMenuItem<bool?>(value: null, child: Text('All')),
        PopupMenuItem<bool?>(value: true, child: Text('Default only')),
        PopupMenuItem<bool?>(value: false, child: Text('Others')),
      ],
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
            ),
            color: selected
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
                  color: selected
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
