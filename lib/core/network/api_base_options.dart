import 'package:dio/dio.dart';

import '../config/api_config.dart';

/// API 요청 공통 기본 설정(base URL, timeout). 인증 인터셉터가 붙는
/// [ApiClient]와 인증 전용 Dio([authDioProvider])가 같은 값을 쓰도록 여기서만 정의한다.
///
/// 이 앱은 한국어 전용 서비스라(book_item.dart의 X-Timezone 고정과 동일한
/// 전제) `Accept-Language: ko`를 기본으로 보낸다 — 헤더가 없으면 영어를
/// 기본값으로 응답하는 엔드포인트(추천 도서 문구 등, api-doc)가 한국어 UI
/// 사이에서 영어로 노출되는 걸 막는다.
BaseOptions buildApiBaseOptions({String baseUrl = ApiConfig.baseUrl}) {
  return BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 10),
    sendTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 10),
    headers: const {'Accept-Language': 'ko'},
  );
}
