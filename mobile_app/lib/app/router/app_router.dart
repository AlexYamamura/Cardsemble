import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cardsemble/theme/app_colors.dart';
import 'package:cardsemble/features/device_capture/presentation/device_capture_notifier.dart';
import 'package:cardsemble/features/device_capture/presentation/settings_step.dart';
import 'package:cardsemble/features/summary/presentation/summary_screen.dart';
import 'package:cardsemble/features/transactions/presentation/transactions_notifier.dart';
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

class _MainTabsState extends State<MainTabs> with TickerProviderStateMixin {
  late final TabController _tabController;
  late final PageController _pageController;
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
    _pageController = PageController(initialPage: _tabController.index);
    _tabController.addListener(_onTabChanged);
    _pageController.addListener(_onPageScrolled);
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
      // Single entry point for the shared transaction data so both tabs do not
      // fire duplicate multi-page fetches on startup.
      context.read<TransactionsNotifier>().loadAll();
    });
    _showFirstRunSettings();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _pageController.dispose();
    _settingsAnimationController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  /// Keeps the NavigationBar's highlighted icon in sync while the user swipes
  /// between pages, since the TabController index only settles after the swipe.
  void _onPageScrolled() {
    if (!mounted) return;
    setState(() {});
  }

  void _showTransactionsTab() {
    _tabController.animateTo(1);
    _pageController.animateToPage(
      1,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
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
        child: PageView(
          controller: _pageController,
          physics: const _SensitiveTabPhysics(),
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
      bottomNavigationBar: _AnimatedTabBar(
        tabs: _tabs,
        selectedIndex: (_pageController.hasClients ? (_pageController.page ?? 0.0) : _tabController.index.toDouble()),
        fractionalIndex: _pageController.hasClients
            ? (_pageController.page ?? _tabController.index.toDouble())
            : _tabController.index.toDouble(),
        onSelected: (index) {
          _tabController.animateTo(index);
          _pageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          );
        },
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

class _SensitiveTabPhysics extends PageScrollPhysics {
  const _SensitiveTabPhysics({super.parent});

  @override
  _SensitiveTabPhysics applyTo(ScrollPhysics? ancestor) {
    return _SensitiveTabPhysics(parent: buildParent(ancestor));
  }

  @override
  double get dragStartDistanceMotionThreshold => 6.0;

  @override
  double get minFlingVelocity => 300.0;

  @override
  SpringDescription get spring => const SpringDescription(
    mass: 1.0,
    stiffness: 300.0,
    damping: 35.0,
  );
}

// Shared metrics for the custom bottom navigation bar. The bar reserves a
// fixed-height region at the top for the icon and the sliding selection pill;
// the label sits below it.
const double _kNavBarHeight = 80.0;
const double _kNavIndicatorWidth = 64.0;
const double _kNavIndicatorHeight = 32.0;
const double _kNavIndicatorTop = 14.0;

/// A bottom navigation bar whose highlight pill tracks the actual tab the user
/// is on — including mid-swipe, where the fractional page position is used so
/// the highlight slides with the finger instead of snapping to the nearest
/// destination.
class _AnimatedTabBar extends StatefulWidget {
  const _AnimatedTabBar({
    required this.tabs,
    required this.selectedIndex,
    required this.fractionalIndex,
    required this.onSelected,
  });

  final List<_TabInfo> tabs;
  final double selectedIndex;
  final double fractionalIndex;
  final ValueChanged<int> onSelected;

  @override
  State<_AnimatedTabBar> createState() => _AnimatedTabBarState();
}

class _AnimatedTabBarState extends State<_AnimatedTabBar> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = widget.tabs.length;

    return ColoredBox(
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: SizedBox(
          // A bounded height is essential: a Scaffold bottomNavigationBar is
          // laid out with an unbounded/loose height, so an unconstrained
          // Stack would expand to the full screen and hide the body.
          height: _kNavBarHeight,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = constraints.maxWidth / n;
              // Drive the pill from the fractional page position so the
              // highlight follows the finger during a swipe and tracks a
              // programmatic tab animation.
              final left = widget.fractionalIndex * itemWidth +
                  (itemWidth - _kNavIndicatorWidth) / 2;

              return Stack(
                fit: StackFit.expand,
                children: [
                  Positioned(
                    top: _kNavIndicatorTop,
                    left: left,
                    width: _kNavIndicatorWidth,
                    height: _kNavIndicatorHeight,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (int i = 0; i < n; i++)
                        Expanded(
                          child: _Destination(
                            tab: widget.tabs[i],
                            selected: (i - widget.selectedIndex).abs() < 0.5,
                            onTap: () => widget.onSelected(i),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Destination extends StatelessWidget {
  const _Destination({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final _TabInfo tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The icon sits on top of the (primary-coloured) selection pill when
    // selected, so it uses the on-primary colour. The label sits below the
    // pill on the surface, so it uses the primary colour instead — otherwise
    // it would be invisible (light on light).
    final iconColor =
        selected ? AppColors.onPrimary : theme.colorScheme.onSurfaceVariant;
    final labelColor =
        selected ? AppColors.primary : theme.colorScheme.onSurfaceVariant;

    return InkResponse(
      onTap: onTap,
      radius: 32,
      child: Padding(
        // Reserve the same top region the selection pill occupies so the icon
        // sits centred inside the pill and the label falls below it.
        padding: const EdgeInsets.only(top: _kNavIndicatorTop),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            SizedBox(
              height: _kNavIndicatorHeight,
              child: Center(
                child: Icon(
                  selected ? tab.selectedIcon : tab.icon,
                  color: iconColor,
                  size: 24,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              tab.label,
              style: TextStyle(
                color: labelColor,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
