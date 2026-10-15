import 'package:flutter/material.dart';

class SettingsStep extends StatelessWidget {
  const SettingsStep({
    super.key,
    required this.number,
    required this.title,
    required this.description,
    required this.icon,
    required this.isComplete,
    this.action,
  });

  final String number;
  final String title;
  final String description;
  final IconData icon;
  final bool isComplete;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: isComplete
              ? accent
              : theme.colorScheme.surfaceContainerHighest,
          child: isComplete
              ? const Icon(Icons.check, color: Colors.white, size: 20)
              : Text(
                  number,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (action != null) ...[
                const SizedBox(height: 8),
                action!,
              ],
            ],
          ),
        ),
      ],
    );
  }
}
