import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cardsemble/theme/app_colors.dart';
import 'package:cardsemble/core/widgets/settings_gear_menu.dart';
import 'package:cardsemble/features/card_catalog/data/card_catalog_repository.dart';
import 'package:cardsemble/features/card_catalog/domain/entities/card_catalog_card.dart';
import 'package:cardsemble/features/card_optimizer/data/card_optimizer_repository.dart';
import 'package:cardsemble/features/card_optimizer/presentation/card_optimizer_screen.dart';

/// Research surface for browsing credit cards.
///
/// Keeps the search bar at the top. Directly below it is a separate dropdown
/// card listing matching cards to select from; choosing one adds it to the
/// white-background selected-cards table underneath. Tapping a row in that
/// table opens a detail sheet with more information about the card.
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
  final Set<String> _selectedIds = <String>{};
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadCards();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

  bool _matches(CardCatalogCard card) {
    final query = _query.toLowerCase();
    return query.isEmpty ? false : card.searchText.contains(query);
  }

  List<CardCatalogCard> get _searchResults {
    final results = _allCards.where(_matches).toList(growable: false);
    results.sort((a, b) => a.name.compareTo(b.name));
    return results;
  }

  List<CardCatalogCard> get _selectedCards {
    final list = _allCards
        .where((card) => _selectedIds.contains(card.id))
        .toList(growable: false);
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  void _toggleCard(CardCatalogCard card) {
    setState(() {
      if (_selectedIds.contains(card.id)) {
        _selectedIds.remove(card.id);
      } else {
        _selectedIds.add(card.id);
      }
    });
  }

  void _showCardDetail(CardCatalogCard card) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _CardDetailSheet(card: card),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
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
          // Search bar at the top (previous format).
          _buildSearchBar(),
          const Divider(height: 1),
          // Separate dropdown of matching cards to select from.
          _buildSearchDropdown(),
          const Divider(height: 1),
          // White-background table of the selected cards.
          _buildSelectedTable(),
          // Full available catalog list below (previous commit behavior).
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
                : _buildAvailableList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search credit cards',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _query.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                  },
                )
              : null,
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: AppColors.outline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: AppColors.primary),
          ),
        ),
      ),
    );
  }

  /// Dropdown of matching cards, shown directly below the search bar.
  Widget _buildSearchDropdown() {
    final results = _searchResults;
    if (_query.isEmpty || results.isEmpty) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: 220,
      child: Card(
        color: AppColors.surface,
        elevation: 4,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: results.length,
          itemBuilder: (context, index) {
            final card = results[index];
            final isSelected = _selectedIds.contains(card.id);
            return ListTile(
              dense: true,
              leading: const Icon(Icons.credit_card, size: 20),
              title: Text(card.name),
              subtitle: Text(
                '${card.issuer ?? ''} ${card.network ?? ''}'.trim(),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              trailing: isSelected
                  ? const Icon(Icons.check_circle, color: AppColors.primary)
                  : const Icon(Icons.add, color: AppColors.primary),
              onTap: () => _toggleCard(card),
            );
          },
        ),
      ),
    );
  }

  /// White-background table of the cards the user has selected.
  Widget _buildSelectedTable() {
    return SizedBox(
      height: 260,
      child: Column(
        children: [
          _buildOptimizerButton(),
          _buildSelectedTableHeader(),
          Expanded(
            child: _selectedCards.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.credit_card_outlined,
                          size: 48,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Select a card from the dropdown above',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _selectedCards.length,
                    itemBuilder: (context, index) {
                      final card = _selectedCards[index];
                      return _SelectedRow(
                        card: card,
                        onTap: () => _showCardDetail(card),
                        onRemove: () => _toggleCard(card),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// Button row above the selected-cards table.
  ///
  /// "Card Optimizer" opens the optimizer for the currently selected cards.
  /// The tune icon opens the custom point multiplier settings.
  Widget _buildOptimizerButton() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _selectedCards.isEmpty ? null : _openCardOptimizer,
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('Card Optimizer'),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: _openMultiplierSettings,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: const Icon(Icons.tune, size: 18),
          ),
        ],
      ),
    );
  }

  void _openCardOptimizer() {
    final cards = _selectedCards;
    if (cards.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CardOptimizerScreen(
          selectedCards: List<CardCatalogCard>.unmodifiable(cards),
          repository: context.read<CardOptimizerRepository>(),
        ),
      ),
    );
  }

  Future<void> _openMultiplierSettings() async {
    final repository = context.read<CardOptimizerRepository>();
    final saved = await showCardOptimizerSettings(
      context: context,
      repository: repository,
      cards: _selectedCards,
    );
    if (saved == null || !mounted) return;
    await repository.saveTypeMultipliers(saved);
    setState(() {});
  }

  Widget _buildSelectedTableHeader() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: const [
          Expanded(
            flex: 3,
            child: Text(
              'Card Name',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Issuer',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Card Type',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  /// Full available catalog list (previous commit behavior).
  Widget _buildAvailableList() {
    final cards = _allCards
        .where((card) => _query.isEmpty || _matches(card))
        .toList(growable: false);
    cards.sort((a, b) => a.name.compareTo(b.name));
    if (cards.isEmpty) {
      return const Center(child: Text('No matching cards'));
    }
    return ListView.builder(
      itemCount: cards.length,
      itemBuilder: (context, index) {
        final card = cards[index];
        final isSelected = _selectedIds.contains(card.id);
        return ListTile(
          dense: true,
          leading: const Icon(Icons.credit_card_outlined),
          title: Text(card.name),
          subtitle: Text(
            '${card.issuer ?? ''} ${card.network ?? ''}'.trim(),
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          trailing: isSelected
              ? const Icon(Icons.check_circle, color: AppColors.primary)
              : const Icon(Icons.add_circle_outline, color: AppColors.primary),
          onTap: () => _toggleCard(card),
        );
      },
    );
  }
}

/// A row in the selected-cards table.
class _SelectedRow extends StatelessWidget {
  const _SelectedRow({
    required this.card,
    required this.onTap,
    required this.onRemove,
  });

  final CardCatalogCard card;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  card.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  card.issuer ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  card.type ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet showing more information about a card from the table body.
class _CardDetailSheet extends StatelessWidget {
  const _CardDetailSheet({required this.card});

  final CardCatalogCard card;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.credit_card, color: AppColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    card.name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _DetailRow(label: 'Issuer', value: card.issuer ?? '—'),
            _DetailRow(label: 'Network', value: card.network ?? '—'),
            _DetailRow(label: 'Type', value: card.type ?? '—'),
            _DetailRow(label: 'Segment', value: card.segment ?? '—'),
            _DetailRow(label: 'Country', value: card.country ?? '—'),
            if (card.annualFee != null)
              _DetailRow(
                label: 'Annual fee',
                value: _formatMoney(
                  card.annualFee!.amount,
                  card.annualFee!.currency,
                ),
              ),
            if (card.fxFee != null)
              _DetailRow(
                label: 'FX fee',
                value: '${card.fxFee!.percent?.toStringAsFixed(2) ?? '—'}%',
              ),
            if (card.creditRequired?.scoreBand != null)
              _DetailRow(
                label: 'Credit required',
                value: card.creditRequired!.scoreBand!,
              ),
            if (card.rewards != null && card.rewards!.currency != null)
              _DetailRow(
                label: 'Rewards currency',
                value: card.rewards!.currency!,
              ),
            const Divider(height: 24),
            if (card.benefits.isNotEmpty) ...[
              const Text(
                'Benefits',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              const SizedBox(height: 8),
              ...card.benefits.map(
                (benefit) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '• ${benefit.title ?? benefit.id ?? 'Benefit'}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (card.rewards != null &&
                card.rewards!.categories.isNotEmpty) ...[
              const Text(
                'Elevated category spending',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              const SizedBox(height: 8),
              ...card.rewards!.categories.map(
                (category) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _ElevatedCategoryRow(category: category),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (card.signupBonus != null) ...[
              const Text(
                'Signup bonus',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              const SizedBox(height: 8),
              _DetailRow(
                label: 'Amount',
                value: _formatMoney(
                  card.signupBonus!.amount,
                  card.signupBonus!.unit,
                ),
              ),
              if (card.signupBonus!.spendRequired != null)
                _DetailRow(
                  label: 'Spend required',
                  value: _formatMoney(
                    card.signupBonus!.spendRequired,
                    card.signupBonus!.spendCurrency,
                  ),
                ),
              if (card.signupBonus!.months != null)
                _DetailRow(
                  label: 'Within',
                  value: '${card.signupBonus!.months} months',
                ),
              const SizedBox(height: 12),
            ],
            // Notes section removed per user request
            if (card.officialUrl != null) ...[
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: const Text('Official site'),
                onTap: () {},
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatMoney(num? amount, String? unit) {
    if (amount == null) return '—';
    final formatted = amount is int
        ? amount.toString()
        : amount.toStringAsFixed(2);
    return unit != null ? '$unit $formatted' : formatted;
  }
}

/// Shared modal bottom sheet for editing type multipliers.
///
/// Loads current multipliers, derives keys from the supplied cards plus defaults,
/// renders validated decimal fields, offers reset-to-1.0, and persists on Save.
/// Returns the new [Map<String, double>] when Save is pressed, or `null` on
/// Cancel or if the sheet is dismissed without saving.
Future<Map<String, double>?> showCardOptimizerSettings({
  required BuildContext context,
  required CardOptimizerRepository repository,
  required List<CardCatalogCard> cards,
}) async {
  final current = await repository.loadTypeMultipliers();
  final types = <String>{};
  for (final card in cards) {
    types.add(repository.rewardTypeFor(card));
  }
  final allKeys = <String>{};
  allKeys.addAll(current.keys);
  allKeys.addAll(types);
  final effective = Map<String, double>.from(current);
  for (final k in allKeys) {
    effective.putIfAbsent(k, () => 1.0);
  }

  final controllers = <String, TextEditingController>{};
  for (final key in allKeys) {
    final value = effective[key] ?? 1.0;
    controllers[key] = TextEditingController(text: value.toStringAsFixed(2));
  }

  return showModalBottomSheet<Map<String, double>?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 12),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Point Multipliers',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ...allKeys.map(
              (key) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _typeLabel(key),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: controllers[key],
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        suffixText: 'x',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    final result = <String, double>{};
                    var valid = true;
                    for (final key in allKeys) {
                      final text = controllers[key]!.text;
                      final parsed = double.tryParse(text);
                      if (parsed == null || parsed <= 0) {
                        valid = false;
                        break;
                      }
                      result[key] = parsed;
                    }
                    if (!valid) return;
                    Navigator.of(context).pop(result);
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

String _typeLabel(String key) {
  switch (key) {
    case 'points':
      return 'Points multiplier';
    case 'cash':
      return 'Cash multiplier';
    case 'travel':
      return 'Travel multiplier';
    case 'other':
      return 'Other multiplier';
    default:
      return 'Multiplier';
  }
}

/// A detail row showing an elevated reward category with its points per dollar.
class _ElevatedCategoryRow extends StatelessWidget {
  const _ElevatedCategoryRow({required this.category});

  final CardRewardCategory category;

  @override
  Widget build(BuildContext context) {
    final points = category.pointsPerDollar;
    return Row(
      children: [
        const SizedBox(width: 110),
        Expanded(
          child: Text(
            category.label ?? 'Unnamed category',
            style: const TextStyle(fontSize: 13),
          ),
        ),
        if (points != null)
          Text(
            '${points.toStringAsFixed(1)}x',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
      ],
    );
  }
}

/// A detail row inside the card detail sheet.
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
