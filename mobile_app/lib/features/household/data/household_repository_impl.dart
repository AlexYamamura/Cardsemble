import 'package:cardsemble/core/core.dart';
import 'package:cardsemble/features/household/domain/household_domain.dart';

class HouseholdRepositoryImpl implements HouseholdRepository {
  HouseholdRepositoryImpl({
    required SupabaseApiClient apiClient,
  }) : _apiClient = apiClient;

  final SupabaseApiClient _apiClient;

  @override
  Future<Result<List<HouseholdPerson>>> loadPeople() async {
    final result = await _apiClient.safeGet('/api/household/people');
    return result.map(
      (payload) => extractRecords(payload, 'people')
          .map(HouseholdPerson.fromJson)
          .toList(growable: false),
    );
  }

  @override
  Future<Result<HouseholdPerson>> createPerson(String displayName, {bool isDefault = false}) async {
    final result = await _apiClient.safePost(
      '/api/household/people',
      {'display_name': displayName.trim(), 'is_default': isDefault},
    );
    return result.map((payload) {
      if (payload['ok'] != true) {
        throw const NetworkException('Could not add household person.');
      }
      return HouseholdPerson.fromJson(payload['person'] as Map<String, dynamic>);
    });
  }

  @override
  Future<Result<void>> updatePerson(String personId, String displayName, {bool? isDefault}) async {
    final result = await _apiClient.safePatch(
      '/api/household/people/$personId',
      {'display_name': displayName.trim(), if (isDefault != null) 'is_default': isDefault},
    );
    return result.map((payload) {
      if (payload['ok'] != true) {
        throw const NetworkException('Could not update household person.');
      }
    });
  }

  @override
  Future<Result<void>> deletePerson(String personId) async {
    final result = await _apiClient.safeDelete('/api/household/people/$personId');
    return result.map((payload) {
      if (payload['ok'] != true) {
        throw const NetworkException('Could not delete household person.');
      }
    });
  }

  @override
  Future<Result<List<HouseholdMember>>> loadMembers() async {
    final result = await _apiClient.safeGet('/api/household/members');
    return result.map(
      (payload) => extractRecords(payload, 'members')
          .map(HouseholdMember.fromJson)
          .toList(growable: false),
    );
  }

  @override
  Future<Result<void>> addMember(String userId) async {
    final result = await _apiClient.safePost(
      '/api/household/members',
      {'user_id': userId},
    );
    return result.map((payload) {
      if (payload['ok'] != true) {
        throw const NetworkException('Could not add household member.');
      }
    });
  }

  @override
  Future<Result<JoinHouseholdResult>> joinByInviteCode(String inviteCode) async {
    final result = await _apiClient.safePost(
      '/api/household/members/join',
      {'invite_code': inviteCode},
    );
    return result.map((payload) {
      if (payload['ok'] != true) {
        throw NetworkException('Could not join household: ${payload['detail'] ?? 'Unknown error'}');
      }
      return JoinHouseholdResult(
        householdId: payload['household_id'] as String,
        member: payload['member'] as Map<String, dynamic>?,
      );
    });
  }
}