import 'package:flutter/material.dart';

import 'package:cardsemble/features/card_catalog/domain/entities/card_catalog_card.dart';
import 'package:cardsemble/features/card_optimizer/data/card_optimizer_repository.dart';
import 'package:cardsemble/features/card_optimizer/domain/entities/optimized_result.dart';
import 'package:cardsemble/features/research/presentation/research_screen.dart';
import 'package:cardsemble/theme/app_colors.dart';

class CardOptimizerScreen extends StatefulWidget {
  const CardOptimizerScreen({
    required this.selectedCards,
    required this.repository,
    super.key,
  });

  final List<CardCatalogCard> selectedCards;
  final CardOptimizerRepository repository;

  @override
  State<CardOptimizerScreen> createState() => _CardOptimizerScreenState();
}

class _CardOptimizerScreenState extends State<CardOptimizerScreen> {
  late final List<OptimizedResult> _results;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadResults();
  }

  Future<void> _loadResults() async {
    final cards = widget.selectedCards;
    if (cards.isEmpty) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      return;
    }
    final multipliers = await widget.repository.loadTypeMultipliers();
    if (!mounted) return;
    final results = widget.repository.optimize(
      cards: cards,
      typeMultipliers: multipliers,
    );
    setState(() {
      _results = results;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Card Optimizer'),
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_results.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Card Optimizer'),
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          actions: [
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Point multipliers',
              onPressed: _openSettings,
            ),
          ],
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.auto_awesome, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'No rewards categories found',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Card Optimizer'),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Point multipliers',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Best card per rewards category',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ..._results.map((result) => _OptimizedResultCard(result: result)),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _openSettings() async {
    final result = await showCardOptimizerSettings(
      context: context,
      repository: widget.repository,
      cards: widget.selectedCards,
    );
    if (result == null || !mounted) return;
    // Persist new multipliers and recompute results.
    await widget.repository.saveTypeMultipliers(result);
    final updated = widget.repository.optimize(
      cards: widget.selectedCards,
      typeMultipliers: result,
    );
    setState(() => _results = updated);
  }
}

class _OptimizedResultCard extends StatelessWidget {
  const _OptimizedResultCard({required this.result});

  final OptimizedResult result;

  String _rateUnit(String rewardType) {
    switch (rewardType) {
      case 'cash':
        return '\$';
      case 'travel':
        return 'pt';
      case 'points':
      case 'other':
      default:
        return 'pt';
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = this.result;
    final effective = result.effectivePointsPerDollar;
    final base = result.basePointsPerDollar;
    final multiplier = result.multiplier;
    final capText = result.isUncapped
        ? 'Uncapped'
        : result.capDescription ?? '—';
    final rateUnit = _rateUnit(result.rewardType);
    final rateSuffix = '$rateUnit/dollar';
    final effectiveRate = base * multiplier;

    final Color tierColor;
    if (effectiveRate >= 3.0) {
      tierColor = Colors.green;
    } else if (effectiveRate >= 2.0) {
      tierColor = Colors.amber;
    } else {
      tierColor = Colors.orange;
    }

    return Card(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    result.category.label ?? 'Unnamed category',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${effective.toStringAsFixed(1)} $rateSuffix',
                  style: TextStyle(
                    fontSize: 14,
                    color: tierColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Best card: ${result.bestCard.name}',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            Text(
              'Base rate: ${base.toStringAsFixed(1)} $rateSuffix',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.trending_up, size: 16, color: Colors.green),
                const SizedBox(width: 4),
                Text(
                  'Effective: $effectiveRate $rateSuffix',
                  style: const TextStyle(fontSize: 12, color: Colors.green),
                ),
              ],
            ),
            if (result.capDescription != null) ...[
              const SizedBox(height: 6),
              Text(
                'Cap: $capText',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Multiplier: ${multiplier.toStringAsFixed(2)}x',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
