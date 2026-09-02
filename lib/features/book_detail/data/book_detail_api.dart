import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../bookshelf/models/user_book_create_result.dart';
import '../models/book_detail.dart';
import '../models/book_review.dart';

/// 검색 결과 경유 책 상세 화면의 API 호출.
///
/// 문서: ../../../../../api-doc/api-books-isbn.md, api-me-books-exists.md,
/// api-me-books.md, api-books-isbn13-reviews-get.md,
/// api-books-isbn13-reviews-post.md, api-books-isbn13-reviews-reviewId-patch.md,
/// api-books-isbn13-reviews-reviewId-delete.md,
/// api-likes-targetType-targetId-post.md, api-likes-targetType-targetId-delete.md,
/// api-reports-post.md
///
/// 인증 필요 요청이므로 401 시 1회 재시도 후 실패하면 로그아웃 처리하는
/// [ApiClient]를 통해서만 호출한다(CLAUDE.md 인증 API 호출 규칙).
class BookDetailApi {
  BookDetailApi({required this._apiClient});

  final ApiClient _apiClient;

  /// GET /api/books/{isbn} — ISBN10/13으로 책 상세 조회.
  Future<BookDetail> getBookDetail(String isbn) async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        '/api/books/$isbn',
      );
      return BookDetail.fromJson(_unwrapMap(response));
    } on DioException catch (e) {
      throw _mapError(e, overrides: const {404: '해당 책을 찾을 수 없습니다.'});
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// GET /api/me/books/exists — 서재 포함 여부(true면 userBookId 함께 반환).
  Future<({bool exists, int? userBookId})> checkExists(String isbn13) async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        '/api/me/books/exists',
        queryParameters: {'isbn13': isbn13},
      );
      final data = _unwrapMap(response);
      return (
        exists: data['exists'] as bool,
        userBookId: data['userBookId'] as int?,
      );
    } on DioException catch (e) {
      throw _mapError(e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// POST /api/me/books — ISBN13으로 서재 담기(선택적으로 완독 메타데이터 포함).
  /// 이미 서재에 있으면 409([ApiException.statusCode] == 409).
  /// [clientRequestId]는 로컬 `user_book` 생성 때 발급해 저장한 UUID를 받으며,
  /// 이 메서드 안에서는 절대 새로 만들지 않는다.
  /// [wantToReread]가 false면 문서의 기본값과 같으므로 필드를 생략하고,
  /// true일 때만 전송한다(null은 서버가 허용하지 않는다).
  Future<UserBookCreateResult> addToBookshelf({
    required String isbn13,
    required String status,
    required String clientRequestId,
    String? sourceType,
    bool wantToReread = false,
    double? myRating,
    String? shortReview,
    String? difficulty,
    String? finishedAt,
  }) async {
    final body = {
      'isbn13': isbn13,
      'status': status,
      'sourceType': ?sourceType,
      if (wantToReread) 'wantToReread': true,
      'myRating': ?myRating,
      'shortReview': ?shortReview,
      'difficulty': ?difficulty,
      'finishedAt': ?finishedAt,
      'clientRequestId': clientRequestId,
    };

    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/me/books',
        data: body,
        options: Options(headers: const {'X-Timezone': 'Asia/Seoul'}),
      );
      final data = _unwrapMap(response);
      return UserBookCreateResult.fromJson(data);
    } on DioException catch (e) {
      throw _mapError(e, overrides: const {409: '이미 서재에 담긴 책입니다.'});
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// GET /api/books/{isbn13}/reviews — 커서 기반 리뷰 목록(최신순).
  Future<ReviewsPage> getReviews({
    required String isbn13,
    int? cursor,
    int size = 20,
  }) async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        '/api/books/$isbn13/reviews',
        queryParameters: {'cursor': ?cursor, 'size': size},
      );
      return ReviewsPage.fromJson(_unwrapMap(response));
    } on DioException catch (e) {
      throw _mapError(e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// POST /api/books/{isbn13}/reviews — 리뷰 작성.
  Future<void> postReview({
    required String isbn13,
    double? rating,
    required String content,
    required bool isSpoiler,
  }) async {
    try {
      await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/books/$isbn13/reviews',
        data: {'rating': ?rating, 'content': content, 'isSpoiler': isSpoiler},
      );
    } on DioException catch (e) {
      throw _mapError(e, overrides: const {400: '리뷰 내용을 확인해주세요.'});
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// PATCH /api/books/{isbn13}/reviews/{reviewId} — 본인 리뷰 수정.
  /// [clearRating]이 true면 별점을 제거한다(문서 기준 null 전달 시 제거).
  Future<void> patchReview({
    required String isbn13,
    required int reviewId,
    double? rating,
    bool clearRating = false,
    String? content,
    bool? isSpoiler,
  }) async {
    final body = <String, dynamic>{
      'content': ?content,
      'isSpoiler': ?isSpoiler,
    };
    if (clearRating) {
      body['rating'] = null;
    } else if (rating != null) {
      body['rating'] = rating;
    }

    try {
      await _apiClient.dio.patch<Map<String, dynamic>>(
        '/api/books/$isbn13/reviews/$reviewId',
        data: body,
      );
    } on DioException catch (e) {
      throw _mapError(e, overrides: const {404: '리뷰가 존재하지 않거나 본인 작성이 아닙니다.'});
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// DELETE /api/books/{isbn13}/reviews/{reviewId} — 본인 리뷰 삭제.
  Future<void> deleteReview({
    required String isbn13,
    required int reviewId,
  }) async {
    try {
      await _apiClient.dio.delete<Map<String, dynamic>>(
        '/api/books/$isbn13/reviews/$reviewId',
      );
    } on DioException catch (e) {
      throw _mapError(e, overrides: const {404: '리뷰가 존재하지 않거나 본인 작성이 아닙니다.'});
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

  /// POST /api/reports — 콘텐츠 신고(REVIEW 등).
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
          404 => '존재하지 않거나 접근할 수 없습니다.',
          409 => '이미 처리된 요청입니다.',
          _ => '요청 처리 중 오류가 발생했습니다.',
        };
    return ApiException(message, statusCode: statusCode, cause: e);
  }
}
