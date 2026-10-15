import 'package:flutter/material.dart';
import 'package:cardsemble/features/card_events/domain/card_events_domain.dart';

class CardEventsNotifier extends ChangeNotifier {
  CardEventsNotifier({
    required CardEventRepository cardEventRepository,
  }) : _cardEventRepository = cardEventRepository;

  final CardEventRepository _cardEventRepository;

  List<CardEventRecord> _events = [];
  bool _isLoading = false;
  String? _error;

  List<CardEventRecord> get events => _events;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadEvents() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _cardEventRepository.loadCardEvents();
      result.fold(
        (events) => _events = events,
        (failure) => _error = failure.message,
      );
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> setHouseholdVisible(String eventId, bool visible) async {
    _error = null;
    notifyListeners();

    try {
      final result = await _cardEventRepository.setHouseholdVisible(eventId, visible);
      return result.fold(
        (_) {
          final index = _events.indexWhere((e) => e.id == eventId);
          if (index != -1) {
            _events[index] = CardEventRecord(
              id: _events[index].id,
              amount: _events[index].amount,
              currency: _events[index].currency,
              occurredAt: _events[index].occurredAt,
              merchant: _events[index].merchant,
              cardLabel: _events[index].cardLabel,
              paymentLabel: _events[index].paymentLabel,
              source: _events[index].source,
              personId: _events[index].personId,
              reconciliationStatus: _events[index].reconciliationStatus,
            );
            notifyListeners();
          }
          return true;
        },
        (failure) {
          _error = failure.message;
          notifyListeners();
          return false;
        },
      );
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}