import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cardsemble/theme/app_colors.dart';
import 'package:cardsemble/features/device_capture/presentation/device_capture_notifier.dart';
import 'package:cardsemble/features/device_capture/presentation/capture_settings_screen.dart';
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

class _MainTabsState extends State<MainTabs>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabController;
  late final PageController _pageController;
  late final ValueNotifier<int> _tabIndexNotifier;
  int _activeTabIndex = 0;
  // Navigator keys for each tab
  final GlobalKey<NavigatorState> _summaryNavigatorKey =
      GlobalKey<NavigatorState>();
  final GlobalKey<NavigatorState> _transactionsNavigatorKey =
      GlobalKey<NavigatorState>();
  final GlobalKey<NavigatorState> _eventsNavigatorKey =
      GlobalKey<NavigatorState>();
  final GlobalKey<NavigatorState> _peopleNavigatorKey =
      GlobalKey<NavigatorState>();
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
    _tabIndexNotifier = ValueNotifier<int>(_tabController.index);
    _tabController.addListener(_onTabChanged);
    _pageController.addListener(_onPageScrolled);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final capture = context.read<DeviceCaptureNotifier>();
      capture.loadPeople();
      capture.checkStatus();
      // Single entry point for the shared transaction data so both tabs do not
      // fire duplicate multi-page fetches on startup.
      context.read<TransactionsNotifier>().loadAll();
      // Check if we need to show first-run settings
      _checkFirstRunSettings();
    });
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _pageController.dispose();
    _tabIndexNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      // User returned from notification access settings; re-check status.
      context.read<DeviceCaptureNotifier>().checkStatus();
    }
  }

  void _onPageScrolled() {
    if (!mounted || !_pageController.hasClients) return;
    // Update active tab index based on page position
    if ((_pageController.page ?? 0).round() != _activeTabIndex) {
      setState(() => _activeTabIndex = (_pageController.page ?? 0).round());
    }
  }

  void _onTabChanged() {
    if (!mounted) return;
    _tabIndexNotifier.value = _tabController.index;
    // Update page controller when tab controller changes (e.g., via programmatic navigation)
    if (!_pageController.hasClients) return;
    if (_tabController.index != _pageController.page) {
      _pageController.animateToPage(
        _tabController.index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _showTransactionsTab() {
    if (!mounted) return;
    _tabController.animateTo(1);
    _pageController.animateToPage(
      1,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _checkFirstRunSettings() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final reviewed = preferences.getBool(_settingsReviewedKey) ?? false;
      if (!mounted) return;
      if (!reviewed) {
        // Show first-run setup as a modal route
        await Navigator.of(context, rootNavigator: true).push<void>(
          PageRouteBuilder<void>(
            transitionDuration: const Duration(milliseconds: 300),
            reverseTransitionDuration: const Duration(milliseconds: 250),
            pageBuilder: (_, __, ___) =>
                const CaptureSettingsScreen(firstRun: true),
            transitionsBuilder: (_, animation, __, child) {
              final curved = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              );
              return FadeTransition(
                opacity: curved,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.1),
                    end: Offset.zero,
                  ).animate(curved),
                  child: child,
                ),
              );
            },
          ),
        );
      }
    } catch (error) {
      // Ignore errors during settings check
    }
  }

  Future<void> _openSettings() async {
    if (!mounted) return;
    await Navigator.of(context, rootNavigator: true).push<void>(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (_, __, ___) => const CaptureSettingsScreen(firstRun: false),
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.1),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  Widget _buildTabNavigator({
    required int index,
    required GlobalKey<NavigatorState> navigatorKey,
    required WidgetBuilder rootBuilder,
  }) {
    return _KeepAliveTab(
      child: NavigatorPopHandler<Object?>(
        enabled: _activeTabIndex == index,
        onPopWithResult: (_) {
          // All handlers can be invoked when the active one blocks
          // the root pop. Only the active tab may pop its own stack.
          if (_activeTabIndex != index) return;
          navigatorKey.currentState?.maybePop();
        },
        child: Navigator(
          key: navigatorKey,
          onGenerateRoute: (settings) => MaterialPageRoute<Object?>(
            settings: settings,
            builder: rootBuilder,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
          onPageChanged: (index) {
            if (_activeTabIndex != index) {
              setState(() => _activeTabIndex = index);
            }
            if (_tabController.index != index) {
              _tabController.index = index;
            }
          },
          children: [
            _buildTabNavigator(
              index: 0,
              navigatorKey: _summaryNavigatorKey,
              rootBuilder: (_) => SummaryScreen(
                onShowTransactions: _showTransactionsTab,
                onOpenSettings: _openSettings,
              ),
            ),
            _buildTabNavigator(
              index: 1,
              navigatorKey: _transactionsNavigatorKey,
              rootBuilder: (_) => const TransactionsScreen(),
            ),
            _buildTabNavigator(
              index: 2,
              navigatorKey: _eventsNavigatorKey,
              rootBuilder: (_) => const CardEventsScreen(),
            ),
            _buildTabNavigator(
              index: 3,
              navigatorKey: _peopleNavigatorKey,
              rootBuilder: (_) => const PeopleScreen(),
            ),
          ],
        ),
      ),
       bottomNavigationBar: ValueListenableBuilder<int>(
         valueListenable: _tabIndexNotifier,
         builder: (context, value, _) => _AnimatedTabBar(
           tabs: _tabs,
           selectedIndex: value.toDouble(),
           fractionalIndex: _pageController.hasClients
               ? _pageController.page ?? value.toDouble()
               : value.toDouble(),
           onSelected: _selectTab,
         ),
       ),
    );
  }

  void _selectTab(int index) {
    _tabController.animateTo(index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }
}

// We need to define _KeepAliveTab here since it's used above.
class _KeepAliveTab extends StatefulWidget {
  const _KeepAliveTab({required this.child});

  final Widget child;

  @override
  State<_KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<_KeepAliveTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
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
