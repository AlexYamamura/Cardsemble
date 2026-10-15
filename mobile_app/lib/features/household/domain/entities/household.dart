class HouseholdPerson {
  const HouseholdPerson({
    required this.id,
    required this.displayName,
    required this.isDefault,
  });

  final String id;
  final String displayName;
  final bool isDefault;

  factory HouseholdPerson.fromJson(Map<String, dynamic> json) {
    return HouseholdPerson(
      id: json['person_id'] as String? ?? json['id'] as String,
      displayName: json['display_name'] as String,
      isDefault: json['is_default'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'person_id': id,
      'display_name': displayName,
      'is_default': isDefault,
    };
  }
}

class HouseholdMember {
  const HouseholdMember({
    required this.userId,
    required this.householdId,
    required this.role,
    required this.joinedAt,
    this.inviteCode,
  });

  final String userId;
  final String householdId;
  final String role;
  final String joinedAt;
  final String? inviteCode;

  bool get isOwner => householdId == userId;

  factory HouseholdMember.fromJson(Map<String, dynamic> json) {
    return HouseholdMember(
      userId: json['user_id'] as String,
      householdId: json['household_id'] as String? ?? json['user_id'] as String,
      role: json['role'] as String,
      joinedAt: json['joined_at'] as String,
      inviteCode: json['invite_code'] as String?,
    );
  }
}

class JoinHouseholdResult {
  const JoinHouseholdResult({
    required this.householdId,
    this.member,
  });

  final String householdId;
  final Map<String, dynamic>? member;
}