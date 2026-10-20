import 'package:cardsemble/core/error/failure.dart';
import 'package:cardsemble/core/network/supabase_api_client.dart';
import 'package:cardsemble/features/card_catalog/domain/entities/card_catalog_card.dart';

/// Integration boundary for the future card catalog backend.
///
/// No catalog table, Edge Function route, or upstream feed exists in the
/// current repository. Implement this interface once one does, then register a
/// `CardCatalogRepository` in the service locator. Until then the repository is
/// intentionally unreferenced by the app.
abstract interface class CardCatalogSource {
  CardCatalogSource({
    required SupabaseApiClient apiClient,
  }) : _apiClient = apiClient;

  final SupabaseApiClient _apiClient;
  /// Fetches the requested catalog entries.
  ///
  /// The source may omit unknown ids. The repository treats omitted ids as
  /// unresolved rather than inventing placeholder cards.
  Future<Result<List<CardCatalogCard>>> fetchCards(Set<String> ids) async {
    final result = await _apiClient.safeGet('/api/card_catalog/cards');
    return result.map(
      (payload) => extractRecords(payload, 'cards')
          .map(CardCatalogCard.fromJson)
          .toList(growable: false),
    );
  }
}
