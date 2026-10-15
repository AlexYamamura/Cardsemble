import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cardsemble/features/accounts/presentation/accounts_notifier.dart';
import 'package:cardsemble/features/accounts/domain/accounts_domain.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final notifier = context.read<AccountsNotifier>();
      notifier.loadConnections();
      notifier.loadStatementCycles();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connected Accounts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: () => _syncAccounts(context),
            tooltip: 'Sync',
          ),
        ],
      ),
      body: Consumer<AccountsNotifier>(
        builder: (context, notifier, _) {
          // Show loading indicator when initially loading or when refreshing and no data yet
          if (notifier.isLoading && notifier.connections.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          return RefreshIndicator(
            onRefresh: () async {
              await notifier.loadConnections();
              await notifier.loadStatementCycles();
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildConnectionsSection(context, notifier),
                const SizedBox(height: 24),
                _buildStatementSection(context, notifier),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _linkNewAccount(context),
        icon: const Icon(Icons.add_link),
        label: const Text('Link Account'),
      ),
    );
  }

  Widget _buildConnectionsSection(BuildContext context, AccountsNotifier notifier) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Plaid Connections', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if (notifier.connections.isNotEmpty)
              Text('${notifier.connections.length} connected', style: const TextStyle(color: Colors.grey)),
          ],
        ),
        const SizedBox(height: 12),
        if (notifier.connections.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Icon(Icons.account_balance_outlined, size: 48, color: Colors.grey),
                  const SizedBox(height: 12),
                  const Text('No linked accounts yet'),
                  const SizedBox(height: 8),
                  const Text('Tap "Link Account" to connect your bank', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: notifier.connections.length,
            itemBuilder: (context, index) {
              final conn = notifier.connections[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: conn.status == 'connected' ? Colors.green.shade100 : Colors.orange.shade100,
                    child: Icon(
                      Icons.account_balance,
                      color: conn.status == 'connected' ? Colors.green.shade700 : Colors.orange.shade700,
                    ),
                  ),
                  title: Text(conn.institutionName),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Status: ${conn.status}'),
                      Text('Item ID: ${conn.itemId}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                  trailing: conn.status == 'connected'
                      ? Icon(Icons.check_circle, color: Colors.green.shade700)
                      : Icon(Icons.warning, color: Colors.orange.shade700),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildStatementSection(BuildContext context, AccountsNotifier notifier) {
    final summary = notifier.statementSummary;

    if (summary == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Statement Summary', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No statement data available'),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Statement Summary', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(summary.status, style: TextStyle(color: _statusColor(summary.status))),
          ],
        ),
        const SizedBox(height: 12),
        if (summary.total != null && summary.currency != null)
          Card(
            color: const Color(0xFF244A3A),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total Owed', style: TextStyle(color: Colors.white70)),
                  Text(
                    '${summary.currency!} ${summary.total!}',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: summary.accounts.map((account) {
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.blue.shade100,
                  child: Icon(Icons.credit_card, color: Colors.blue.shade700),
                ),
                title: Text(account.displayName ?? account.accountName),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (account.mask != null) Text('Ending in ${account.mask}'),
                    if (account.institutionName != null) Text(account.institutionName!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => _editDisplayName(context, notifier, account),
                  tooltip: 'Edit display name',
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Color _statusColor(String status) {
    switch (status.toUpperCase()) {
      case 'READY':
        return Colors.green;
      case 'WAITING_FOR_STATEMENTS':
        return Colors.orange;
      case 'ERROR':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  void _syncAccounts(BuildContext context) async {
    final notifier = context.read<AccountsNotifier>();
    final success = await notifier.syncConnections();
    if (!success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(notifier.error ?? 'Sync failed')),
      );
    }
  }

  void _linkNewAccount(BuildContext context) async {
    final notifier = context.read<AccountsNotifier>();
    final success = await notifier.createLinkToken();
    if (!success) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(notifier.error ?? 'Failed to create link token')),
        );
      }
      return;
    }

    if (notifier.linkToken != null) {
      // In a real app, you'd launch Plaid Link here
      // For now, show the link token
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Plaid Link Token'),
            content: SelectableText(notifier.linkToken!),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    }
  }

  void _editDisplayName(BuildContext context, AccountsNotifier notifier, StatementAccount account) {
    final controller = TextEditingController(text: account.displayName ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit: ${account.accountName}'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Display Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final String displayName = controller.text.trim();
              final bool isEmpty = displayName.isEmpty;
              final String? finalDisplayName = isEmpty ? null : displayName;
              final success = await notifier.updateDisplayName(account.accountId, finalDisplayName);
              if (context.mounted) {
                Navigator.pop(ctx);
              }
              if (!success && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(notifier.error ?? 'Failed to update')),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}