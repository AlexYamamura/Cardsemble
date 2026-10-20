import 'package:cardsemble/core/error/failure.dart';
import 'package:cardsemble/core/network/supabase_api_client.dart';
import 'package:cardsemble/features/card_catalog/domain/card_catalog_source.dart';
import 'package:cardsemble/features/card_catalog/domain/entities/card_catalog_card.dart';

/// Implementation of [CardCatalogSource] that fetches from the Edge Function.
class CardCatalogSourceImpl implements CardCatalogSource {
  CardCatalogSourceImpl({required SupabaseApiClient apiClient}) : _apiClient = apiClient;

  final SupabaseApiClient _apiClient;

  @override
  Future<Result<List<CardCatalogCard>>> fetchCards(Set<String> ids) async {
    if (ids.isEmpty) {
      return const Success(<CardCatalogCard>[]);
    }

    final uri = Uri.parse('/api/card-catalog').replace(queryParameters: {
      'ids': ids.join(','),
    });

    final result = await _apiClient.safeGet(uri.toString());
    return result.map((payload) {
      // Expecting payload to be { "cards": [ ... ] }
      final List<dynamic> jsonArray = payload['cards'] as List<dynamic>;
      return jsonArray
          .map((json) => CardCatalogCard.fromJson(json as Map<String, dynamic>))
          .toList(growable: false);
    });
  }

  @override
  Future<Result<List<CardCatalogCard>>> fetchAllCards() async {
    // For fetching all cards, we don't pass any IDs
    // The endpoint should return all cards when no IDs are specified
    final result = await _apiClient.safeGet('/api/card-catalog');
    return result.map((payload) {
      // Expecting payload to be { "cards": [ ... ] }
      final List<dynamic> jsonArray = payload['cards'] as List<dynamic>;
      return jsonArray
          .map((json) => CardCatalogCard.fromJson(json as Map<String, dynamic>))
          .toList(growable: false);
    });
  }
}