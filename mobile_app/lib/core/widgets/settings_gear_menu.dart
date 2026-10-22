import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cardsemble/features/auth/presentation/auth_notifier.dart';

/// Gear dropdown shown in the header of every tab.
///
/// Options, in order: Settings, Card Events, Manage Household, Sign out.
class SettingsGearMenu extends StatelessWidget {
  const SettingsGearMenu({
    super.key,
    this.onOpenSettings,
    this.onOpenCardEvents,
    this.onOpenManageHousehold,
  });

  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenCardEvents;
  final VoidCallback? onOpenManageHousehold;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Menu',
      icon: const Icon(Icons.settings_outlined),
      onSelected: (value) async {
        switch (value) {
          case 'settings':
            onOpenSettings?.call();
            break;
          case 'card-events':
            onOpenCardEvents?.call();
            break;
          case 'manage-household':
            onOpenManageHousehold?.call();
            break;
          case 'sign-out':
            await context.read<AuthNotifier>().signOut();
            break;
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'settings', child: Text('Settings')),
        PopupMenuItem(value: 'card-events', child: Text('Card Events')),
        PopupMenuItem(
          value: 'manage-household',
          child: Text('Manage Household'),
        ),
        PopupMenuItem(value: 'sign-out', child: Text('Sign out')),
      ],
    );
  }
}
