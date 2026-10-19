import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cardsemble/theme/app_colors.dart';
import 'package:cardsemble/features/device_capture/presentation/device_capture_notifier.dart';
import 'package:cardsemble/features/device_capture/presentation/settings_step.dart';
import 'package:cardsemble/features/household/domain/entities/household.dart';
import 'package:cardsemble/features/auth/presentation/auth_notifier.dart';

class CaptureSettingsScreen extends StatefulWidget {
  const CaptureSettingsScreen({super.key, required this.firstRun});

  final bool firstRun;

  @override
  State<CaptureSettingsScreen> createState() => _CaptureSettingsScreenState();
}

class _CaptureSettingsScreenState extends State<CaptureSettingsScreen> {
  @override
  void initState() {
    super.initState();
    // Check if we need to auto-configure step 1 after the widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final notifier = context.read<DeviceCaptureNotifier>();
      final auth = context.read<AuthNotifier>();
      final defaultPerson = notifier.people.isNotEmpty
          ? notifier.people.firstWhere(
              (p) => p.id == auth.userSession?.userId,
              orElse: () => notifier.people.firstWhere(
                (p) => p.isDefault,
                orElse: () => notifier.people.first,
              ),
            )
          : null;

      if (defaultPerson != null &&
          notifier.credentials == null &&
          !notifier.isLoading &&
          !notifier.step1AutoConfigured) {
        notifier.setStep1AutoConfigured(true);
        _autoConfigureStep1(defaultPerson);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // For first run, we want to prevent going back until setup is complete.
    // We'll use PopScope to control this.
    return PopScope(
      canPop: !widget.firstRun,
      onPopInvokedWithResult: (didPop, result) {
        if (widget.firstRun && !didPop) {
          // Prevent going back during first run setup.
          // We just prevent the pop.
          return;
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.cream,
        appBar: AppBar(
          leading: widget.firstRun
              ? null
              : IconButton(
                  tooltip: 'Close settings',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                ),
          title: Text(widget.firstRun ? 'Setup' : 'Settings'),
        ),
        body: _buildSettingsOverlay(),
      ),
    );
  }

  Widget _buildSettingsOverlay() {
    final notifier = context.watch<DeviceCaptureNotifier>();
    final auth = context.watch<AuthNotifier>();
    final theme = Theme.of(context);

    // Find the household member matching the logged-in user for auto step 1.
    final authUserId = auth.userSession?.userId;
    final defaultPerson = notifier.people.isNotEmpty
        ? notifier.people.firstWhere(
            (p) => p.id == authUserId,
            orElse: () => notifier.people.firstWhere(
              (p) => p.isDefault,
              orElse: () => notifier.people.first,
            ),
          )
        : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Auto-capture Setup',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Link Google Pay to automatically capture card transactions for your household.',
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 32),

          // Step 1: Your username — auto-assigned from login, no selection needed.
          SettingsStep(
            number: '1',
            title: 'Your username',
            description: defaultPerson != null
                ? 'Using ${defaultPerson.displayName} as your capture identity.'
                : 'No household member found for your account.',
            icon: Icons.person_outline,
            isComplete: defaultPerson != null && notifier.credentials != null,
          ),
          const SizedBox(height: 16),

          // Step 1 content — auto-configure or show status.
          if (defaultPerson != null && notifier.credentials == null) ...[
            if (notifier.isLoading) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('Setting up your account...',
                      style: theme.textTheme.bodyMedium),
                ],
              ),
            ] else ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _autoConfigureStep1(defaultPerson),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Set up capture'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56),
                ),
              ),
            ],
            if (notifier.error != null) ...[
              const SizedBox(height: 16),
              Text(notifier.error!,
                  style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],

          const SizedBox(height: 24),

          // Step 2: Grant notification access.
          SettingsStep(
            number: '2',
            title: 'Enable notifications',
            description:
                'Allow Cardsemble to read Google Pay purchase notifications.',
            icon: Icons.notifications_active,
            isComplete: notifier.hasNotificationAccess,
            action: notifier.hasNotificationAccess
                ? null
                : FilledButton.icon(
                    onPressed: () =>
                        notifier.openNotificationAccessSettings(),
                    icon: const Icon(Icons.notifications_active),
                    label: const Text('Turn on Notifications'),
                  ),
          ),
          const SizedBox(height: 16),

          if (!notifier.hasNotificationAccess &&
              notifier.credentials != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => notifier.sendTestNotification(),
              icon: const Icon(Icons.send),
              label: const Text('Send Test Notification'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
              ),
            ),
            if (notifier.error != null) ...[
              const SizedBox(height: 16),
              Text(notifier.error!,
                  style: TextStyle(color: theme.colorScheme.error)),
            ],
          ] else if (notifier.isConfigured && notifier.hasNotificationAccess) ...[
            Card(
              color: Colors.green.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.check_circle,
                        color: Colors.green.shade700, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Capture is active!',
                              style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green.shade700)),
                          const SizedBox(height: 4),
                          Text(
                              'Google Pay transactions will now appear automatically in Card Events.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                  color: Colors.green.shade700)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () async {
                final deviceId = notifier.deviceId;
                if (deviceId != null) {
                  await notifier.revokeDeviceToken(deviceId);
                }
              },
              icon: const Icon(Icons.block, color: Colors.red),
              label: const Text('Disable Capture',
                  style: TextStyle(color: Colors.red)),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                side: const BorderSide(color: Colors.red, width: 2),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _autoConfigureStep1(HouseholdPerson person) async {
    final capture = context.read<DeviceCaptureNotifier>();
    final success = await capture.createDeviceToken(person.id);
    if (success && capture.credentials != null && mounted) {
      const apiUrl = 'https://creditcards-beige.vercel.app';
      await capture.configureCapture(apiUrl);
    }
  }
}