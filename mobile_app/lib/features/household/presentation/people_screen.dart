import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cardsemble/theme/app_colors.dart';
import 'package:cardsemble/features/household/presentation/household_notifier.dart';
import 'package:cardsemble/features/household/domain/household_domain.dart';


class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key});

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen>
    with AutomaticKeepAliveClientMixin {
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      // This screen is presented as a full-page route (Manage Household).
      // An opaque background prevents the black flash behind the transparent
      // route during the open/close transition.
      backgroundColor: AppColors.cream,
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
               _buildQrPlaceholder(context),
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
                    else
                      ...[
                        for (final person in notifier.people)
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
                               trailing: PopupMenuButton<String>(
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

  Widget _buildQrPlaceholder(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Material(
        color: Colors.grey.shade50,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: Colors.grey.shade300, width: 2),
        ),
        child: InkWell(
          key: const ValueKey('qr-placeholder-card'),
          onTap: () => _scanQrCode(context),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.qr_code, size: 32, color: Colors.grey.shade600),
                    const SizedBox(width: 8),
                    Text(
                      'Scan QR Code',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Scan QR code to add household members',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
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
    return showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Scan to Add Household Member',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.grey.shade400,
                    width: 3,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: SizedBox(
                    width: 300,
                    height: 400,
                    child: MobileScanner(
                      onDetect: (capture) {
                        final List<Barcode> barcodes = capture.barcodes;
                        if (barcodes.isNotEmpty) {
                          final String code = barcodes.first.rawValue ?? '';
                          if (code.isNotEmpty) {
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                              _processScannedCode(context, code.trim());
                            }
                          }
                        }
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
            ],
          ),
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