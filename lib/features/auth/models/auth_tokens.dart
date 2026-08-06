class AuthTokens {
  const AuthTokens({required this.accessToken, required this.expiresIn, required this.refreshToken});

  factory AuthTokens.fromJson(Map<String, dynamic> json) {
    return AuthTokens(
      accessToken: json['accessToken'] as String,
      expiresIn: json['expiresIn'] as int,
      refreshToken: json['refreshToken'] as String,
    );
  }

  final String accessToken;
  final int expiresIn;

  /// 모바일 전용 로그인/refresh 응답에는 필수 필드다
  /// (api-auth-mobile-provider-login-post.md, api-auth-mobile-refresh-post.md).
  final String refreshToken;
}
