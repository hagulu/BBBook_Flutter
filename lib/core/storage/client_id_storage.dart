import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// X-Client-Id 헤더에 쓸 설치 단위 클라이언트 식별자.
///
/// 최초 실행 시 생성해 시큐어 스토리지에 저장하고, 이후에는 저장된 값을 재사용한다
/// (api-auth-mobile-provider-login-post.md, api-auth-mobile-refresh-post.md).
class ClientIdStorage {
  ClientIdStorage({FlutterSecureStorage? storage, Uuid? uuid})
    : _storage = storage ?? const FlutterSecureStorage(),
      _uuid = uuid ?? const Uuid();

  static const _clientIdKey = 'client_id';

  final FlutterSecureStorage _storage;
  final Uuid _uuid;
  String? _cachedId;

  Future<String> getOrCreateClientId() async {
    final cached = _cachedId;
    if (cached != null) return cached;

    final stored = await _storage.read(key: _clientIdKey);
    if (stored != null) {
      _cachedId = stored;
      return stored;
    }

    final generated = _uuid.v4();
    await _storage.write(key: _clientIdKey, value: generated);
    _cachedId = generated;
    return generated;
  }
}
