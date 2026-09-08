import 'package:dio/dio.dart';

import '../config/api_config.dart';

/// API 요청 공통 기본 설정(base URL, timeout). 인증 인터셉터가 붙는
/// [ApiClient]와 인증 전용 Dio([authDioProvider])가 같은 값을 쓰도록 여기서만 정의한다.
BaseOptions buildApiBaseOptions({String baseUrl = ApiConfig.baseUrl}) {
  return BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 10),
    sendTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 10),
  );
}
