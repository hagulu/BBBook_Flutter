import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_base_options.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/client_id_storage.dart';
import '../../../core/storage/token_storage.dart';
import '../data/auth_api.dart';
import '../data/auth_repository.dart';
import '../data/local_auth_store.dart';
import '../data/social_auth_service.dart';

/// 로그인/refresh/logout 전용 Dio. Authorization 헤더나 401 재시도 로직을
/// 거치지 않도록 [apiClientProvider]와 분리한다(base URL/timeout은 동일하게 공유).
final authDioProvider = Provider<Dio>((ref) {
  return Dio(buildApiBaseOptions());
});

/// Authorization 헤더 자동 첨부 및 401 refresh 재시도가 적용되는 공통 클라이언트.
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient();
});

final tokenStorageProvider = Provider<TokenStorage>((ref) {
  return TokenStorage();
});

final localAuthStoreProvider = Provider<LocalAuthStore>((ref) {
  return const LocalAuthStore();
});

final clientIdStorageProvider = Provider<ClientIdStorage>((ref) {
  return ClientIdStorage();
});

final authApiProvider = Provider<AuthApi>((ref) {
  return AuthApi(
    authDio: ref.watch(authDioProvider),
    apiClient: ref.watch(apiClientProvider),
    clientIdStorage: ref.watch(clientIdStorageProvider),
  );
});

final socialAuthServiceProvider = Provider<SocialAuthService>((ref) {
  return SocialAuthService();
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    authApi: ref.watch(authApiProvider),
    tokenStorage: ref.watch(tokenStorageProvider),
    socialAuthService: ref.watch(socialAuthServiceProvider),
  );
});
