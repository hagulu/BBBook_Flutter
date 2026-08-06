class AuthUser {
  const AuthUser({
    required this.id,
    required this.nickname,
    required this.profileImageUrl,
    required this.isFinishedBooksPublic,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as int,
      nickname: json['nickname'] as String?,
      profileImageUrl: json['profileImageUrl'] as String?,
      isFinishedBooksPublic: json['isFinishedBooksPublic'] as bool? ?? false,
    );
  }

  final int id;
  final String? nickname;
  final String? profileImageUrl;
  final bool isFinishedBooksPublic;
}
