import 'package:cardsemble/core/core.dart';
import 'package:cardsemble/features/card_events/domain/card_events_domain.dart';

abstract class CardEventRepository {
  Future<Result<List<CardEventRecord>>> loadCardEvents();
  Future<Result<void>> setHouseholdVisible(String eventId, bool visible);
}