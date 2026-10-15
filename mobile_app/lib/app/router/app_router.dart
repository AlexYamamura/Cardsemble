import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cardsemble/theme/app_colors.dart';
import 'package:cardsemble/features/device_capture/presentation/device_capture_notifier.dart';
import 'package:cardsemble/features/device_capture/presentation/settings_step.dart';
import 'package:cardsemble/features/summary/presentation/summary_screen.dart';
import 'package:cardsemble/features/transactions/presentation/transactions_screen.dart';
import 'package:cardsemble/features/card_events/presentation/card_events_screen.dart';
import 'package:cardsemble/features/household/presentation/people_screen.dart';

class _TabInfo {
  const _TabInfo({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class MainTabs extends StatefulWidget {
  const MainTabs({super.key});

  @override
  State<MainTabs> createState() => _MainTabsState();
}

class _MainTabsState extends State<MainTabs> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final AnimationController _settingsAnimationController;
  late final Animation<double> _settingsFadeAnimation;
  late final Animation<Offset> _settingsSlideAnimation;
  bool _showSettings = false;
  bool _firstRunSettingsPending = true;
  static const _settingsReviewedKey = 'capture_settings_reviewed';

  static const List<_TabInfo> _tabs = [
    _TabInfo(
      icon: Icons.insights_outlined,
      selectedIcon: Icons.insights,
      label: 'Summary',
    ),
    _TabInfo(
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long,
      label: 'Transactions',
    ),
    _TabInfo(
      icon: Icons.notifications_none,
      selectedIcon: Icons.notifications,
      label: 'Events',
    ),
    _TabInfo(
      icon: Icons.people_outline,
      selectedIcon: Icons.people,
      label: 'People',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(_onTabChanged);
    _settingsAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _settingsFadeAnimation = CurvedAnimation(
      parent: _settingsAnimationController,
      curve: Curves.easeOutCubic,
    );
    _settingsSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _settingsAnimationController,
      curve: Curves.easeOutCubic,
    ));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final capture = context.read<DeviceCaptureNotifier>();
      capture.loadPeople();
      capture.checkStatus();
    });
    _showFirstRunSettings();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _settingsAnimationController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  void _showTransactionsTab() {
    _tabController.animateTo(1);
  }

