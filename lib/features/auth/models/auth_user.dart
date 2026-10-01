class AuthUser {
  const AuthUser({
    required this.id,
    required this.nickname,
    required this.profileImageUrl,
    required this.isFinishedBooksPublic,
    this.isSanctioned = false,
    this.sanction,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as int,
      nickname: json['nickname'] as String?,
      profileImageUrl: json['profileImageUrl'] as String?,
      isFinishedBooksPublic: json['isFinishedBooksPublic'] as bool? ?? false,
      isSanctioned: json['isSanctioned'] as bool? ?? false,
      sanction: json['sanction'] is Map<String, dynamic>
          ? UserSanction.fromJson(json['sanction'] as Map<String, dynamic>)
          : null,
    );
  }

  final int id;
  final String? nickname;
  final String? profileImageUrl;
  final bool isFinishedBooksPublic;
  final bool isSanctioned;
  final UserSanction? sanction;
}

class UserSanction {
  const UserSanction({
    required this.reason,
    required this.reasonLabel,
    required this.isPermanent,
    required this.endsAt,
  });

  factory UserSanction.fromJson(Map<String, dynamic> json) => UserSanction(
    reason: json['reason'] as String?,
    reasonLabel: json['reasonLabel'] as String?,
    isPermanent: json['isPermanent'] as bool? ?? false,
    endsAt: DateTime.tryParse(json['endsAt'] as String? ?? ''),
  );

  final String? reason;
  final String? reasonLabel;
  final bool isPermanent;
  final DateTime? endsAt;
}
