import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:plaid_flutter/plaid_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:android_intent_plus/android_intent.dart';

import 'ledger_api.dart';
import 'google_pay_capture.dart';

const _pendingOrange = Color(0xFFB45309); // Darker orange (amber-700)

class LedgerScreen extends StatefulWidget {
  const LedgerScreen({required this.api, required this.onSignOut, super.key});

  final LedgerApi api;
  final Future<void> Function() onSignOut;

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final GooglePayCapture _googlePayCapture = GooglePayCapture();
  StreamSubscription<LinkSuccess>? _plaidSuccessSubscription;
  StreamSubscription<LinkExit>? _plaidExitSubscription;
  int _selectedTab = 0;
  late DateTimeRange _summaryRange;
  String? _drilldownAccountId;
  String? _drilldownPersonId;
  String? _filterAccountId;
  String? _filterPersonId;
  DateTimeRange? _filterDateRange;
  String? _filterStatus;
  bool _loading = true;
  bool _addingPerson = false;
  bool _showSettings = false;
  bool _firstRunSettingsPending = true;
  bool _captureConfigured = false;
  bool _notificationAccess = false;
  bool _captureWorking = false;
  bool _linkingPlaid = false;
  String? _error;
  String? _captureError;
  String? _capturePersonId;
  List<HouseholdPerson> _people = const [];
  List<CardTransaction> _transactions = const [];
  List<CardEventRecord> _events = const [];
  List<PlaidConnection> _plaidConnections = const [];
  StatementCycleSummary? _statementSummary;
  final Set<String> _updatingTransactions = {};
  static const _settingsReviewedKey = 'capture_settings_reviewed';
  late final PageController _pageController;
  late final AnimationController _settingsAnimationController;
  late final Animation<double> _settingsFadeAnimation;
  late final Animation<Offset> _settingsSlideAnimation;

  @override
  void initState() {
    super.initState();
    final today = DateUtils.dateOnly(DateTime.now());
    _summaryRange = DateTimeRange(
      start: DateTime(today.year, today.month),
      end: today,
    );
    WidgetsBinding.instance.addObserver(this);
    _plaidSuccessSubscription = PlaidLink.onSuccess.listen(_onPlaidSuccess);
    _plaidExitSubscription = PlaidLink.onExit.listen(_onPlaidExit);
    _pageController = PageController(initialPage: _selectedTab);
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
    _firstRunSettingsPending = true;
    _refresh();
    _refreshCaptureStatus();
    _showFirstRunSettings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _plaidSuccessSubscription?.cancel();
    _plaidExitSubscription?.cancel();
    _pageController.dispose();
    _settingsAnimationController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshCaptureStatus();
  }

  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

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
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _firstRunSettingsPending = false;
        _error = 'Could not load app preferences: $error';
      });
    }
  }
  

