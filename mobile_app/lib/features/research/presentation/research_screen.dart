import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cardsemble/core/widgets/settings_gear_menu.dart';
import 'package:cardsemble/features/card_catalog/data/card_catalog_repository.dart';
import 'package:cardsemble/features/card_catalog/domain/entities/card_catalog_card.dart';

/// Research surface for browsing credit cards.
///
/// Shows all available credit cards from the card catalog with a search bar
/// above the list. The search bar filters the card list by name.
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
  bool _isLoading = true;
  List<CardCatalogCard> _allCards = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadCards();
    });
  }

  Future<void> _loadCards() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    
    try {
      final repository = context.read<CardCatalogRepository>();
      final result = await repository.getAllCards();
      
      if (!mounted) return;
      
      if (result.isSuccess) {
        setState(() {
          _allCards = result.value;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = result.failure.message;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matches(CardCatalogCard card) {
    final query = _query.toLowerCase();
    return card.name.toLowerCase().contains(query);
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
                hintText: 'Search credit cards',
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
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: _loadCards,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : _allCards.isEmpty
                        ? const Center(child: Text('No credit cards available'))
                        : ListView.builder(
                            itemCount: _allCards.where(_matches).toList(growable: false).length,
                            itemBuilder: (context, index) {
                              final matches = _allCards.where(_matches).toList(growable: false);
                              final card = matches[index];
                              return ListTile(
                                leading: const Icon(Icons.credit_card),
                                title: Text(card.name),
                                trailing: const Icon(Icons.chevron_right),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
