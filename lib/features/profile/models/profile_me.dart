/// `GET /api/me/profile` 응답 데이터.
class ProfileMe {
  const ProfileMe({
    required this.id,
    required this.nickname,
    required this.email,
    required this.profileImageUrl,
  });

  factory ProfileMe.fromJson(Map<String, dynamic> json) {
    return ProfileMe(
      id: json['id'] as int,
      nickname: json['nickname'] as String?,
      email: json['email'] as String?,
      profileImageUrl: json['profileImageUrl'] as String?,
    );
  }

  final int id;
  final String? nickname;
  final String? email;
  final String? profileImageUrl;
}
