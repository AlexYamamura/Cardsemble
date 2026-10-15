import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cardsemble/features/card_events/presentation/card_events_notifier.dart';
import 'package:cardsemble/features/card_events/domain/card_events_domain.dart';
import 'package:cardsemble/core/utils/currency.dart';

class CardEventsScreen extends StatefulWidget {
  const CardEventsScreen({super.key});

  @override
  State<CardEventsScreen> createState() => _CardEventsScreenState();
}

class _CardEventsScreenState extends State<CardEventsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CardEventsNotifier>().loadEvents();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Card Events'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: () => _refresh(context),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Consumer<CardEventsNotifier>(
        builder: (context, notifier, _) {
          if (notifier.isLoading && notifier.events.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (notifier.error != null && notifier.events.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(notifier.error!),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => notifier.loadEvents(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (notifier.events.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.event_note_outlined, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('No card events yet'),
                  const SizedBox(height: 8),
                  const Text('Card events will appear here when captured', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => _refresh(context),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: notifier.events.length,
              itemBuilder: (context, index) {
                final event = notifier.events[index];
                return _EventTile(
                  event: event,
                  onVisibilityChange: (visible) => notifier.setHouseholdVisible(event.id, visible),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _refresh(BuildContext context) async {
    await context.read<CardEventsNotifier>().loadEvents();
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({
    required this.event,
    required this.onVisibilityChange,
  });

  final CardEventRecord event;
  final Future<bool> Function(bool) onVisibilityChange;

  @override
  Widget build(BuildContext context) {
    final isHouseholdVisible = event.reconciliationStatus == 'household_visible';
    final isPending = event.reconciliationStatus == 'pending';
    final isIgnored = event.reconciliationStatus == 'ignored';

    Color statusColor;
    String statusText;
    IconData statusIcon;

    if (isHouseholdVisible) {
      statusColor = Colors.green;
      statusText = 'Visible to household';
      statusIcon = Icons.visibility;
    } else if (isPending) {
      statusColor = Colors.orange;
      statusText = 'Pending review';
      statusIcon = Icons.hourglass_empty;
    } else if (isIgnored) {
      statusColor = Colors.grey;
      statusText = 'Ignored';
      statusIcon = Icons.block;
    } else {
      statusColor = Colors.blue;
      statusText = 'Personal';
      statusIcon = Icons.lock;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: statusColor.withValues(alpha: 0.1),
              child: Icon(Icons.credit_card, color: statusColor),
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
                  Text('${event.cardLabel}  •  ${event.paymentLabel}'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _SourceBadge(source: event.source),
                      const SizedBox(width: 8),
                      _ReconciliationBadge(
                        status: statusText,
                        color: statusColor,
                        icon: statusIcon,
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${_dateLabel(event.occurredAt)}  •  ${formatCurrency(event.amountValue, event.currency)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              icon: Icon(statusIcon, color: statusColor),
              onSelected: (value) async {
                if (value == 'toggle_visibility') {
                  await onVisibilityChange(!isHouseholdVisible);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'toggle_visibility',
                  child: Row(
                    children: [
                      Icon(isHouseholdVisible ? Icons.lock : Icons.visibility, size: 18),
                      const SizedBox(width: 8),
                      Text(isHouseholdVisible ? 'Make Personal' : 'Share with Household'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _dateLabel(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return 'Date unavailable';
    final date = parsed.toLocal();
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final label = _sourceLabel(source);
    final color = _sourceColor(source);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_sourceIcon(source), size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Color _sourceColor(String source) {
    return switch (source) {
      'ios_shortcut' => Colors.purple,
      'authenticated_api' => Colors.blue,
      'api_test' => Colors.orange,
      _ => Colors.grey,
    };
  }

  IconData _sourceIcon(String source) {
    return switch (source) {
      'ios_shortcut' => Icons.shortcut_rounded,
      'authenticated_api' => Icons.phone_android_rounded,
      'api_test' => Icons.science_rounded,
      _ => Icons.info_outline,
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
}

class _ReconciliationBadge extends StatelessWidget {
  const _ReconciliationBadge({
    required this.status,
    required this.color,
    required this.icon,
  });

  final String status;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            status,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}