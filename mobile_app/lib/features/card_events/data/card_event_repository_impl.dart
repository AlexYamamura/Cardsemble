import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cardsemble/core/core.dart';
import 'package:cardsemble/features/card_events/domain/card_events_domain.dart';

class CardEventRepositoryImpl implements CardEventRepository {
  CardEventRepositoryImpl({
    required ApiClient apiClient,
    required SupabaseClient supabase,
  })  : _apiClient = apiClient,
        _supabase = supabase;

  final ApiClient _apiClient;
  final SupabaseClient _supabase;

  @override
  Future<Result<List<CardEventRecord>>> loadCardEvents() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        return const FailureResult(AuthFailure('Your session has expired. Sign in again.'));
      }

      final data = await _supabase
          .from('card_events')
          .select(
              'event_id,user_id,person_id,occurred_at,amount,currency,merchant,card_label,payment_label,source,received_at')
          .eq('user_id', userId)
          .order('received_at', ascending: false)
          .order('event_id', ascending: true)
          .limit(200);

      final events = (data as List?)
              ?.map((row) => CardEventRecord.fromJson(row))
              .toList(growable: false) ??
          [];

      final reconData = await _supabase
          .from('card_event_reconciliations')
          .select('event_id,status')
          .eq('user_id', userId);

      final reconByEvent = <String, String>{};
      for (final row in (reconData as List)) {
        final eventId = row['event_id'] as String?;
        final status = row['status'] as String?;
        if (eventId != null && status != null) {
          reconByEvent[eventId] = status;
        }
      }

      return Success([
        for (final event in events)
          event.copyWith(reconciliationStatus: reconByEvent[event.id]),
      ]);
    } catch (error) {
      return FailureResult(DatabaseFailure('Could not load card events: $error'));
    }
  }

  @override
  Future<Result<void>> setHouseholdVisible(String eventId, bool visible) async {
    final result = await _apiClient.safePatch(
      '/api/card-events/$eventId/household-visible',
      {'household_visible': visible},
    );
    return result.map((payload) {
      if (payload['ok'] != true) {
        throw const NetworkException('Could not update event visibility.');
      }
    });
  }
}