Future<void> _closeSettings() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_settingsReviewedKey, true);
      if (mounted) {
        _settingsAnimationController.reverse();
        await Future.delayed(const Duration(milliseconds: 250));
        setState(() {
          _showSettings = false;
          _firstRunSettingsPending = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Could not save settings: $error';
          _showSettings = false;
          _firstRunSettingsPending = false;
        });
      }
    }
  }

  Future<void> _openSettings() async {
    setState(() => _showSettings = true);
    _settingsAnimationController.forward();
  }

  Future<String?> _showPersonSelector({
    required BuildContext context,
    required String title,
    String? currentPersonId,
    required List<HouseholdPerson> people,
    required ValueChanged<String?> onSelected,
  }) async {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _PersonSelectorSheet(
        title: title,
        currentPersonId: currentPersonId,
        people: people,
        onSelected: onSelected,
      ),
    );
  }

  Future<void> _refreshCaptureStatus() async {
    if (!_isAndroid) return;
    try {
      final configured = await _googlePayCapture.isConfigured();
      final access = await _googlePayCapture.hasNotificationAccess();
      if (!mounted) return;
      setState(() {
        _captureConfigured = configured;
        _notificationAccess = access;
        _captureError = null;
      });
    } catch (error) {
      if (mounted) setState(() => _captureError = error.toString());
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      late List<HouseholdMember> householdMembers;
      late List<HouseholdPerson> householdPeople;
      late List<CardTransaction> transactions;
      late List<CardEventRecord> events;
      late List<PlaidConnection> plaidConnections;
      late StatementCycleSummary summary;
      await Future.wait<void>([
        widget.api.loadHouseholdMembers().then<void>((value) => householdMembers = value),
        widget.api.loadHouseholdPeople().then<void>((value) => householdPeople = value),
        widget.api.loadTransactions().then<void>(
          (value) => transactions = value,
        ),
        widget.api.loadCardEvents().then<void>((value) => events = value),
        widget.api.loadPlaidConnections().then<void>(
          (value) => plaidConnections = value,
        ),
        widget.api.loadStatementCycles().then<void>((value) => summary = value),
      ]);
      if (!mounted) return;
      // Combine household members and people for assignment dropdown
      final allPeople = <HouseholdPerson>[
        ...householdPeople,
        ...householdMembers.map((m) => HouseholdPerson(
          id: m.userId,
          displayName: m.userId, // Will be resolved via user lookup
          isDefault: false,
        )),
      ];
      setState(() {
        _people = allPeople;
        _transactions = transactions;
        _events = events;
        _plaidConnections = plaidConnections;
        _statementSummary = summary;
        _capturePersonId ??= allPeople
            .where((person) => person.isDefault)
            .firstOrNull
            ?.id;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _startPlaidLink() async {
    setState(() {
      _linkingPlaid = true;
      _error = null;
    });
    try {
      final token = await widget.api.createPlaidLinkToken(
        _isAndroid ? 'android' : 'ios',
      );
      await PlaidLink.create(
        configuration: LinkTokenConfiguration(token: token),
      );
      await PlaidLink.open();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _linkingPlaid = false;
        _error = 'Could not open Plaid Link: $error';
      });
    }
  }

  Future<void> _onPlaidSuccess(LinkSuccess event) async {
    try {
      await widget.api.exchangePlaidPublicToken(
        publicToken: event.publicToken,
        institutionId: event.metadata.institution?.id,
        institutionName: event.metadata.institution?.name,
        platform: _isAndroid ? 'android' : 'ios',
      );
      if (!mounted) return;
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${event.metadata.institution?.name ?? 'Institution'} connected.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not save Plaid connection: $error');
      }
    } finally {
      if (mounted) setState(() => _linkingPlaid = false);
    }
  }

  void _onPlaidExit(LinkExit event) {
    if (!mounted) return;
    setState(() {
      _linkingPlaid = false;
      if (event.error != null) {
        _error =
            event.error!.displayMessage ??
            'Plaid could not complete the connection.';
      }
    });
  }

  Future<void> _assign(CardTransaction transaction, String? personId) async {
    setState(() {
      _updatingTransactions.add(transaction.id);
      _error = null;
    });
    try {
      await widget.api.assignTransaction(transaction.id, personId);
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transaction assignment updated.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _updatingTransactions.remove(transaction.id));
      }
    }
  }

  Future<void> _editCreditCardName(_SummaryRow row) async {
    final accountId = row.accountId;
    if (accountId == null) return;
    var enteredCardName = row.displayName ?? '';
    final plaidNames = [row.officialName, row.plaidName]
        .whereType<String>()
        .map((name) => name.replaceAll('\uFFFD', '').trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final enteredName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Name this card'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (plaidNames.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text('Plaid names: ${plaidNames.join(' · ')}'),
              ),
            TextFormField(
              key: const ValueKey('credit-card-display-name-field'),
              initialValue: enteredCardName,
              onChanged: (value) => enteredCardName = value,
              autofocus: true,
              maxLength: 100,
              decoration: const InputDecoration(
                labelText: 'Card name',
                hintText: 'e.g. Chase Freedom Unlimited',
                border: OutlineInputBorder(),
              ),
            ),
            if (row.accountMask?.isNotEmpty == true)
              Text('Account ending in ${row.accountMask}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          if (row.displayName != null)
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, ''),
              child: const Text('Reset'),
            ),
          FilledButton(
            onPressed: () {
              final value = enteredCardName.trim();
              if (value.isEmpty) return;
              Navigator.pop(dialogContext, value);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (enteredName == null || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.api.updateCreditCardDisplayName(
        accountId,
        enteredName.isEmpty ? null : enteredName,
      );
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enteredName.isEmpty ? 'Card name reset.' : 'Card name updated.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addPerson() async {
    final displayName = await showDialog<String>(
      context: context,
      builder: (context) => const _AddPersonDialog(),
    );
    if (displayName == null) return;

    setState(() {
      _addingPerson = true;
      _error = null;
    });
    try {
      await widget.api.createHouseholdPerson(displayName);
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$displayName added as household person.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _addingPerson = false);
    }
  }

  bool _scanningQr = false;

  Future<void> _scanQrToAddPerson() async {
    setState(() => _scanningQr = true);
    try {
      final result = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        builder: (context) => _QrScannerSheet(onScan: (code) => Navigator.pop(context, code)),
      );
      if (result == null || !mounted) return;

      // Parse the QR code - expected format: invite code directly or cardsemble://invite?code=xxx
      String inviteCode = result.trim();
      final uri = Uri.tryParse(result);
      if (uri != null && uri.scheme == 'cardsemble' && uri.host == 'invite') {
        inviteCode = uri.queryParameters['code'] ?? uri.queryParameters['token'] ?? '';
      }

      if (inviteCode.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid QR code. Please scan a Cardsemble invite code.')),
        );
        return;
      }

      setState(() => _addingPerson = true);
      try {
        await widget.api.joinHouseholdByInviteCode(inviteCode);
        await _refresh();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Household member added successfully!')),
        );
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add member: $error')),
        );
      } finally {
        if (mounted) setState(() => _addingPerson = false);
      }
    } finally {
      if (mounted) setState(() => _scanningQr = false);
    }
  }

  Future<void> _enableGooglePayCapture() async {
    final personId = _capturePersonId;
    if (personId == null) {
      setState(() => _captureError = 'Add a household member before setup.');
      return;
    }
    setState(() {
      _captureWorking = true;
      _captureError = null;
    });
    DeviceCaptureCredentials? credentials;
    try {
      credentials = await widget.api.createGooglePayDeviceToken(personId);
      await _googlePayCapture.configure(
        apiUrl: widget.api.apiBaseUrl,
        deviceToken: credentials.token,
        deviceId: credentials.id,
      );
      await _refreshCaptureStatus();
    } catch (error) {
      if (credentials != null) {
        try {
          await widget.api.revokeDeviceToken(credentials.id);
        } catch (revokeError) {
          if (mounted) {
            setState(() {
              _captureError = '$error Device-key cleanup failed: $revokeError';
            });
          }
          return;
        }
      }
      if (mounted) setState(() => _captureError = error.toString());
    } finally {
      if (mounted) setState(() => _captureWorking = false);
    }
  }

  Future<void> _openNotificationAccessSettings() async {
    try {
      await _googlePayCapture.openNotificationAccessSettings();
    } catch (error) {
      if (mounted) setState(() => _captureError = error.toString());
    }
  }

  Future<void> _sendTestNotification() async {
    try {
      final granted = await _googlePayCapture.sendTestNotification();
      if (granted == false) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please grant notification permission, then tap the button again.')),
        );
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Test notification sent. Check the Card Events tab.')),
      );
    } catch (error) {
      if (mounted) setState(() => _captureError = error.toString());
    }
  }

  Future<void> _disableGooglePayCapture() async {
    setState(() {
      _captureWorking = true;
      _captureError = null;
    });
    try {
      final deviceId = await _googlePayCapture.deviceId();
      if (deviceId != null) await widget.api.revokeDeviceToken(deviceId);
      await _googlePayCapture.clear();
      await _refreshCaptureStatus();
    } catch (error) {
      if (mounted) setState(() => _captureError = error.toString());
    } finally {
      if (mounted) setState(() => _captureWorking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titles = [
      'Monthly summary',
      'Transactions',
      'Captured events',
      'People',
    ];
    final showingFirstRunSettings = _firstRunSettingsPending;

    // On first run, show settings as full-screen content, not overlay
    if (showingFirstRunSettings) {
      final canContinue = _captureConfigured && _notificationAccess;
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) {
            _closeSettings();
          }
        },
        child: Scaffold(
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
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Settings opened from app bar - show as full screen
    if (_showSettings) {
      return PopScope(
        canPop: false,
onPopInvokedWithResult: (didPop, result) {
          if (!didPop) {
            _closeSettings();
          }
        },
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Close settings',
              onPressed: _closeSettings,
              icon: const Icon(Icons.arrow_back),
            ),
            title: const Text('Settings'),
          ),
          body: _buildSettingsOverlay(),
        ),
      );
    }

    return PopScope(
      canPop: true,
      child: Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -0.1),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: Text(
            titles[_selectedTab],
            key: ValueKey(_selectedTab),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            tooltip: 'Account',
            onSelected: (value) async {
              if (value != 'sign-out') return;
              try {
                await widget.onSignOut();
              } catch (error) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Could not sign out: $error')),
                );
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'sign-out', child: Text('Sign out')),
            ],
          ),
        ],
      ),
      body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Color(0xFFDDD1BD), // Warm beige
                Color(0xFFD5CFC2), // Mushroom
              ],
            ),
          ),
          child: PageView(
              controller: _pageController,
              physics: _SensitivePageScrollPhysics(),
              onPageChanged: (index) {
                setState(() => _selectedTab = index);
              },
              children: [
                _buildTabContent(0),
                _buildTabContent(1),
                _buildTabContent(2),
                _buildTabContent(3),
              ],
            ),
        ),
       bottomNavigationBar: NavigationBar(
           height: 76,
           labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
           selectedIndex: _selectedTab,
           onDestinationSelected: (index) {
             _pageController.animateToPage(
               index,
               duration: const Duration(milliseconds: 300),
               curve: Curves.easeOutCubic,
             );
           },
           indicatorColor: Theme.of(context).colorScheme.primary,
           destinations: const [
            NavigationDestination(
              icon: Icon(Icons.insights_outlined),
              selectedIcon: Icon(Icons.insights),
              label: 'Summary',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'Transactions',
            ),
            NavigationDestination(
              icon: Icon(Icons.notifications_none),
              selectedIcon: Icon(Icons.notifications),
              label: 'Events',
            ),
            NavigationDestination(
              icon: Icon(Icons.people_outline),
              selectedIcon: Icon(Icons.people),
              label: 'People',
            ),
          ],
        ),
    )
  );
  }

  Widget _buildSettingsOverlay() {
    return AnimatedBuilder(
      animation: _settingsAnimationController,
      builder: (context, child) {
        return FadeTransition(
          opacity: _settingsFadeAnimation,
          child: SlideTransition(
            position: _settingsSlideAnimation,
            child: child!,
          ),
        );
      },
      child: SafeArea(
        bottom: true,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              if (_error != null) _errorCard(_error!),
              ..._captureContent(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent(int tabIndex) {
    if (_loading &&
        _people.isEmpty &&
        _transactions.isEmpty &&
        _events.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_people.isEmpty &&
        _transactions.isEmpty &&
        _events.isEmpty &&
        tabIndex != 0) {
      return _emptyOrError();
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (_error != null) _errorCard(_error!),
          if (tabIndex == 0) ..._summaryContent(),
          if (tabIndex == 1) ..._transactionContent(),
          if (tabIndex == 2) ..._eventContent(),
          if (tabIndex == 3) ..._peopleContent(),
        ],
      ),
    );
  }

  List<Widget> _transactionContent() {
    final personNames = {
      for (final person in _people) person.id: person.displayName,
    };
    final accountsById = <String, StatementAccount>{
      for (final account in _statementSummary?.accounts ?? const [])
        account.accountId: account,
    };
    for (final transaction in _transactions) {
      final accountId = transaction.accountId;
      if (accountId == null || accountsById.containsKey(accountId)) continue;
      accountsById[accountId] = StatementAccount(
        accountId: accountId,
        accountName: transaction.accountName ?? 'Credit card',
        displayName: transaction.displayName,
        plaidName: transaction.plaidName,
        officialName: transaction.officialName,
        mask: transaction.accountMask,
      );
    }

    final effectiveAccountId = _drilldownAccountId ?? _filterAccountId;
    final effectivePersonId = _drilldownPersonId ?? _filterPersonId;
    final effectiveStatus = _filterStatus;

    final drilldownTransactions = _transactions
        .where((transaction) {
          final date = DateTime.tryParse(transaction.date ?? '');
          final day = date == null ? null : DateUtils.dateOnly(date);
          final accountMatches =
              effectiveAccountId == null || transaction.accountId == effectiveAccountId;
          final personMatches =
              effectivePersonId == null ||
              (transaction.assignedPersonId ??
                      _people
                          .where((person) => person.isDefault)
                          .firstOrNull
                          ?.id) ==
                  effectivePersonId;
          final dateMatches =
              day != null &&
              (_filterDateRange == null ||
                  (day.compareTo(_filterDateRange!.start) >= 0 &&
                      day.compareTo(_filterDateRange!.end) <= 0)) &&
              (double.tryParse(transaction.amount) ?? 0) > 0 &&
              transaction.transactionCode?.toLowerCase() != 'payment';
          final statusMatches = effectiveStatus == null ||
              (effectiveStatus == 'pending' && transaction.pending) ||
              (effectiveStatus == 'approved' && !transaction.pending);
          return accountMatches && personMatches && dateMatches && statusMatches;
        })
        .toList(growable: false);

    final selectedAccount = accountsById[effectiveAccountId];
    final selectedPerson = _people
        .where((person) => person.id == effectivePersonId)
        .firstOrNull;

    final hasActiveFilters = effectiveAccountId != null ||
        effectivePersonId != null ||
        _filterDateRange != null ||
        _filterStatus != null;

    // Calculate filtered total for PAY button
    double filteredTotal = 0;
    String filteredCurrency = 'USD';
    for (final tx in drilldownTransactions) {
      final amount = double.tryParse(tx.amount) ?? 0;
      if (amount > 0) {
        filteredTotal += amount;
        filteredCurrency = tx.currency;
      }
    }

    return [
      _StatementSummaryCard(summary: _statementSummary),
      if (filteredTotal > 0) ...[
        _PayButton(
          amount: filteredTotal,
          currency: filteredCurrency,
          onTap: () => _showPayActionSheet(context, filteredTotal, filteredCurrency),
        ),
        const SizedBox(height: 12),
      ],
      _TransactionFilterBar(
        accounts: accountsById.values.toList(),
        people: _people,
        selectedAccountId: effectiveAccountId ?? '__all__',
        selectedPersonId: effectivePersonId ?? '__everyone__',
        selectedDateRange: _filterDateRange,
        selectedStatus: effectiveStatus ?? '__all__',
        onAccountChanged: (id) => setState(() {
          _filterAccountId = id == '__all__' ? null : id;
          if (id == '__all__' || id == null) _drilldownAccountId = null;
        }),
        onPersonChanged: (id) => setState(() {
          _filterPersonId = id == '__everyone__' ? null : id;
          if (id == '__everyone__' || id == null) _drilldownPersonId = null;
        }),
        onDateRangeChanged: (range) => setState(() => _filterDateRange = range),
        onStatusChanged: (status) => setState(() {
          _filterStatus = status == '__all__' ? null : status;
        }),
        onClearAll: () => setState(() {
          _filterAccountId = null;
          _filterPersonId = null;
          _filterDateRange = null;
          _filterStatus = null;
          _drilldownAccountId = null;
          _drilldownPersonId = null;
        }),
      ),
      if (hasActiveFilters) ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (effectiveAccountId != null)
              _FilterChip(
                label: selectedAccount?.accountName ?? 'Card',
                onRemove: () => setState(() {
                  if (_drilldownAccountId != null) {
                    _drilldownAccountId = null;
                  } else {
                    _filterAccountId = null;
                  }
                }),
              ),
            if (effectivePersonId != null)
              _FilterChip(
                label: selectedPerson?.displayName ?? 'Person',
                onRemove: () => setState(() {
                  if (_drilldownPersonId != null) {
                    _drilldownPersonId = null;
                  } else {
                    _filterPersonId = null;
                  }
                }),
              ),
            if (_filterDateRange != null)
              _FilterChip(
                label: _rangeLabel(_filterDateRange!),
                onRemove: () => setState(() => _filterDateRange = null),
              ),
            if (_filterStatus != null)
              _FilterChip(
                label: _filterStatus == 'pending' ? 'Pending' : 'Approved',
                onRemove: () => setState(() => _filterStatus = null),
              ),
          ],
        ),
      ],
      const SizedBox(height: 8),
      if (drilldownTransactions.isEmpty)
        _emptyCard(
          _transactions.isEmpty
              ? 'No Plaid transactions have been synced yet.'
              : 'No transactions match the current filters.',
        )
      else
        ...drilldownTransactions.map(
          (transaction) => _TransactionCard(
            transaction: transaction,
            people: _people,
            personNames: personNames,
            updating: _updatingTransactions.contains(transaction.id),
            onAssign: (personId) => _assign(transaction, personId),
            onOpenAssigneePicker: () => _showPersonSelector(
              context: context,
              title: 'Assign transaction to',
              currentPersonId: transaction.assignmentSource == 'default'
                  ? null
                  : transaction.assignedPersonId,
              people: _people,
              onSelected: (personId) => _assign(transaction, personId),
            ),
          ),
        ),
    ];
  }

  List<Widget> _summaryContent() {
    final quickMonths = _quickMonths();
    final included = _transactions
        .where((transaction) {
          final date = DateTime.tryParse(transaction.date ?? '');
          if (date == null) return false;
          final day = DateUtils.dateOnly(date);
          final code = transaction.transactionCode?.toLowerCase();
          final amount = double.tryParse(transaction.amount);
          return !transaction.pending &&
              day.compareTo(_summaryRange.start) >= 0 &&
              day.compareTo(_summaryRange.end) <= 0 &&
              amount != null &&
              amount > 0 &&
              code != 'payment';
        })
        .toList(growable: false);

    final totalsByCurrency = <String, double>{};
    final totalsByCard = <String, double>{};
    final currenciesByCard = <String, String>{};
    final totalsByPersonAndCurrency = <String, double>{};
    final accountsById = <String, StatementAccount>{
      for (final account in _statementSummary?.accounts ?? const [])
        account.accountId: account,
    };
    for (final transaction in _transactions) {
      final accountId = transaction.accountId;
      if (accountId == null || accountsById.containsKey(accountId)) continue;
      accountsById[accountId] = StatementAccount(
        accountId: accountId,
        accountName: transaction.accountName ?? 'Credit card',
        displayName: transaction.displayName,
        plaidName: transaction.plaidName,
        officialName: transaction.officialName,
        mask: transaction.accountMask,
      );
    }
    final accountNames = {
      for (final account in accountsById.values)
        account.accountId: account.accountName,
    };
    final peopleById = {for (final person in _people) person.id: person};
    final primaryId = _people
        .where((person) => person.isDefault)
        .firstOrNull
        ?.id;

    for (final transaction in included) {
      final amount = double.parse(transaction.amount);
      final currency = transaction.currency;
      totalsByCurrency.update(
        currency,
        (total) => total + amount,
        ifAbsent: () => amount,
      );

      final cardId = transaction.accountId ?? 'unknown-card';
      final cardKey = '$cardId|$currency';
      totalsByCard.update(
        cardKey,
        (total) => total + amount,
        ifAbsent: () => amount,
      );
      currenciesByCard[cardKey] = currency;

      final personId = transaction.assignedPersonId ?? primaryId;
      final personKey = '${personId ?? 'unassigned'}|$currency';
      totalsByPersonAndCurrency.update(
        personKey,
        (total) => total + amount,
        ifAbsent: () => amount,
      );
    }

    final accountLabel = <String, String>{};
    for (final key in totalsByCard.keys) {
      final accountId = key.split('|').first;
      accountLabel[key] =
          accountNames[accountId] ??
          (accountId == 'unknown-card' ? 'Card name unavailable' : 'Card');
    }

return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Household spending',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _rangeLabel(_summaryRange),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              if (totalsByCurrency.isEmpty)
                Text(
                  'No posted card charges in this date range.',
                  style: Theme.of(context).textTheme.titleMedium,
                )
              else
                ...totalsByCurrency.entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      '${_currencySymbol(entry.key)} ${_money(entry.value.toStringAsFixed(2))}',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                '${included.length} posted charge${included.length == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
FilledButton.icon(
        onPressed: _loading ? null : _chooseSummaryRange,
        icon: const Icon(Icons.date_range),
        label: const Text('Choose date range'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      const SizedBox(height: 4),
      SizedBox(
        height: 48,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: quickMonths.length,
          separatorBuilder: (context, index) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final month = quickMonths[index];
            final isSelected = _rangeIsMonth(month);
            return FilterChip(
              key: ValueKey('quick-month-${month.year}-${month.month}'),
              label: Text(_monthLabel(month)),
              selected: isSelected,
              onSelected: _loading ? null : (_) => _selectMonth(month),
              selectedColor: Theme.of(context).colorScheme.primary,
              checkmarkColor: Colors.white,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Theme.of(context).colorScheme.primary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
              side: BorderSide(color: Theme.of(context).colorScheme.primary),
              backgroundColor: Colors.white,
            );
          },
        ),
      ),
      const SizedBox(height: 12),
      _SummaryBreakdownCard(
        title: 'By credit card',
        emptyMessage: 'No card charges in this period.',
        onEditRow: _editCreditCardName,
        onRowTap: (row) {
          if (row.accountId == null) return;
          setState(() {
            _drilldownAccountId = row.accountId;
            _drilldownPersonId = null;
            _filterDateRange = _summaryRange;
          });
          _pageController.animateToPage(
            1,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          );
        },
        rows: totalsByCard.entries.map((entry) {
          final accountId = entry.key.split('|').first;
          final account = accountsById[accountId];
          return _SummaryRow(
            label: accountLabel[entry.key]!,
            accountId: accountId,
            currency: currenciesByCard[entry.key]!,
            amount: entry.value,
            displayName: account?.displayName,
            plaidName: account?.plaidName,
            officialName: account?.officialName,
            accountMask: account?.mask,
          );
        }).toList(),
      ),
      const SizedBox(height: 8),
Align(
        alignment: Alignment.center,
        child: FilledButton.icon(
          onPressed: _linkingPlaid ? null : _startPlaidLink,
          icon: _linkingPlaid
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.add, size: 18),
          label: const Text('Link a card'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ),
      ),
      const SizedBox(height: 12),
      _SummaryBreakdownCard(
        title: 'By household member',
        emptyMessage: 'No assigned charges in this period.',
        onRowTap: (row) {
          if (row.personId == null) return;
          setState(() {
            _drilldownPersonId = row.personId;
            _drilldownAccountId = null;
            _filterDateRange = _summaryRange;
          });
          _pageController.animateToPage(
            1,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          );
        },
        rows: totalsByPersonAndCurrency.entries.map((entry) {
          final parts = entry.key.split('|');
          final person = peopleById[parts.first];
          return _SummaryRow(
            label: person?.displayName ?? 'Unassigned',
            personId: person?.id,
            currency: parts.last,
            amount: entry.value,
            color: person == null ? null : _personColor(person.id, _people),
          );
        }).toList(),
      ),
      const SizedBox(height: 12),
      const Text(
        'Counts positive, posted card charges by transaction date. Pending '
        'transactions, credits/refunds, and card payments are excluded. This '
        'is spending in the selected range, not the Plaid statement balance '
        'or a calculated amount to pay your partner.',
      ),
      if (_transactions.isEmpty && _error == null) ...[
        const SizedBox(height: 12),
        _emptyCard('No Plaid transactions have been synced yet.'),
      ],
    ];
  }

  Future<void> _chooseSummaryRange() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(today.year + 2),
      initialDateRange: _summaryRange,
      helpText: 'Choose transaction date range',
      saveText: 'Apply range',
    );
    if (picked == null || !mounted) return;
    final newRange = DateTimeRange(
      start: DateUtils.dateOnly(picked.start),
      end: DateUtils.dateOnly(picked.end),
    );
    setState(() {
      _summaryRange = newRange;
      _filterDateRange = newRange; // Sync with transactions tab filter
    });
  }

  List<DateTime> _quickMonths() {
    final today = DateUtils.dateOnly(DateTime.now());
    return List<DateTime>.generate(
      12,
      (index) => DateTime(today.year, today.month - index, 1),
      growable: false,
    );
  }

  bool _rangeIsMonth(DateTime month) {
    final today = DateUtils.dateOnly(DateTime.now());
    final monthEnd = DateTime(month.year, month.month + 1, 0);
    final expectedEnd = monthEnd.isAfter(today) ? today : monthEnd;
    return _summaryRange.start == DateTime(month.year, month.month) &&
        _summaryRange.end == expectedEnd;
  }

  void _selectMonth(DateTime month) {
    final today = DateUtils.dateOnly(DateTime.now());
    final monthEnd = DateTime(month.year, month.month + 1, 0);
    final newRange = DateTimeRange(
      start: DateTime(month.year, month.month),
      end: monthEnd.isAfter(today) ? today : monthEnd,
    );
    setState(() {
      _summaryRange = newRange;
      _filterDateRange = newRange; // Sync with transactions tab filter
      _drilldownAccountId = null;
      _drilldownPersonId = null;
    });
  }

  Future<void> _showPayActionSheet(BuildContext context, double amount, String currency) async {
    final theme = Theme.of(context);
    final text = '${_currencySymbol(currency)} ${amount.toStringAsFixed(2)}';

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewPadding.bottom,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outline.withAlpha(100),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    Text('Pay $text', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _PayAppButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _copyAmountAndOpenApp(text, 'Fidelity');
                        },
                        logo: _AppLogo.fidelity,
                        label: 'Fidelity',
                        isPrimary: true,
                      ),
                      const SizedBox(height: 12),
                      _PayAppButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _copyAmountAndOpenApp(text, 'Chase');
                        },
                        logo: _AppLogo.chase,
                        label: 'Chase',
                        isPrimary: false,
                      ),
                      const SizedBox(height: 12),
                      _PayAppButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _copyAmountAndOpenApp(text, 'Venmo');
                        },
                        logo: _AppLogo.venmo,
                        label: 'Venmo',
                        isPrimary: false,
                      ),
                      const SizedBox(height: 12),
                      _PayAppButton(
                        onPressed: () {
                          Navigator.pop(context);
                          Clipboard.setData(ClipboardData(text: text));
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied $text')));
                        },
                        logo: _AppLogo.copy,
                        label: 'Copy amount only',
                        isPrimary: false,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copyAmountAndOpenApp(String text, String appName) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied $text to clipboard')));

    if (defaultTargetPlatform == TargetPlatform.android) {
      final packageName = _getPackageName(appName);
      if (packageName != null) {
        try {
          final intent = AndroidIntent(
            action: 'android.intent.action.MAIN',
            package: packageName,
          );
          await intent.launch();
          return;
        } catch (_) {
          // Fall through to deep link attempt
        }
      }
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      final urlScheme = _getUrlScheme(appName);
      if (urlScheme != null) {
        try {
          await launchUrl(Uri.parse(urlScheme), mode: LaunchMode.externalApplication);
          return;
        } catch (_) {
          // Fall through
        }
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open $appName app')));
  }

  String? _getPackageName(String appName) {
    switch (appName) {
      case 'Fidelity':
        return 'com.fidelity.android';
      case 'Chase':
        return 'com.chase.sig.android';
      case 'Venmo':
        return 'com.venmo';
      default:
        return null;
    }
  }

  String? _getUrlScheme(String appName) {
    switch (appName) {
      case 'Fidelity':
        return 'fidelity://';
      case 'Chase':
        return 'chase://';
      case 'Venmo':
        return 'venmo://';
      default:
        return null;
    }
  }

  List<Widget> _eventContent() {
    final personNames = {
      for (final person in _people) person.id: person.displayName,
    };
    return [
      const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Text(
          'These are the card events received from connected capture sources. '
          'The iPhone Shortcut remains the iOS capture method.',
        ),
      ),
      if (_events.isEmpty)
        _emptyCard('No captured card events have been received yet.')
      else
        ..._events.map(
          (event) => _EventCard(
            event: event,
            personName: event.personId == null
                ? null
                : personNames[event.personId],
            people: _people,
          ),
        ),
    ];
  }

  List<Widget> _peopleContent() {
    return [
      const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Text(
          'Household members are available for transaction assignment. '
          'The primary person receives any transaction left on the household default.',
        ),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add household member',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'Invite someone to share card transactions. They can scan the QR code below or you can add them manually.',
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _scanningQr ? null : _scanQrToAddPerson,
                      icon: _scanningQr
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.qr_code_scanner),
                      label: const Text('Scan QR to add'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.primary,
                        side: BorderSide(color: Theme.of(context).colorScheme.primary),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _addingPerson ? null : _addPerson,
                      icon: _addingPerson
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.person_add),
                      label: const Text('Add manually'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      if (_people.isEmpty)
        _emptyCard('No household members are configured.')
      else
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current members',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ..._people.map(
              (person) => Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _personColor(person.id, _people),
                    child: Text(
                      person.displayName.isEmpty
                          ? '?'
                          : person.displayName.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  title: Text(person.displayName),
                  subtitle: person.isDefault
                      ? const Text('Household default')
                      : null,
                  trailing: person.isDefault
                      ? const Icon(Icons.star_outline)
                      : null,
                ),
              ),
            ),
          ],
        ),
    ];
  }

  List<Widget> _plaidContent() {
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Plaid card connections',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Link each bank or card issuer once. Plaid securely keeps its '
                'connection so transactions and available statement data can '
                'sync automatically.',
              ),
              const SizedBox(height: 12),
              if (_plaidConnections.isEmpty)
                const Text('No bank connections have been linked yet.')
              else
                ..._plaidConnections.map((connection) {
                  final accounts = (_statementSummary?.accounts ?? const [])
                      .where((account) => account.itemId == connection.itemId)
                      .toList(growable: false);
                  final accountLabels = accounts
                      .map(
                        (account) {
                          final mask = account.mask;
                          if (mask != null &&
                              mask.isNotEmpty &&
                              !account.accountName.contains(mask)) {
                            return '${account.accountName} ··$mask';
                          }
                          return account.accountName;
                        },
                      )
                      .toList(growable: false);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.account_balance_outlined),
                    title: Text(connection.institutionName),
                    subtitle: Text(
                      accountLabels.isEmpty
                          ? 'Connected'
                          : accountLabels.join('\n'),
                    ),
                    isThreeLine: accountLabels.length > 1,
                  );
                }),
              const SizedBox(height: 8),
              if (_linkingPlaid)
                const Center(child: CircularProgressIndicator())
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      key: const ValueKey('link-another-card'),
                      onPressed: _startPlaidLink,
                      icon: const Icon(Icons.add_link),
                      label: const Text('Link another card'),
                    ),
                    if (_plaidConnections.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: _loading
                            ? null
                            : () async {
                                setState(() {
                                  _loading = true;
                                  _error = null;
                                });
                                try {
                                  await widget.api.syncPlaidConnections();
                                  await _refresh();
                                } catch (error) {
                                  if (mounted) {
                                    setState(() => _error = error.toString());
                                  }
                                } finally {
                                  if (mounted) {
                                    setState(() => _loading = false);
                                  }
                                }
                              },
                        icon: const Icon(Icons.sync),
                        label: const Text('Sync now'),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    ];
  }

  List<Widget> _captureContent() {
    final plaidContent = _plaidContent();
    if (!_isAndroid) {
      return [
        ...plaidContent,
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'iPhone capture',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Use the iPhone Shortcut to send Wallet transaction '
                  'notifications to your household. iOS does not let apps read '
                  'notifications from other apps.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'iOS Shortcut remains the capture source; the app displays '
                  'the events it sends here.',
                ),
              ],
            ),
          ),
        ),
      ];
    }

    final selectedPerson = _people
        .where((person) => person.id == _capturePersonId)
        .firstOrNull;
    return [
      ...plaidContent,
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Google Wallet / Google Pay',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'With your permission, Android notification access lets this '
                'app detect transaction alerts from Google Wallet only. '
                'Matching alerts are sent to your household as card events.',
              ),
              const SizedBox(height: 8),
              Text(
                _captureConfigured
                    ? _notificationAccess
                          ? 'Capture is on for ${selectedPerson?.displayName ?? 'the selected person'}.'
                          : 'Device connected. Allow notification access to start capture.'
                    : 'Not connected.',
              ),
              if (!_captureConfigured) ...[
                const SizedBox(height: 12),
                _PersonSelectorTile(
                  title: 'Record Transactions As:',
                  currentPersonId: _capturePersonId,
                  people: _people,
                  onTap: _captureWorking
                      ? null
                      : () => _showPersonSelector(
                          context: context,
                          title: 'Record Transactions As:',
                          currentPersonId: _capturePersonId,
                          people: _people,
                          onSelected: (personId) =>
                              setState(() => _capturePersonId = personId),
                        ),
                ),
              ],
              const SizedBox(height: 14),
              if (_captureWorking)
                const Center(child: CircularProgressIndicator())
              else if (!_captureConfigured)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      onPressed: _people.isEmpty
                          ? null
                          : _enableGooglePayCapture,
                      icon: const Icon(Icons.link),
                      label: const Text('Connect this Android device'),
                    ),
                    if (_notificationAccess)
                      TextButton(
                        onPressed: _openNotificationAccessSettings,
                        child: const Text(
                          'Turn off notification access in Android Settings',
                        ),
                      ),
                  ],
                )
              else if (!_notificationAccess)
                FilledButton.icon(
                  onPressed: _openNotificationAccessSettings,
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('Allow notification access'),
                )
              else
                OutlinedButton.icon(
                  onPressed: _disableGooglePayCapture,
                  icon: const Icon(Icons.link_off),
                  label: const Text('Disconnect and revoke device key'),
                ),
            ],
          ),
        ),
      ),
      if (_captureError != null) ...[
        const SizedBox(height: 8),
        _errorCard(_captureError!),
      ],
      if (_captureConfigured && _notificationAccess) ...[
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _sendTestNotification,
          icon: const Icon(Icons.notifications_none),
          label: const Text('Send test Google Pay notification'),
        ),
      ],
      const SizedBox(height: 12),
      const Text(
        'Only Google Wallet transaction alerts that include a recognizable '
        'amount and merchant are submitted. Other apps’ notifications are '
        'ignored. Android’s notification-access permission itself can expose '
        'notifications system-wide, so grant it only if you are comfortable '
        'with that Android permission. Disconnecting revokes the upload key; '
        'also turn off this app’s notification access in Android Settings '
        'when you want to remove the OS permission.',
      ),
    ];
  }

  Widget _emptyOrError() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        if (_error != null) _errorCard(_error!),
        _emptyCard(
          _error == null
              ? 'No household activity is available yet.'
              : 'Could not load your household activity.',
        ),
        OutlinedButton.icon(
          onPressed: _loading ? null : _refresh,
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      ],
    );
  }

  Widget _errorCard(String error) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Text('Could not update activity: $error'),
      ),
    );
  }

  Widget _emptyCard(String message) {
    return Card(
      child: Padding(padding: const EdgeInsets.all(18), child: Text(message)),
    );
  }
}