  Future<void> _showFirstRunSettings() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final reviewed = preferences.getBool(_settingsReviewedKey) ?? false;
      if (!mounted) return;
      if (!reviewed) {
        _settingsAnimationController.forward();
      }
      setState(() {
        _firstRunSettingsPending = !reviewed;
        _showSettings = !reviewed;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _firstRunSettingsPending = false;
        _showSettings = false;
      });
    }
  }

  Future<void> _closeSettings() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_settingsReviewedKey, true);
    } catch (error) {
      // Persisting the flag is best-effort; continue closing regardless.
    }
    if (!mounted) return;
    _settingsAnimationController.reverse();
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    setState(() {
      _showSettings = false;
      _firstRunSettingsPending = false;
    });
  }

  void _openSettings() {
    setState(() => _showSettings = true);
    _settingsAnimationController.forward();
  }

  @override
  Widget build(BuildContext context) {
    if (_firstRunSettingsPending) {
      final notifier = context.watch<DeviceCaptureNotifier>();
      final canContinue = notifier.isConfigured && notifier.hasNotificationAccess;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Setup'),
          automaticallyImplyLeading: false,
        ),
        body: _buildSettingsOverlay(),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: FilledButton.icon(
              onPressed: canContinue ? _closeSettings : null,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Continue'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      );
    }

    if (_showSettings) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Close settings',
            onPressed: _closeSettings,
            icon: const Icon(Icons.arrow_back),
          ),
          title: const Text('Settings'),
        ),
        body: _buildSettingsOverlay(),
      );
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Color(0xFFDDD1BD),
              Color(0xFFD5CFC2),
            ],
          ),
        ),
        child: TabBarView(
          controller: _tabController,
          physics: const BouncingScrollPhysics(),
          children: [
            SummaryScreen(
              onShowTransactions: _showTransactionsTab,
              onOpenSettings: _openSettings,
            ),
            const TransactionsScreen(),
            const CardEventsScreen(),
            const PeopleScreen(),
          ],
        ),
      ),
      bottomNavigationBar: ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          top: false,
          child: NavigationBar(
            height: 76,
            selectedIndex: _tabController.index,
            onDestinationSelected: (index) => _tabController.animateTo(index),
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            indicatorColor: AppColors.primary,
            destinations: _tabs
                .map(
                  (tab) => NavigationDestination(
                    icon: Icon(tab.icon),
                    selectedIcon: Icon(tab.selectedIcon),
                    label: tab.label,
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsOverlay() {
    final notifier = context.watch<DeviceCaptureNotifier>();
    final theme = Theme.of(context);

    return FadeTransition(
      opacity: _settingsFadeAnimation,
      child: SlideTransition(
        position: _settingsSlideAnimation,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Auto-capture Setup',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                'Link Google Pay to automatically capture card transactions for your household.',
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 32),
              SettingsStep(
                number: '1',
                title: 'Select a person',
                description:
                    'Choose which household member\'s cards to capture.',
                icon: Icons.person_outline,
                isComplete: notifier.credentials != null,
              ),
              const SizedBox(height: 16),
              SettingsStep(
                number: '2',
                title: 'Enable capture',
                description:
                    'Create a secure device token and configure Google Pay notifications.',
                icon: Icons.phone_android,
                isComplete: notifier.isConfigured,
              ),
              const SizedBox(height: 16),
              SettingsStep(
                number: '3',
                title: 'Grant notification access',
                description:
                    'Allow Cardsemble to read Google Pay purchase notifications.',
                icon: Icons.notifications_active,
                isComplete: notifier.hasNotificationAccess,
                action: notifier.hasNotificationAccess
                    ? null
                    : TextButton(
                        onPressed: () =>
                            notifier.openNotificationAccessSettings(),
                        child: const Text('Grant Access'),
                      ),
              ),
              const SizedBox(height: 24),
              if (notifier.credentials == null) ...[
                Text('Step 1: Select Person',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: notifier.people.map((person) {
                    return FilledButton(
                      onPressed: () async {
                        final success = await notifier.createDeviceToken(person.id);
                        if (success && notifier.credentials != null) {
                          const apiUrl = 'https://creditcards-beige.vercel.app';
                          await notifier.configureCapture(apiUrl);
                        }
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: person.isDefault
                            ? theme.colorScheme.primary
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: person.isDefault
                                ? Colors.white
                                : Colors.grey.shade300,
                            child: Text(
                              person.displayName.substring(0, 1).toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                color: person.isDefault
                                    ? theme.colorScheme.primary
                                    : Colors.grey.shade600,
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
                  Text(notifier.error!,
                      style: TextStyle(color: theme.colorScheme.error)),
                ],
              ] else if (!notifier.isConfigured) ...[
                Text('Step 2: Enable Capture',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: notifier.isLoading
                      ? null
                      : () async {
                          const apiUrl = 'https://creditcards-beige.vercel.app';
                          await notifier.configureCapture(apiUrl);
                        },
                  icon: notifier.isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Icon(Icons.play_arrow),
                  label: Text(notifier.isLoading
                      ? 'Configuring...'
                      : 'Enable Google Pay Capture'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                  ),
                ),
                if (notifier.error != null) ...[
                  const SizedBox(height: 16),
                  Text(notifier.error!,
                      style: TextStyle(color: theme.colorScheme.error)),
                ],
              ] else if (!notifier.hasNotificationAccess) ...[
                Text('Step 3: Grant Notification Access',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => notifier.openNotificationAccessSettings(),
                  icon: const Icon(Icons.notifications_active),
                  label: const Text('Open Notification Access Settings'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                  ),
                ),
                const SizedBox(height: 8),
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
              ] else ...[
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
        ),
      ),
    );
  }
}
