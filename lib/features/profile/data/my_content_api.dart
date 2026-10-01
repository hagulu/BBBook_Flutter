import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../models/my_content_book.dart';
import '../models/my_discussion_answer_summary.dart';
import '../models/my_discussion_summary.dart';
import '../models/my_review_summary.dart';

/// "내가 작성한 콘텐츠" 목록 API 호출(`my-content-screens.md` §1, §3-4, §4-4,
/// §5-4). 독후감은 로컬 DB에서 직접 조회한다([MyReflectionListController]
/// 참고 — 서버 목록 API는 상세로 이동할 로컬 PK를 주지 않아 동기화 타이밍
/// 문제가 있었다).
///
/// 문서: ../../../../../api-doc/api-me-reviews-get.md,
/// api-me-discussions-get.md, api-me-discussion-answers-get.md
///
/// 인증 필요 요청이므로 401 시 1회 재시도 후 실패하면 로그아웃 처리하는
/// [ApiClient]를 통해서만 호출한다(CLAUDE.md 인증 API 호출 규칙).
class MyContentApi {
  MyContentApi({required this._apiClient});

  final ApiClient _apiClient;

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
      isHidden: (item) => item.isHidden,
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
      isHidden: (item) => item.isHidden,
    );
  }

  /// GET /api/me/discussion-answers
  Future<MyContentPage<MyDiscussionAnswerSummary>> fetchDiscussionAnswers({
    int? cursor,
    required int size,
  }) {
    return _fetchPage(
      '/api/me/discussion-answers',
      cursor: cursor,
      size: size,
      itemFromJson: MyDiscussionAnswerSummary.fromJson,
      isHidden: (item) => item.isHidden,
    );
  }

  /// 숨김 처리된 항목은 목록에서 제외한다. 걸러진 뒤 [size]보다 적게 남으면
  /// 다음 페이지를 이어 조회해 채운다 — 스크롤 기반 추가 로딩이라 목록이
  /// 짧게 끝나면 다음 페이지 요청이 일어나지 않기 때문이다.
  Future<MyContentPage<T>> _fetchPage<T>(
    String path, {
    int? cursor,
    required int size,
    required T Function(Map<String, dynamic> json) itemFromJson,
    required bool Function(T item) isHidden,
  }) async {
    final items = <T>[];
    var page = await _fetchRawPage(
      path,
      cursor: cursor,
      size: size,
      itemFromJson: itemFromJson,
    );
    items.addAll(page.items.where((item) => !isHidden(item)));
    while (page.hasNext && items.length < size) {
      final nextCursor = page.nextCursor;
      if (nextCursor == null) break;
      page = await _fetchRawPage(
        path,
        cursor: nextCursor,
        size: size,
        itemFromJson: itemFromJson,
      );
      items.addAll(page.items.where((item) => !isHidden(item)));
    }
    return MyContentPage<T>(
      items: List.unmodifiable(items),
      nextCursor: page.nextCursor,
      hasNext: page.hasNext,
    );
  }

  Future<MyContentPage<T>> _fetchRawPage<T>(
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
