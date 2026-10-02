import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_base_options.dart';
import '../data/app_update_dismissed_store.dart';
import '../data/app_version_api.dart';

/// 앱 버전 API는 인증이 필요 없어 인터셉터 없는 전용 Dio를 쓴다.
final _appVersionDioProvider = Provider<Dio>((ref) {
  return Dio(buildApiBaseOptions());
});

final appVersionApiProvider = Provider<AppVersionApi>((ref) {
  return AppVersionApi(dio: ref.watch(_appVersionDioProvider));
});

final appUpdateDismissedStoreProvider = Provider<AppUpdateDismissedStore>(
  (ref) => AppUpdateDismissedStore(),
);
