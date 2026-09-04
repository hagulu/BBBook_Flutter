import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../models/my_content_book.dart';
import '../models/my_discussion_answer_page.dart';
import '../models/my_discussion_summary.dart';
import '../models/my_reflection_summary.dart';
import '../models/my_review_summary.dart';

/// "내가 작성한 콘텐츠" 4개 목록 API 호출(`my-content-screens.md` §1, §2-4,
/// §3-4, §4-4, §5-4).
///
/// 문서: ../../../../../api-doc/api-me-reflections-get.md,
/// api-me-reviews-get.md, api-me-discussions-get.md,
/// api-me-discussion-answers-get.md
///
/// 인증 필요 요청이므로 401 시 1회 재시도 후 실패하면 로그아웃 처리하는
/// [ApiClient]를 통해서만 호출한다(CLAUDE.md 인증 API 호출 규칙).
class MyContentApi {
  MyContentApi({required this._apiClient});

  final ApiClient _apiClient;

  /// GET /api/me/reflections
  Future<MyContentPage<MyReflectionSummary>> fetchReflections({
    int? cursor,
    required int size,
  }) {
    return _fetchPage(
      '/api/me/reflections',
      cursor: cursor,
      size: size,
      itemFromJson: MyReflectionSummary.fromJson,
    );
  }

  /// GET /api/me/reviews
  Future<MyContentPage<MyReviewSummary>> fetchReviews({
    int? cursor,
    required int size,
  }) {
    return _fetchPage(
      '/api/me/reviews',
      cursor: cursor,
      size: size,
      itemFromJson: MyReviewSummary.fromJson,
    );
  }

  /// GET /api/me/discussions
  Future<MyContentPage<MyDiscussionSummary>> fetchDiscussions({
    int? cursor,
    required int size,
  }) {
    return _fetchPage(
      '/api/me/discussions',
      cursor: cursor,
      size: size,
      itemFromJson: MyDiscussionSummary.fromJson,
    );
  }

  /// GET /api/me/discussion-answers — 다른 3개 목록과 달리 커서가 아니라
  /// 0부터 시작하는 페이지 번호로 조회한다(`api-me-discussion-answers-get.md`).
  Future<MyDiscussionAnswerPage> fetchDiscussionAnswers({
    required int page,
    required int size,
  }) async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        '/api/me/discussion-answers',
        queryParameters: {'page': page, 'size': size},
      );
      return MyDiscussionAnswerPage.fromJson(_unwrapMap(response));
    } on DioException catch (e) {
      throw _mapError(e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  Future<MyContentPage<T>> _fetchPage<T>(
    String path, {
    int? cursor,
    required int size,
    required T Function(Map<String, dynamic> json) itemFromJson,
  }) async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        path,
        queryParameters: {'cursor': ?cursor, 'size': size},
      );
      return MyContentPage.fromJson(_unwrapMap(response), itemFromJson);
    } on DioException catch (e) {
      throw _mapError(e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  Map<String, dynamic> _unwrapMap(Response<Map<String, dynamic>> response) {
    final body = response.data;
    if (body == null || body['data'] is! Map<String, dynamic>) {
      throw const ApiException('서버 응답을 처리할 수 없습니다.');
    }
    return body['data'] as Map<String, dynamic>;
  }

  ApiException _mapError(DioException e) {
    final statusCode = e.response?.statusCode;
    final message = switch (statusCode) {
      401 => '인증에 실패했습니다.',
      _ => '요청 처리 중 오류가 발생했습니다.',
    };
    return ApiException(message, statusCode: statusCode, cause: e);
  }
}
