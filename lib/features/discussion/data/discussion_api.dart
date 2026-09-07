import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../models/discussion_answer.dart';
import '../models/discussion_topic.dart';

/// 주제 토론 기능의 API 호출.
///
/// 문서: ../../../../../api-doc/api-books-isbn13-discussions-get.md,
/// api-books-isbn13-discussions-post.md, api-discussions-topicId-get.md,
/// api-discussions-topicId-patch.md, api-discussions-topicId-delete.md,
/// api-discussions-topicId-close-post.md, api-discussions-topicId-reopen-post.md,
/// api-discussions-topicId-answers-get.md, api-discussions-topicId-answers-post.md,
/// api-discussions-topicId-answers-answerId-patch.md,
/// api-discussions-topicId-answers-answerId-delete.md,
/// api-likes-targetType-targetId-post.md, api-likes-targetType-targetId-delete.md,
/// api-reports-post.md
///
/// 인증 필요 요청이므로 401 시 1회 재시도 후 실패하면 로그아웃 처리하는
/// [ApiClient]를 통해서만 호출한다(CLAUDE.md 인증 API 호출 규칙).
class DiscussionApi {
  DiscussionApi({required this._apiClient});

  final ApiClient _apiClient;

  /// GET /api/books/{isbn13}/discussions — 커서 기반 토론 주제 목록.
  /// [includeClosed]가 true면 닫힌 토론도 뒤에 이어서 내려온다.
  Future<DiscussionTopicsPage> getTopics({
    required String isbn13,
    int? cursor,
    bool includeClosed = false,
    int size = 20,
  }) async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        '/api/books/$isbn13/discussions',
        queryParameters: {
          'cursor': ?cursor,
          if (includeClosed) 'includeClosed': true,
          'size': size,
        },
      );
      return DiscussionTopicsPage.fromJson(_unwrapMap(response));
    } on DioException catch (e) {
      throw _mapError(e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// GET /api/discussions/{topicId} — 토론 주제 상세(책 정보 + 선택지 집계 포함).
  Future<DiscussionTopicDetail> getTopic(int topicId) async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        '/api/discussions/$topicId',
      );
      return DiscussionTopicDetail.fromJson(_unwrapMap(response));
    } on DioException catch (e) {
      throw _mapError(
        e,
        overrides: const {403: '숨김 처리된 토론입니다.', 404: '토론을 찾을 수 없습니다.'},
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// POST /api/books/{isbn13}/discussions — 토론 주제 작성. 반환값은 생성된 주제 ID.
  /// 작성 시점에는 마감일을 받지 않는다(생성 후 상세 화면에서만 설정).
  Future<int> createTopic({
    required String isbn13,
    required String title,
    required String content,
    required bool isSpoiler,
    List<String>? options,
  }) async {
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/books/$isbn13/discussions',
        data: {
          'title': title,
          'content': content,
          'isSpoiler': isSpoiler,
          'options': ?options,
        },
      );
      return _unwrapMap(response)['id'] as int;
    } on DioException catch (e) {
      throw _mapError(e, overrides: const {400: '입력값을 확인해주세요.'});
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// PATCH /api/discussions/{topicId} — 본인 주제 수정. 전달한 필드만 변경된다.
  ///
  /// [options]는 "기존 선택지 전체 + 새로 추가할 선택지"만 허용되므로, 새
  /// 선택지가 없으면 아예 보내지 않는다(호출부에서 null로 전달).
  Future<void> patchTopic({
    required int topicId,
    String? title,
    String? content,
    bool? isSpoiler,
    List<String>? options,
  }) async {
    try {
      await _apiClient.dio.patch<Map<String, dynamic>>(
        '/api/discussions/$topicId',
        data: {
          'title': ?title,
          'content': ?content,
          'isSpoiler': ?isSpoiler,
          'options': ?options,
        },
      );
    } on DioException catch (e) {
      throw _mapError(
        e,
        overrides: const {
          400: '입력값을 확인해주세요.',
          404: '토론이 존재하지 않거나 본인 작성이 아닙니다.',
          409: '마감된 토론은 내용을 수정할 수 없습니다.',
        },
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// PATCH /api/discussions/{topicId} — 마감일만 변경. [closesAt]이 null이면
  /// 마감일을 제거한다(닫힌 토론에서도 이 단독 수정은 허용된다).
  Future<void> patchClosesAt({
    required int topicId,
    required DateTime? closesAt,
  }) async {
    try {
      await _apiClient.dio.patch<Map<String, dynamic>>(
        '/api/discussions/$topicId',
        data: {'closesAt': closesAt?.toUtc().toIso8601String()},
      );
    } on DioException catch (e) {
      throw _mapError(
        e,
        overrides: const {
          400: '마감일 형식이 올바르지 않습니다.',
          404: '토론이 존재하지 않거나 본인 작성이 아닙니다.',
          409: '마감일을 지난 시각으로 바꿀 수 없습니다.',
        },
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// POST /api/discussions/{topicId}/close — 본인 주제 직접 닫기.
  Future<void> closeTopic(int topicId) async {
    try {
      await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/discussions/$topicId/close',
      );
    } on DioException catch (e) {
      throw _mapError(
        e,
        overrides: const {
          404: '토론이 존재하지 않거나 본인 작성이 아닙니다.',
          409: '이미 닫힌 토론입니다.',
        },
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// POST /api/discussions/{topicId}/reopen — 직접 닫은 주제 다시 열기.
  Future<void> reopenTopic(int topicId) async {
    try {
      await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/discussions/$topicId/reopen',
      );
    } on DioException catch (e) {
      throw _mapError(
        e,
        overrides: const {
          404: '토론이 존재하지 않거나 본인 작성이 아닙니다.',
          409: '마감일이 지나 자동으로 닫힌 토론은 다시 열 수 없습니다.',
        },
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// DELETE /api/discussions/{topicId} — 본인 주제 삭제.
  Future<void> deleteTopic(int topicId) async {
    try {
      await _apiClient.dio.delete<Map<String, dynamic>>(
        '/api/discussions/$topicId',
      );
    } on DioException catch (e) {
      throw _mapError(
        e,
        overrides: const {404: '토론이 존재하지 않거나 본인 작성이 아닙니다.'},
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// GET /api/discussions/{topicId}/answers — 페이지 기반 답변 목록(최신순).
  Future<DiscussionAnswersPage> getAnswers({
    required int topicId,
    int page = 0,
    int size = 20,
  }) async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        '/api/discussions/$topicId/answers',
        queryParameters: {'page': page, 'size': size},
      );
      return DiscussionAnswersPage.fromJson(_unwrapMap(response));
    } on DioException catch (e) {
      throw _mapError(e, overrides: const {404: '토론을 찾을 수 없습니다.'});
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// POST /api/discussions/{topicId}/answers — 답변 작성.
  ///
  /// 선택지 토론에서는 `optionId` 필드를 반드시 보내야 하고, 명시적 null이
  /// "기타"다. 자유 토론([withOption]이 false)이면 필드를 아예 보내지 않는다.
  Future<void> createAnswer({
    required int topicId,
    required String content,
    required bool withOption,
    int? optionId,
  }) async {
    try {
      await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/discussions/$topicId/answers',
        data: {
          'content': content,
          if (withOption) 'optionId': optionId,
        },
      );
    } on DioException catch (e) {
      throw _mapError(
        e,
        overrides: const {
          400: '답변 내용을 확인해주세요.',
          404: '토론을 찾을 수 없습니다.',
          409: '닫힌 토론에는 답변을 작성할 수 없습니다.',
        },
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// PATCH /api/discussions/{topicId}/answers/{answerId} — 본인 답변 본문 수정.
  /// 선택지(optionId) 변경 UI는 제공하지 않으므로 본문만 보낸다.
  Future<void> patchAnswer({
    required int topicId,
    required int answerId,
    required String content,
  }) async {
    try {
      await _apiClient.dio.patch<Map<String, dynamic>>(
        '/api/discussions/$topicId/answers/$answerId',
        data: {'content': content},
      );
    } on DioException catch (e) {
      throw _mapError(
        e,
        overrides: const {
          400: '답변 내용을 확인해주세요.',
          404: '답변이 존재하지 않거나 본인 작성이 아닙니다.',
          409: '닫힌 토론의 답변은 수정할 수 없습니다.',
        },
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// DELETE /api/discussions/{topicId}/answers/{answerId} — 본인 답변 삭제.
  Future<void> deleteAnswer({
    required int topicId,
    required int answerId,
  }) async {
    try {
      await _apiClient.dio.delete<Map<String, dynamic>>(
        '/api/discussions/$topicId/answers/$answerId',
      );
    } on DioException catch (e) {
      throw _mapError(
        e,
        overrides: const {404: '답변이 존재하지 않거나 본인 작성이 아닙니다.'},
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// POST /api/likes/{targetType}/{targetId} — 공감 추가. 반환값은 변경 후 공감 수.
  Future<int> postLike({
    required String targetType,
    required int targetId,
  }) async {
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/likes/$targetType/$targetId',
      );
      return _unwrapMap(response)['likeCount'] as int;
    } on DioException catch (e) {
      throw _mapError(e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// DELETE /api/likes/{targetType}/{targetId} — 공감 취소. 반환값은 변경 후 공감 수.
  Future<int> deleteLike({
    required String targetType,
    required int targetId,
  }) async {
    try {
      final response = await _apiClient.dio.delete<Map<String, dynamic>>(
        '/api/likes/$targetType/$targetId',
      );
      return _unwrapMap(response)['likeCount'] as int;
    } on DioException catch (e) {
      throw _mapError(e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// POST /api/reports — 토론 주제/답변 신고.
  Future<void> postReport({
    required String targetType,
    required int targetId,
    required String reason,
    String? content,
  }) async {
    try {
      await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/reports',
        data: {
          'targetType': targetType,
          'targetId': targetId,
          'reason': reason,
          'content': ?content,
        },
      );
    } on DioException catch (e) {
      throw _mapError(
        e,
        overrides: const {404: '신고 대상을 찾을 수 없습니다.', 409: '이미 신고한 콘텐츠입니다.'},
      );
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

  ApiException _mapError(DioException e, {Map<int, String>? overrides}) {
    final statusCode = e.response?.statusCode;
    final message =
        overrides?[statusCode] ??
        switch (statusCode) {
          400 => '입력값을 확인해주세요.',
          401 => '인증에 실패했습니다.',
          403 => '접근할 수 없는 콘텐츠입니다.',
          404 => '존재하지 않거나 접근할 수 없습니다.',
          409 => '이미 처리된 요청입니다.',
          _ => '요청 처리 중 오류가 발생했습니다.',
        };
    return ApiException(message, statusCode: statusCode, cause: e);
  }
}
