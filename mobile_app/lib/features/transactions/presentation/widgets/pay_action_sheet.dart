import 'package:flutter/material.dart';
import 'package:cardsemble/core/core.dart';
import 'package:cardsemble/features/transactions/presentation/transactions_notifier.dart';
import 'package:cardsemble/theme/app_colors.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class PayButton extends StatelessWidget {
  const PayButton({super.key});

  @override
  Widget build(BuildContext context) {
    final notifier = context.read<TransactionsNotifier>();
    final amount = notifier.filteredTotal;
    final currency = notifier.filteredCurrency;
    if (amount <= 0) {
      return const SizedBox.shrink();
    }
    final text = '\$ $currency ${amount.toStringAsFixed(2)}';
    return FilledButton.icon(
      onPressed: () => _showPayActionSheet(context, amount, currency),
      icon: const Icon(Icons.payments_outlined),
      label: Text('Pay $text', overflow: TextOverflow.ellipsis, softWrap: false),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        minimumSize: const Size(0, 44),
      ),
    );
  }

  Future<void> _showPayActionSheet(
      BuildContext context, double amount, String currency) async {
    final theme = Theme.of(context);
    final launcher = DefaultExternalAppLauncher();

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
                  color: theme.colorScheme.outline.withValues(alpha: 100),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    Text('Pay with', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              const SizedBox(height: 16),
              _PayAppButton(
                logo: _AppLogo.fidelity,
                label: 'Fidelity',
                onPressed: () => _handlePress(context, launcher, _AppLogo.fidelity, amount, currency),
              ),
              const SizedBox(height: 12),
              _PayAppButton(
                logo: _AppLogo.chase,
                label: 'Chase',
                onPressed: () => _handlePress(context, launcher, _AppLogo.chase, amount, currency),
              ),
              const SizedBox(height: 12),
              _PayAppButton(
                logo: _AppLogo.venmo,
                label: 'Venmo',
                onPressed: () => _handlePress(context, launcher, _AppLogo.venmo, amount, currency),
              ),
              const SizedBox(height: 12),
              _PayAppButton(
                logo: _AppLogo.copy,
                label: 'Copy amount only',
                onPressed: () => _handleCopy(context, amount, currency),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handlePress(
      BuildContext context,
      ExternalAppLauncher launcher,
      _AppLogo logo,
      double amount,
      String currency) async {
    final packageName = _getPackageName(logo);
    final scheme = _getUrlScheme(logo);
    try {
       await launcher.launchApp(
         packageName: packageName!,
         scheme: scheme!,
         amount: amount.toString(),
         currency: currency,
       );
      // Optionally show success snackbar
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Opened ${logo.toString().split('.').last} app')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open ${logo.toString().split('.').last} app')),
      );
    }
  }

  Future<void> _handleCopy(
      BuildContext context, double amount, String currency) async {
    final text = '\$ $currency ${amount.toStringAsFixed(2)}';
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied \$text to clipboard')),
    );
  }

  String? _getPackageName(_AppLogo logo) {
    switch (logo) {
      case _AppLogo.fidelity:
        return 'com.fidelity.android';
      case _AppLogo.chase:
        return 'com.chase.sig.android';
      case _AppLogo.venmo:
        return 'com.venmo';
      case _AppLogo.copy:
        return null;
    }
  }

  String? _getUrlScheme(_AppLogo logo) {
    switch (logo) {
      case _AppLogo.fidelity:
        return 'fidelity://';
      case _AppLogo.chase:
        return 'chase://';
      case _AppLogo.venmo:
        return 'venmo://';
      case _AppLogo.copy:
        return null;
    }
  }
}

enum _AppLogo { fidelity, chase, venmo, copy }

class _PayAppButton extends StatelessWidget {
  const _PayAppButton({
    required this.logo,
    required this.label,
    required this.onPressed,
  });

  final _AppLogo logo;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
     final bool isLogo = logo != _AppLogo.copy;
    final Color backgroundColor;
    final Color foregroundColor;
    switch (logo) {
      case _AppLogo.fidelity:
        backgroundColor = AppColors.brandFidelity;
        foregroundColor = Colors.white;
      case _AppLogo.chase:
        backgroundColor = AppColors.brandChase;
        foregroundColor = Colors.white;
      case _AppLogo.venmo:
        backgroundColor = AppColors.brandVenmo;
        foregroundColor = AppColors.charcoal;
      case _AppLogo.copy:
        backgroundColor = theme.colorScheme.surfaceContainerHighest;
        foregroundColor = theme.colorScheme.onSurface;
    }
    return ElevatedButton(
       onPressed: onPressed,
       style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
         padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
         shape: RoundedRectangleBorder(
           borderRadius: BorderRadius.circular(12),
         ),
       ),
       child: Row(
         mainAxisSize: MainAxisSize.min,
         children: [
           if (isLogo) _LogoWidget(logo: logo, size: 24, color: foregroundColor),
           if (isLogo) const SizedBox(width: 12),
           Text(label,
               style: theme.textTheme.titleMedium?.copyWith(
                 fontWeight: FontWeight.w600,
                 color: foregroundColor,
               )),
         ],
       ),
     );
  }
}



class _LogoWidget extends StatelessWidget {
  const _LogoWidget({
    required this.logo,
    required this.color,
    required this.size,
  });

  final _AppLogo logo;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    switch (logo) {
      case _AppLogo.fidelity:
        return Icon(Icons.account_balance, size: size, color: color);
      case _AppLogo.chase:
        return Icon(Icons.account_balance_wallet, size: size, color: color);
      case _AppLogo.venmo:
        return Icon(Icons.account_circle, size: size, color: color);
      case _AppLogo.copy:
        return Icon(Icons.copy, size: size, color: color);
    }
  }
}