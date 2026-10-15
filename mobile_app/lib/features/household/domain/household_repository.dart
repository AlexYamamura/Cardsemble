import 'package:cardsemble/core/core.dart';
import 'package:cardsemble/features/household/domain/household_domain.dart';

abstract class HouseholdRepository {
  Future<Result<List<HouseholdPerson>>> loadPeople();
  Future<Result<HouseholdPerson>> createPerson(String displayName, {bool isDefault = false});
  Future<Result<void>> updatePerson(String personId, String displayName, {bool? isDefault});
  Future<Result<void>> deletePerson(String personId);
  Future<Result<List<HouseholdMember>>> loadMembers();
  Future<Result<void>> addMember(String userId);
  Future<Result<JoinHouseholdResult>> joinByInviteCode(String inviteCode);
}