class _StatementSummaryCard extends StatelessWidget {
  const _StatementSummaryCard({required this.summary});

  final StatementCycleSummary? summary;

  @override
  Widget build(BuildContext context) {
    final value = summary;
    final headline = value == null
        ? 'Statement total unavailable'
        : value.status == 'READY' || value.status == 'REVIEW'
        ? 'Current statement charges'
        : 'Statement total not ready';
    final amount = value?.total == null
        ? null
        : '${_currencySymbol(value!.currency ?? '')} ${_money(value.total!, absolute: true)}'
              .trim();
     return Card(
       child: Padding(
         padding: const EdgeInsets.all(18),
         child: Column(
           crossAxisAlignment: CrossAxisAlignment.start,
           children: [
             Text(headline, style: Theme.of(context).textTheme.titleMedium?.copyWith(
               color: Theme.of(context).colorScheme.primary,
             )),
            const SizedBox(height: 6),
            Text(
              amount ?? _statementStatus(value?.status),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              value == null
                  ? 'Refresh to check statement data.'
                  : '${value.accountCount} card account'
                        '${value.accountCount == 1 ? '' : 's'} · '
                        'split by assigned person',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

const _approvedCharcoal = Color(0xFF3F4540);

class _TransactionCard extends StatelessWidget {
  const _TransactionCard({
    required this.transaction,
    required this.people,
    required this.personNames,
    required this.updating,
    required this.onAssign,
    required this.onOpenAssigneePicker,
  });

  final CardTransaction transaction;
  final List<HouseholdPerson> people;
  final Map<String, String> personNames;
  final bool updating;
  final ValueChanged<String?> onAssign;
  final VoidCallback onOpenAssigneePicker;

  @override
  Widget build(BuildContext context) {
    final merchant = transaction.merchant;
    final assignedPerson = people
        .where((person) => person.id == transaction.assignedPersonId)
        .firstOrNull;
    final assigneeName =
        assignedPerson?.displayName ??
        personNames[transaction.assignedPersonId] ??
        'Household default';
    final assigneeColor = assignedPerson == null
        ? Theme.of(context).colorScheme.primary
        : _personColor(assignedPerson.id, people);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        merchant?.isNotEmpty == true
                            ? merchant!
                            : transaction.name,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: transaction.pending
                              ? _pendingOrange
                              : _approvedCharcoal,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (transaction.date != null) transaction.date!,
                          if (transaction.accountName?.isNotEmpty == true)
                            transaction.accountName!,
                          if (transaction.pending) 'Pending',
                        ].join(' · '),
                        style: TextStyle(
                          color: transaction.pending
                              ? _pendingOrange
                              : _approvedCharcoal,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${_currencySymbol(transaction.currency)} ${_money(transaction.amount)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: transaction.pending
                        ? _pendingOrange
                        : _approvedCharcoal,
                    fontWeight: FontWeight.w700,
                  ),
),
              ],
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: updating ? null : onOpenAssigneePicker,
              borderRadius: BorderRadius.circular(16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: assigneeColor.withAlpha(24),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: updating
                        ? assigneeColor.withAlpha(90)
                        : assigneeColor.withAlpha(150),
                    width: updating ? 1 : 2,
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: assigneeColor,
                       child: transaction.hasSplits
                           ? const Text(
                               'SPLIT',
                               style: TextStyle(
                                 color: Colors.white,
                                 fontSize: 16,
                                 fontWeight: FontWeight.w700,
                               ),
                             )
                           : Text(
                               assigneeName.isEmpty
                                   ? '?'
                                   : assigneeName.substring(0, 1).toUpperCase(),
                               style: TextStyle(
                                 color: Colors.white,
                                 fontSize: 17,
                                 fontWeight: FontWeight.w700,
                               ),
                             ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ASSIGNED TO',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: assigneeColor,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.1,
                                ),
                          ),
                          const SizedBox(height: 2),
                           Text(
                             transaction.hasSplits ? 'SPLIT' : assigneeName,
                             key: ValueKey('assignee-name-${transaction.id}'),
                             style: Theme.of(context).textTheme.titleLarge
                                 ?.copyWith(
                                   color: transaction.hasSplits
                                       ? Theme.of(context).colorScheme.primary
                                       : assigneeColor,
                                   fontWeight: FontWeight.w800,
                                 ),
                             maxLines: 1,
                             overflow: TextOverflow.ellipsis,
                           ),
                        ],
                      ),
                    ),
                    if (transaction.assignmentSource != 'default')
                      Icon(
                        Icons.verified_rounded,
                        color: assigneeColor,
                      ),
                    if (!updating) ...[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: assigneeColor.withAlpha(180),
                      ),
                    ],
                    if (updating) ...[
                      const SizedBox(width: 12),
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.personName,
    required this.people,
  });

  final CardEventRecord event;
  final String? personName;
  final List<HouseholdPerson> people;

  @override
  Widget build(BuildContext context) {
    final bg = switch (event.reconciliationStatus) {
      'matched' => Colors.green.withAlpha(12),
      'manual' => Colors.yellow.withAlpha(12),
      'none' || null => Theme.of(context).cardTheme.color,
      _ => Theme.of(context).cardTheme.color,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: bg,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: const Icon(Icons.notifications_outlined, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.merchant,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text('${event.cardLabel} · ${event.paymentLabel}'),
                  const SizedBox(height: 8),
                  _PersonBadge(
                    name: personName ?? 'Person not assigned',
                    color: event.personId == null
                        ? Theme.of(context).colorScheme.outline
                        : _personColor(event.personId!, people),
                  ),
                  if (event.reconciliationStatus != null &&
                      event.reconciliationStatus != 'none')
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Icon(
                            switch (event.reconciliationStatus) {
                              'matched' => Icons.check_circle,
                              'manual' => Icons.warning,
                              _ => Icons.info_outline,
                            },
                            size: 14,
                            color: switch (event.reconciliationStatus) {
                              'matched' => Colors.green,
                              'manual' => Colors.orange,
                              _ => null,
                            },
                          ),
                          const SizedBox(width: 4),
                          Text(
                            event.reconciliationStatus! == 'matched'
                                ? 'Matched'
                                : event.reconciliationStatus! == 'manual'
                                ? 'Manual'
                                : '',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      )),
                  const SizedBox(height: 5),
                  Text(
                    '${_sourceLabel(event.source)} · '
                    '${_dateLabel(event.occurredAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${_currencySymbol(event.currency)} ${_money(event.amount, absolute: true)}',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.end,
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryBreakdownCard extends StatelessWidget {
  const _SummaryBreakdownCard({
    required this.title,
    required this.emptyMessage,
    required this.onRowTap,
    this.onEditRow,
    required this.rows,
  });

  final String title;
  final String emptyMessage;
  final ValueChanged<_SummaryRow> onRowTap;
  final ValueChanged<_SummaryRow>? onEditRow;
  final List<_SummaryRow> rows;

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<_SummaryRow>>{};
    for (final row in rows) {
      grouped.putIfAbsent(row.currency, () => []).add(row);
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Text(emptyMessage),
              )
            else
              ...grouped.entries.expand(
                (currencyGroup) => [
                  if (grouped.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 4),
                      child: Text(
                        currencyGroup.key,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                  ...currencyGroup.value.map(
                    (row) => InkWell(
                      key: ValueKey(
                        'summary-row-${row.accountId ?? row.personId ?? row.label}',
                      ),
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => onRowTap(row),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            if (row.color != null) ...[
                              CircleAvatar(
                                radius: 8,
                                backgroundColor: row.color,
                              ),
                              const SizedBox(width: 9),
                            ],
                            Expanded(
                              child: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      row.label,
                                      style: Theme.of(context).textTheme.bodyLarge,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (onEditRow != null && row.accountId != null) ...[
                                    const SizedBox(width: 8),
                                    IconButton(
                                      key: ValueKey(
                                        'edit-card-name-${row.accountId}',
                                      ),
                                      tooltip: 'Edit card name',
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                      onPressed: () => onEditRow!(row),
                                      icon: const Icon(Icons.edit_outlined, size: 18),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '${_currencySymbol(row.currency)} ${_money(row.amount.toStringAsFixed(2))}',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(width: 6),
                            if (onEditRow == null || row.accountId == null)
                              Icon(
                                Icons.chevron_right,
                                color: Theme.of(context).colorScheme.outline,
                                size: 20,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow {
  const _SummaryRow({
    required this.label,
    required this.currency,
    required this.amount,
    this.accountId,
    this.personId,
    this.color,
    this.displayName,
    this.plaidName,
    this.officialName,
    this.accountMask,
  });

  final String label;
  final String currency;
  final double amount;
  final String? accountId;
  final String? personId;
  final Color? color;
  final String? displayName;
  final String? plaidName;
  final String? officialName;
  final String? accountMask;
}

class _PersonBadge extends StatelessWidget {
  const _PersonBadge({required this.name, required this.color});

  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person, size: 15, color: color),
          const SizedBox(width: 4),
          Text(
            name,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

const _personPalette = [
  Color(0xFF176B5B),
  Color(0xFF4F46A5),
  Color(0xFFC2415D),
  Color(0xFF146A8A),
  Color(0xFF8A4E9B),
  Color(0xFF966000),
];

Color _personColor(String personId, List<HouseholdPerson> people) {
  final index = people.indexWhere((person) => person.id == personId);
  if (index < 0) return _personPalette.first;
  return _personPalette[index % _personPalette.length];
}

class _AddPersonDialog extends StatefulWidget {
  const _AddPersonDialog();

  @override
  State<_AddPersonDialog> createState() => _AddPersonDialogState();
}

class _AddPersonDialogState extends State<_AddPersonDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, _controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add household member'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          maxLength: 100,
          decoration: const InputDecoration(labelText: 'Name'),
          validator: (value) =>
              value == null || value.trim().isEmpty ? 'Enter a name' : null,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Add'),
        ),
      ],
    );
  }
}

String _money(String value, {bool absolute = false}) {
  final parsed = double.tryParse(value);
  if (parsed == null) return value;
  return (absolute ? parsed.abs() : parsed).toStringAsFixed(2);
}

String _currencySymbol(String currency) {
  switch (currency.toUpperCase()) {
    case 'USD':
      return '\$';
    case 'EUR':
      return '€';
    case 'GBP':
      return '£';
    case 'CAD':
      return 'CA\$';
    case 'AUD':
      return 'A\$';
    case 'JPY':
      return '¥';
    case 'CNY':
      return '¥';
    default:
      return currency;
  }
}

String _statementStatus(String? status) {
  return switch (status) {
    'REVIEW' => 'Needs review',
    'MULTI_CURRENCY' => 'Cards use different currencies',
    _ => 'Waiting for statement data',
  };
}

String _sourceLabel(String source) {
  return switch (source) {
    'ios_shortcut' => 'iPhone Shortcut',
    'authenticated_api' => 'Mobile app',
    'api_test' => 'Test event',
    _ => source,
  };
}

String _dateLabel(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return 'Date unavailable';
  final date = parsed.toLocal();
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

String _rangeLabel(DateTimeRange range) {
  return '${_shortDate(range.start)} – ${_shortDate(range.end)}';
}

String _shortDate(DateTime value) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[value.month - 1]} ${value.day}, ${value.year}';
}

String _monthLabel(DateTime value) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return "${months[value.month - 1]} '${value.year.toString().substring(2)}";
}

class _PersonSelectorSheet extends StatefulWidget {
  const _PersonSelectorSheet({
    required this.title,
    required this.currentPersonId,
    required this.people,
    required this.onSelected,
  });

  final String title;
  final String? currentPersonId;
  final List<HouseholdPerson> people;
  final ValueChanged<String?> onSelected;

  @override
  State<_PersonSelectorSheet> createState() => _PersonSelectorSheetState();
}

class _PersonSelectorSheetState extends State<_PersonSelectorSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(30),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 5,
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outline.withAlpha(100),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          widget.title,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          softWrap: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: widget.people.length + 1,
                    separatorBuilder: (context, index) =>
                        Divider(height: 1, indent: 56, endIndent: 16),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        final isSelected = widget.currentPersonId == null;
                        return _PersonSelectorTileItem(
                          person: null,
                          displayName: 'Household default',
                          isSelected: isSelected,
                          color: theme.colorScheme.primary,
                          onTap: () {
                            Navigator.pop(context);
                            widget.onSelected(null);
                          },
                        );
                      }
                      final person = widget.people[index - 1];
                      final isSelected = widget.currentPersonId == person.id;
                      return _PersonSelectorTileItem(
                        person: person,
                        displayName: person.displayName,
                        isSelected: isSelected,
                        color: _personColor(person.id, widget.people),
                        onTap: () {
                          Navigator.pop(context);
                          widget.onSelected(person.id);
                        },
                      );
                    },
                  ),
                ),
                SizedBox(height: MediaQuery.of(context).viewPadding.bottom + 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PersonSelectorTileItem extends StatelessWidget {
  const _PersonSelectorTileItem({
    required this.person,
    required this.displayName,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  final HouseholdPerson? person;
  final String displayName;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: isSelected ? color : color.withAlpha(40),
              child: Text(
                displayName.isEmpty
                    ? '?'
                    : displayName.substring(0, 1).toUpperCase(),
                style: TextStyle(
                  color: isSelected ? Colors.white : color,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                displayName,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? color : theme.colorScheme.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle_rounded,
                color: color,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }
}

class _PersonSelectorTile extends StatelessWidget {
  const _PersonSelectorTile({
    required this.title,
    required this.currentPersonId,
    required this.people,
    this.onTap,
  });

  final String title;
  final String? currentPersonId;
  final List<HouseholdPerson> people;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentPerson = people
        .where((p) => p.id == currentPersonId)
        .firstOrNull;
    final displayName = currentPerson?.displayName ?? 'Household default';
    final color = currentPerson == null
        ? theme.colorScheme.primary
        : _personColor(currentPerson.id, people);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.outline.withAlpha(100),
            width: 1.5,
          ),
          color: theme.colorScheme.surface,
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: color.withAlpha(40),
              child: Text(
                displayName.isEmpty
                    ? '?'
                    : displayName.substring(0, 1).toUpperCase(),
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    softWrap: true,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    displayName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _DropdownMenu extends StatefulWidget {
  const _DropdownMenu({
    required this.label,
    required this.currentValue,
    required this.people,
    required this.onSelected,
  });

  final String label;
  final String? currentValue;
  final List<HouseholdPerson> people;
  final ValueChanged<String?>? onSelected;

  @override
  State<_DropdownMenu> createState() => _DropdownMenuState();
}

class _DropdownMenuState extends State<_DropdownMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 180),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    );
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          constraints: const BoxConstraints(maxHeight: 320),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.outline.withAlpha(100),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(40),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Text(
                      widget.label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => widget.onSelected?.call(widget.currentValue),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: widget.people.length + 1,
                  separatorBuilder: (context, index) =>
                      Divider(height: 1, indent: 56, endIndent: 16),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      final isSelected = widget.currentValue == null;
                      return _PersonSelectorTileItem(
                        person: null,
                        displayName: 'Household default',
                        isSelected: isSelected,
                        color: theme.colorScheme.primary,
                        onTap: () => widget.onSelected?.call(null),
                      );
                    }
                    final person = widget.people[index - 1];
                    final isSelected = widget.currentValue == person.id;
                    return _PersonSelectorTileItem(
                      person: person,
                      displayName: person.displayName,
                      isSelected: isSelected,
                      color: _personColor(person.id, widget.people),
                      onTap: () => widget.onSelected?.call(person.id),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransactionFilterBar extends StatelessWidget {
  const _TransactionFilterBar({
    required this.accounts,
    required this.people,
    required this.selectedAccountId,
    required this.selectedPersonId,
    required this.selectedDateRange,
    required this.selectedStatus,
    required this.onAccountChanged,
    required this.onPersonChanged,
    required this.onDateRangeChanged,
    required this.onStatusChanged,
    required this.onClearAll,
  });

  final List<StatementAccount> accounts;
  final List<HouseholdPerson> people;
  final String? selectedAccountId;
  final String? selectedPersonId;
  final DateTimeRange? selectedDateRange;
  final String? selectedStatus;
  final ValueChanged<String?> onAccountChanged;
  final ValueChanged<String?> onPersonChanged;
  final ValueChanged<DateTimeRange?> onDateRangeChanged;
  final ValueChanged<String?> onStatusChanged;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quickMonths = List<DateTime>.generate(
      12,
      (index) {
        final today = DateUtils.dateOnly(DateTime.now());
        return DateTime(today.year, today.month - index, 1);
      },
      growable: false,
    );

    final hasFilters = selectedAccountId != null ||
        selectedPersonId != null ||
        selectedDateRange != null ||
        selectedStatus != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Filters',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (hasFilters)
                  TextButton.icon(
                    onPressed: onClearAll,
                    icon: const Icon(Icons.clear_all, size: 16),
                    label: const Text('Clear all'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _FilterMenuButton(
                  label: 'Credit card',
                  selectedValue: selectedAccountId,
                  items: [
                    const _FilterMenuItem(value: '__all__', label: 'All cards'),
                    ...accounts.map((a) => _FilterMenuItem(
                      value: a.accountId,
                      label: a.accountName,
                    )),
                  ],
                  onChanged: onAccountChanged,
                ),
                _FilterMenuButton(
                  label: 'Assigned to',
                  selectedValue: selectedPersonId,
                  items: [
                    const _FilterMenuItem(value: '__everyone__', label: 'Everyone'),
                    ...people.map((p) => _FilterMenuItem(
                      value: p.id,
                      label: p.displayName,
                    )),
                  ],
                  onChanged: onPersonChanged,
                ),
                _FilterMenuButton(
                  label: 'Status',
                  selectedValue: selectedStatus,
                  items: const [
                    _FilterMenuItem(value: '__all__', label: 'All'),
                    _FilterMenuItem(value: 'pending', label: 'Pending'),
                    _FilterMenuItem(value: 'approved', label: 'Approved'),
                  ],
                  onChanged: onStatusChanged,
                ),
                _DateRangeFilterButton(
                  label: 'Date range',
                  selectedRange: selectedDateRange,
                  quickMonths: quickMonths,
                  onChanged: onDateRangeChanged,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterMenuButton extends StatelessWidget {
  const _FilterMenuButton({
    required this.label,
    required this.selectedValue,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final String? selectedValue;
  final List<_FilterMenuItem> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopupMenuButton<String?>(
      initialValue: selectedValue,
      onSelected: onChanged,
      itemBuilder: (context) => items.map((item) => PopupMenuItem<String?>(
        value: item.value,
        child: Text(item.label),
      )).toList(),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selectedValue != null
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
            ),
            color: selectedValue != null
                ? theme.colorScheme.primary
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: selectedValue != null
                      ? Colors.white
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

class _FilterMenuItem {
  const _FilterMenuItem({required this.value, required this.label});
  final String? value;
  final String label;
}

class _DateRangeFilterButton extends StatelessWidget {
  const _DateRangeFilterButton({
    required this.label,
    required this.selectedRange,
    required this.quickMonths,
    required this.onChanged,
  });

  final String label;
  final DateTimeRange? selectedRange;
  final List<DateTime> quickMonths;
  final ValueChanged<DateTimeRange?> onChanged;

  String _monthLabel(DateTime value) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return "${months[value.month - 1]} '${value.year.toString().substring(2)}";
  }

  Future<void> _showMenu(BuildContext context) async {
    final theme = Theme.of(context);
    final picked = await showModalBottomSheet<DateTimeRange?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewPadding.bottom,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outline.withAlpha(100),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    Text('Date range', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Quick select', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: quickMonths.map((month) {
                        final isSelected = selectedRange != null &&
                            selectedRange!.start.year == month.year &&
                            selectedRange!.start.month == month.month;
                        final monthEnd = DateTime(month.year, month.month + 1, 0);
                        final today = DateUtils.dateOnly(DateTime.now());
                        final range = DateTimeRange(
                          start: month,
                          end: monthEnd.isAfter(today) ? today : monthEnd,
                        );
                        return FilterChip(
                          label: Text(_monthLabel(month)),
                          selected: isSelected,
                          onSelected: (_) => Navigator.pop(context, range),
                          visualDensity: VisualDensity.compact,
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context, null),
                            child: const Text('All time'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () async {
                              final navigator = Navigator.of(context);
                              final picked = await showDateRangePicker(
                                context: context,
                                firstDate: DateTime(2000),
                                lastDate: DateTime.now(),
                                initialDateRange: selectedRange,
                              );
                              if (picked != null) {
                                navigator.pop(DateTimeRange(
                                  start: DateUtils.dateOnly(picked.start),
                                  end: DateUtils.dateOnly(picked.end),
                                ));
                              }
                            },
                            child: const Text('Custom range'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return OutlinedButton(
      onPressed: () => _showMenu(context),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        side: BorderSide(
          color: selectedRange != null
              ? theme.colorScheme.primary
              : theme.colorScheme.primary,
        ),
        backgroundColor: selectedRange != null
            ? theme.colorScheme.primary
            : theme.colorScheme.primaryContainer.withAlpha(50),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: selectedRange != null
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.arrow_drop_down,
            size: 18,
            color: selectedRange != null ? theme.colorScheme.onPrimary : theme.colorScheme.primary,
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.onRemove,
  });

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InputChip(
      label: Text(label),
      deleteIcon: const Icon(Icons.close, size: 18),
      onDeleted: onRemove,
      deleteButtonTooltipMessage: 'Clear filter',
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      side: BorderSide(color: theme.colorScheme.outline.withAlpha(100)),
      backgroundColor: theme.colorScheme.surfaceContainerHighest.withAlpha(50),
      labelStyle: theme.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w500,
      ),
      deleteIconColor: theme.colorScheme.onSurfaceVariant,
    );
  }
}

class _PayButton extends StatelessWidget {
  const _PayButton({
    required this.amount,
    required this.currency,
    required this.onTap,
  });

  final double amount;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = '${_currencySymbol(currency)} ${amount.toStringAsFixed(2)}';

    return FilledButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.payments_outlined),
      label: Text(
        'Pay $text',
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: Colors.white,
          fontSize: 16,
        ),
      ),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        minimumSize: const Size.fromHeight(56),
      ),
    );
  }
}

class _PayAppButton extends StatelessWidget {
  const _PayAppButton({
    required this.onPressed,
    required this.label,
    required this.logo,
    this.isPrimary = false,
  });

  final VoidCallback onPressed;
  final String label;
  final _AppLogo logo;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brandColor = _getBrandColor(logo, theme);

    if (isPrimary) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          backgroundColor: brandColor,
        ),
        child: _ButtonContent(logo: logo, label: label, color: Colors.white),
      );
    }

    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        side: BorderSide(color: brandColor, width: 2),
      ),
      child: _ButtonContent(logo: logo, label: label, color: brandColor),
    );
  }

  Color _getBrandColor(_AppLogo logo, ThemeData theme) {
    switch (logo) {
      case _AppLogo.fidelity:
        return const Color(0xFF006044); // Fidelity dark green
      case _AppLogo.chase:
        return const Color(0xFF1171C5); // Chase blue
      case _AppLogo.venmo:
        return const Color(0xFF008CFF); // Venmo blue
      case _AppLogo.copy:
        return theme.colorScheme.primary;
    }
  }
}

class _ButtonContent extends StatelessWidget {
  const _ButtonContent({
    required this.logo,
    required this.label,
    required this.color,
  });

  final _AppLogo logo;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _LogoWidget(logo: logo, color: color, size: 20),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: color, fontSize: 16)),
      ],
    );
  }
}

