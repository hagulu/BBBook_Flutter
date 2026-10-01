import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../models/book_recommendation.dart';

/// 추천 도서 API 호출.
///
/// 문서: ../../../../../api-doc/api-me-recommendations-books-get.md
///
/// 인증 필요 요청이므로 401 시 1회 재시도 후 실패하면 로그아웃 처리하는
/// [ApiClient]를 통해서만 호출한다(CLAUDE.md 인증 API 호출 규칙).
class RecommendationApi {
  RecommendationApi({required this._apiClient});

  final ApiClient _apiClient;

  /// GET /api/me/recommendations/books — 완독 기록·카테고리 성향 기반 추천.
  /// 완독 기록·현재 책장 전체를 기준으로 서버가 계산하므로 미전송 dirty
  /// 변경을 먼저 반영하도록 [ApiClient.recordDependentOptions]를 붙인다 —
  /// 서재 포함 여부 조회(`BookDetailApi.checkExists`) 등 기존 기록 의존
  /// 요청과 같은 수준의 보장이다. 단, 요청 시점에 이미 다른 동기화가
  /// 진행 중이면 `BackgroundRecordSync.beforeNetworkRequest`가 그 완료를
  /// 기다리지 않고 바로 진행하는 기존 정책을 그대로 따르므로(새로 시작하는
  /// 동기화만 기다림), 방금 완독 처리한 책이 드물게 아직 반영되지 않은
  /// 채로 응답을 받을 수 있다 — 다른 기록 의존 API들도 동일하게 감수하는
  /// 한계라 이 API만 별도로 강한 보장을 추가하지 않았다.
  ///
  /// [size]는 목록당 추천 도서 수(1~7, 서버 기본값과 동일한 3). 다시읽기
  /// 추천 목록은 항상 1권이라 영향받지 않는다(api-doc).
  Future<List<BookRecommendationGroup>> getRecommendations({
    int size = 3,
  }) async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        '/api/me/recommendations/books',
        queryParameters: {'size': size},
        options: ApiClient.recordDependentOptions(),
      );
      return _unwrapList(response)
          .map(
            (e) => BookRecommendationGroup.fromJson(e as Map<String, dynamic>),
          )
          .toList();
    } on DioException catch (e) {
      throw _mapError(e, overrides: const {400: '요청 값을 확인해주세요.'});
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  List<dynamic> _unwrapList(Response<Map<String, dynamic>> response) {
    final body = response.data;
    if (body == null || body['data'] is! List) {
      throw const ApiException('서버 응답을 처리할 수 없습니다.');
    }
    return body['data'] as List<dynamic>;
  }

  ApiException _mapError(DioException e, {Map<int, String>? overrides}) {
    final statusCode = e.response?.statusCode;
    final message =
        overrides?[statusCode] ??
        switch (statusCode) {
          401 => '인증에 실패했습니다.',
          _ => '요청 처리 중 오류가 발생했습니다.',
        };
    return ApiException(message, statusCode: statusCode, cause: e);
  }
}
