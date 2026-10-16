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

class _PeopleScreenState extends State<PeopleScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HouseholdNotifier>().loadPeople();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Household People'),
      ),
       body: Column(
         children: [
           Expanded(
             child: Consumer<HouseholdNotifier>(
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

                 if (notifier.people.isEmpty) {
                   return Center(
                     child: Column(
                       mainAxisSize: MainAxisSize.min,
                       children: [
                         const Icon(Icons.people_outline, size: 64, color: Colors.grey),
                         const SizedBox(height: 16),
                         const Text('No household people yet'),
                         const SizedBox(height: 8),
                         const Text('Use the buttons below to add household people'),
                       ],
                     ),
                   );
                 }

                 return ListView.builder(
                   padding: const EdgeInsets.all(16),
                   itemCount: notifier.people.length,
                   itemBuilder: (context, index) {
                     final person = notifier.people[index];
                     return Card(
                       margin: const EdgeInsets.only(bottom: 12),
                       child: ListTile(
                         leading: CircleAvatar(
                           backgroundColor: person.isDefault
                               ? const Color(0xFF244A3A)
                               : Colors.grey.shade300,
                           child: Icon(
                             person.isDefault ? Icons.star : Icons.person,
                             color: person.isDefault ? Colors.white : Colors.grey.shade600,
                           ),
                         ),
                         title: Text(person.displayName),
                         trailing: Row(
                           mainAxisSize: MainAxisSize.min,
                           children: [
                             if (!person.isDefault)
                               TextButton.icon(
                                 icon: const Icon(Icons.star_outline, size: 18),
                                 label: const Text('Default'),
                                 onPressed: () => _setDefault(context, notifier, person),
                               ),
                             PopupMenuButton<String>(
                               onSelected: (value) => _handleMenuAction(context, notifier, person, value),
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
                                       Icon(Icons.delete, size: 18, color: Colors.red),
                                       SizedBox(width: 8),
                                       Text('Delete', style: TextStyle(color: Colors.red)),
                                     ],
                                   ),
                                 ),
                               ],
                             ),
                           ],
                         ),
                         subtitle: person.isDefault
                             ? const Text('Default person', style: TextStyle(color: Color(0xFF244A3A)))
                             : null,
                       ),
                     );
                   },
                 );
               },
             ),
           ),
           SafeArea(
             child: Padding(
               padding: EdgeInsets.all(16.0),
               child: Column(
                 mainAxisSize: MainAxisSize.min,
                 children: [
                   FilledButton.icon(
                     onPressed: () => _scanQrCode(context),
                     icon: Icon(Icons.person_add),
                     label: Text('Add household member'),
                   ),
                   SizedBox(height: 8),
                   OutlinedButton.icon(
                     onPressed: () => _showAddPersonDialog(context),
                     icon: Icon(Icons.person_outline),
                     label: Text('Add manually'),
                   ),
                 ],
               ),
             ),
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
                final success = await notifier.createPerson(name, isDefault: isDefault);
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

  void _setDefault(BuildContext context, HouseholdNotifier notifier, HouseholdPerson person) async {
    final success = await notifier.updatePerson(person.id, person.displayName, isDefault: true);
    if (!success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(notifier.error ?? 'Failed to set default')),
      );
    }
  }

  void _handleMenuAction(BuildContext context, HouseholdNotifier notifier, HouseholdPerson person, String action) {
    switch (action) {
      case 'edit':
        _showEditDialog(context, notifier, person);
        break;
      case 'delete':
        _showDeleteConfirm(context, notifier, person);
        break;
    }
  }

  void _showEditDialog(BuildContext context, HouseholdNotifier notifier, HouseholdPerson person) {
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
                final success = await notifier.updatePerson(person.id, name, isDefault: isDefault);
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

  void _showDeleteConfirm(BuildContext context, HouseholdNotifier notifier, HouseholdPerson person) {
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