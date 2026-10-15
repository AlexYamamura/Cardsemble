import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cardsemble/theme/app_colors.dart';
import 'package:cardsemble/features/device_capture/presentation/device_capture_notifier.dart';
import 'package:cardsemble/features/household/domain/household_domain.dart';

class DeviceCaptureScreen extends StatefulWidget {
  const DeviceCaptureScreen({super.key});

  @override
  State<DeviceCaptureScreen> createState() => _DeviceCaptureScreenState();
}

class _DeviceCaptureScreenState extends State<DeviceCaptureScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DeviceCaptureNotifier>().loadPeople();
      context.read<DeviceCaptureNotifier>().checkStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Capture'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: () => _refresh(context),
            tooltip: 'Refresh status',
          ),
        ],
      ),
      body: Consumer<DeviceCaptureNotifier>(
        builder: (context, notifier, _) {
          if (notifier.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          return RefreshIndicator(
            onRefresh: () => _refresh(context),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildStatusCard(context, notifier),
                const SizedBox(height: 24),
                if (!notifier.isConfigured) ...[
                  _buildSetupSection(context, notifier),
                  const SizedBox(height: 24),
                ],
                if (notifier.isConfigured) ...[
                  _buildActiveSection(context, notifier),
                  const SizedBox(height: 24),
                ],
                _buildInfoSection(context),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _refresh(BuildContext context) async {
    await context.read<DeviceCaptureNotifier>().checkStatus();
  }

  Widget _buildStatusCard(BuildContext context, DeviceCaptureNotifier notifier) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: notifier.isConfigured ? Colors.green.shade100 : Colors.orange.shade100,
                  child: Icon(
                    notifier.isConfigured ? Icons.check_circle : Icons.pending,
                    color: notifier.isConfigured ? Colors.green.shade700 : Colors.orange.shade700,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notifier.isConfigured ? 'Capture Active' : 'Not Configured',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        notifier.isConfigured
                            ? 'Google Pay notifications are being captured'
                            : 'Set up to auto-capture card transactions',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (notifier.deviceId != null) ...[
              const SizedBox(height: 16),
              Text('Device ID: ${notifier.deviceId}', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                _StatusChip(
                  label: 'Notification Access',
                  value: notifier.hasNotificationAccess ? 'Granted' : 'Not Granted',
                  isPositive: notifier.hasNotificationAccess,
                ),
                const SizedBox(width: 8),
                if (!notifier.hasNotificationAccess)
                  TextButton(
                    onPressed: () => notifier.openNotificationAccessSettings(),
                    child: const Text('Grant Access'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSetupSection(BuildContext context, DeviceCaptureNotifier notifier) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Setup', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            Text(
              'Select a household member to associate with this device. Google Pay notifications for their cards will be auto-captured.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            if (notifier.people.isEmpty)
              Text('No household members found. Add people first.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.red.shade600))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: notifier.people.map((person) {
                  return FilledButton(
                    onPressed: () => _createAndConfigure(context, notifier, person),
                    style: FilledButton.styleFrom(
                      backgroundColor: person.isDefault ? AppColors.primary : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: person.isDefault ? Colors.white : Colors.grey.shade300,
                          child: Text(
                            person.displayName.substring(0, 1).toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              color: person.isDefault ? AppColors.primary : Colors.grey.shade600,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(person.displayName),
                        if (person.isDefault) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.star, size: 16),
                        ],
                      ],
                    ),
                  );
                }).toList(),
              ),
            if (notifier.error != null) ...[
              const SizedBox(height: 16),
              Text(notifier.error!, style: TextStyle(color: Colors.red.shade700)),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _createAndConfigure(BuildContext context, DeviceCaptureNotifier notifier, HouseholdPerson person) async {
    final success = await notifier.createDeviceToken(person.id);
    if (!success || notifier.credentials == null) return;

    final apiUrl = 'https://creditcards-beige.vercel.app'; // TODO: Get from env
    final configured = await notifier.configureCapture(apiUrl);
    if (!configured) return;

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Device capture configured for ${person.displayName}')),
      );
    }
  }

  Widget _buildActiveSection(BuildContext context, DeviceCaptureNotifier notifier) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Active Device', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.green.shade100,
                child: Icon(Icons.phone_android, color: Colors.green.shade700),
              ),
              title: const Text('Google Pay Capture'),
              subtitle: const Text('Auto-capturing transactions'),
              trailing: PopupMenuButton<String>(
                onSelected: (value) => _handleMenuAction(context, notifier, value),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'test',
                    child: Row(
                      children: [
                        Icon(Icons.send, size: 18),
                        SizedBox(width: 8),
                        Text('Send Test Notification'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'revoke',
                    child: Row(
                      children: [
                        Icon(Icons.block, size: 18, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Revoke Device', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'clear',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 18, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Clear Configuration', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (notifier.error != null) ...[
              const SizedBox(height: 12),
              Text(notifier.error!, style: TextStyle(color: Colors.red.shade700)),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _handleMenuAction(BuildContext context, DeviceCaptureNotifier notifier, String action) async {
    switch (action) {
      case 'test':
        final sent = await notifier.sendTestNotification();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(sent ? 'Test notification sent' : 'Failed to send test')),
          );
        }
        break;
      case 'revoke':
        if (notifier.deviceId != null) {
          await notifier.revokeDeviceToken(notifier.deviceId!);
        }
        break;
      case 'clear':
        await notifier.clearCapture();
        break;
    }
  }

  Widget _buildInfoSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('How it works', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            _InfoStep(
              number: '1',
              title: 'Select a person',
              description: 'Choose which household member\'s cards to capture.',
            ),
            _InfoStep(
              number: '2',
              title: 'Grant notification access',
              description: 'Allow the app to read Google Pay notifications.',
            ),
            _InfoStep(
              number: '3',
              title: 'Auto-capture',
              description: 'Transactions appear in Card Events automatically.',
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              'Requires Google Pay app with added cards. Works with most major banks.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.value,
    required this.isPositive,
  });

  final String label;
  final String value;
  final bool isPositive;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label: $value'),
      backgroundColor: isPositive ? Colors.green.shade50 : Colors.orange.shade50,
      labelStyle: TextStyle(
        color: isPositive ? Colors.green.shade700 : Colors.orange.shade700,
        fontWeight: FontWeight.w500,
      ),
      side: BorderSide(color: isPositive ? Colors.green.shade200 : Colors.orange.shade200),
    );
  }
}

class _InfoStep extends StatelessWidget {
  const _InfoStep({
    required this.number,
    required this.title,
    required this.description,
  });

  final String number;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: AppColors.primary,
            child: Text(number, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(description, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}