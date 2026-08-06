import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// refreshToken을 시큐어 스토리지에 보관한다.
///
/// 원본(Next.js)은 HttpOnly 쿠키 기반 refresh token을 사용하지만,
/// 모바일 환경에서는 쿠키 대신 시큐어 스토리지에 저장하는 방식으로 대체한다.
class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _refreshTokenKey = 'refresh_token';

  final FlutterSecureStorage _storage;

  Future<void> saveRefreshToken(String refreshToken) {
    return _storage.write(key: _refreshTokenKey, value: refreshToken);
  }

  Future<String?> readRefreshToken() {
    return _storage.read(key: _refreshTokenKey);
  }

  Future<void> clearRefreshToken() {
    return _storage.delete(key: _refreshTokenKey);
  }
}