class _LogoWidget extends StatelessWidget {
  const _LogoWidget({required this.logo, required this.color, required this.size});

  final _AppLogo logo;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    switch (logo) {
      case _AppLogo.fidelity:
        return Icon(Icons.account_balance_wallet_rounded, size: size, color: color);
      case _AppLogo.chase:
        return Icon(Icons.credit_card_rounded, size: size, color: color);
      case _AppLogo.venmo:
        return Icon(Icons.payment_rounded, size: size, color: color);
      case _AppLogo.copy:
        return Icon(Icons.copy_outlined, size: size, color: color);
    }
  }
}

enum _AppLogo { fidelity, chase, venmo, copy }

class _QrScannerSheet extends StatefulWidget {
  const _QrScannerSheet({required this.onScan});

  final ValueChanged<String> onScan;

  @override
  State<_QrScannerSheet> createState() => _QrScannerSheetState();
}

class _QrScannerSheetState extends State<_QrScannerSheet> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  bool _scanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null && barcode.rawValue!.isNotEmpty) {
        _scanned = true;
        widget.onScan(barcode.rawValue!);
        Navigator.pop(context);
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Container(
              width: 40,
              height: 5,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(100),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Text('Scan invite QR code', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white)),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.white24),
            Expanded(
              child: Stack(
                children: [
                  MobileScanner(
                    controller: _controller,
                    onDetect: _onDetect,
                  ),
                  Center(
                    child: Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 40,
                    left: 0,
                    right: 0,
                    child: Text(
                      'Position QR code within the frame',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: MediaQuery.of(context).viewPadding.bottom + 16),
          ],
        ),
      ),
    );
  }
}

class _SensitivePageScrollPhysics extends PageScrollPhysics {
  const _SensitivePageScrollPhysics({super.parent});

  @override
  _SensitivePageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _SensitivePageScrollPhysics(parent: buildParent(ancestor));
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
