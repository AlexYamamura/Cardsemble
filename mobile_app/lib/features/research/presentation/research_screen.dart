import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cardsemble/core/widgets/settings_gear_menu.dart';
import 'package:cardsemble/features/accounts/presentation/accounts_notifier.dart';
import 'package:cardsemble/features/accounts/domain/entities/account.dart';

/// Placeholder research surface.
///
/// Shows the currently connected credit cards
/// ([AccountsNotifier.connections]) with a search bar above the list.
///
/// The search bar is wired up, but the filtering is placeholder logic only: it
/// filters the already-loaded connection list locally. Later this should
/// connect to a repository-backed list of all credit cards.
class ResearchScreen extends StatefulWidget {
  const ResearchScreen({
    super.key,
    this.onOpenSettings,
    this.onOpenManageHousehold,
  });

  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenManageHousehold;

  @override
  State<ResearchScreen> createState() => _ResearchScreenState();
}

class _ResearchScreenState extends State<ResearchScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final accounts = context.read<AccountsNotifier>();
      if (accounts.connections.isEmpty && !accounts.isLoading) {
        accounts.loadConnections();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matches(PlaidConnection connection) {
    final query = _query.toLowerCase();
    return connection.institutionName.toLowerCase().contains(query) ||
        (connection.institutionId != null &&
            connection.institutionId!.toLowerCase().contains(query)) ||
        connection.status.toLowerCase().contains(query);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Research'),
        actions: [
          SettingsGearMenu(
            onOpenSettings: widget.onOpenSettings,
            onOpenManageHousehold: widget.onOpenManageHousehold,
          ),
        ],
      ),
      body: Column(
        children: [
           Padding(
             padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
             child: TextField(
               controller: _searchController,
               decoration: InputDecoration(
                 hintText: 'Search connected cards',
                 prefixIcon: const Icon(Icons.search),
                 filled: true,
                 fillColor: Colors.white,
                 border: OutlineInputBorder(
                   borderRadius: BorderRadius.circular(8),
                 ),
               ),
               onChanged: (value) => setState(() => _query = value),
             ),
           ),
          Expanded(
            child: Consumer<AccountsNotifier>(
              builder: (context, accounts, _) {
                if (accounts.connections.isEmpty) {
                  if (accounts.isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (accounts.error != null) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(accounts.error!),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: () => accounts.loadConnections(),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    );
                  }
                  return const Center(child: Text('No connected credit cards'));
                }

                final matches =
                    accounts.connections.where(_matches).toList(growable: false);
                if (matches.isEmpty) {
                  return const Center(child: Text('No matching cards'));
                }

                return ListView.builder(
                  itemCount: matches.length,
                  itemBuilder: (context, index) {
                    final connection = matches[index];
                    return ListTile(
                      key: ValueKey(connection.itemId),
                      leading: const Icon(Icons.credit_card),
                      title: Text(connection.institutionName),
                      subtitle: Text(
                        'Status: ${connection.status}'
                            '${connection.institutionId != null ? ' · ${connection.institutionId}' : ''}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
