import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cardsemble/features/household/presentation/household_notifier.dart';

class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key});

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HouseholdNotifier>().loadMembers();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Household Members'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: () => _showAddMemberDialog(context),
          ),
        ],
      ),
      body: Consumer<HouseholdNotifier>(
        builder: (context, notifier, _) {
          if (notifier.isLoading && notifier.members.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (notifier.error != null && notifier.members.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(notifier.error!),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => notifier.loadMembers(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (notifier.members.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.people_outline, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('No household members yet'),
                  const SizedBox(height: 8),
                  const Text('Tap + to add a member by user ID'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => _showAddMemberDialog(context),
                    child: const Text('Add Member'),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: notifier.members.length,
            itemBuilder: (context, index) {
              final member = notifier.members[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: member.isOwner
                        ? const Color(0xFF244A3A)
                        : Colors.blue.shade100,
                    child: Icon(
                      member.isOwner ? Icons.admin_panel_settings : Icons.person,
                      color: member.isOwner ? Colors.white : Colors.blue.shade700,
                    ),
                  ),
                  title: Text(member.userId),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Role: ${member.role}'),
                      Text('Joined: ${member.joinedAt}'),
                      if (member.inviteCode != null)
                        Text('Invite: ${member.inviteCode}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                  trailing: member.isOwner
                      ? const Chip(label: Text('Owner'), backgroundColor: Color(0xFF244A3A), labelStyle: TextStyle(color: Colors.white))
                      : null,
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showAddMemberDialog(BuildContext context) {
    final controller = TextEditingController();
    final notifier = context.read<HouseholdNotifier>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add Member'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'User ID',
            hintText: 'Enter the user ID to add',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final userId = controller.text.trim();
              if (userId.isEmpty) return;
              final success = await notifier.addMember(userId);
              if (success && dialogContext.mounted) {
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}