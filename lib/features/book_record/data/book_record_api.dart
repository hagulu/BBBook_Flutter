import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../bookshelf/models/book_tag.dart';

/// 책 기록 상세 화면의 API 호출.
///
/// 문서: ../../../../../../api-doc/api-me-books-userBookId-patch.md,
/// api-me-books-userBookId-book-info-patch.md, api-me-books-userBookId-tags-post.md,
/// api-me-books-userBookId-tags-tagId-delete.md, api-me-tags-get.md,
/// api-me-books-userBookId-delete.md
///
/// 인증 필요 요청이므로 401 시 1회 재시도 후 실패하면 로그아웃 처리하는
/// [ApiClient]를 통해서만 호출한다(CLAUDE.md 인증 API 호출 규칙).
///
/// 이 클래스의 PATCH류 응답에는 `createdAt`/`updatedAt`이 내려오지 않으므로
/// `Map<String, dynamic>`(순수 data 파트)을 그대로 반환한다. `BookItem`으로
/// 변환하는 것은 로컬 행의 createdAt을 알고 있는 리포지토리 쪽 책임이다.
class BookRecordApi {
  BookRecordApi({required this._apiClient});

  final ApiClient _apiClient;

  /// PATCH /api/me/books/:userBookId — 독서 상태/진행률/평가 등 기본 기록 필드 수정.
  ///
  /// 각 파라미터는 null이면 요청 본문에서 생략된다(서버 쪽에서도 null은
  /// "변경 없음"으로 해석되므로 동일하다). [platformName]/[discoverySource]는
  /// 빈 문자열을 보내면 서버가 null로 저장한다(문서 기준). [startedAt]/
  /// [finishedAt]은 `yyyy-MM-dd` 형식 문자열이어야 한다.
  ///
  /// status를 FINISHED로 보낼 때 [finishedAt]을 생략하면, 서버가
  /// `X-Timezone` 헤더로 오늘 날짜를 계산해 자동 설정한다. 이 앱은 한국어
  /// 전용 서비스라 타임존 판별 플러그인 없이 'Asia/Seoul'을 고정으로 보낸다.
  Future<Map<String, dynamic>> patchRecord({
    required int userBookId,
    String? status,
    int? currentPage,
    double? myRating,
    String? shortReview,
    bool? isMasterpiece,
    String? sourceType,
    int? rereadCount,
    String? difficulty,
    String? startedAt,
    String? finishedAt,
    String? platformName,
    String? discoverySource,
  }) async {
    final body = <String, dynamic>{
      'status': ?status,
      'currentPage': ?currentPage,
      'myRating': ?myRating,
      'shortReview': ?shortReview,
      'isMasterpiece': ?isMasterpiece,
      'sourceType': ?sourceType,
      'rereadCount': ?rereadCount,
      'difficulty': ?difficulty,
      'startedAt': ?startedAt,
      'finishedAt': ?finishedAt,
      'platformName': ?platformName,
      'discoverySource': ?discoverySource,
    };

    try {
      final response = await _apiClient.dio.patch<Map<String, dynamic>>(
        '/api/me/books/$userBookId',
        data: body,
        options: Options(headers: const {'X-Timezone': 'Asia/Seoul'}),
      );
      return _unwrapMap(response);
    } on DioException catch (e) {
      throw _mapError(e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// PATCH /api/me/books/:userBookId/book-info — 표시용 제목/저자/출판사/총쪽수/표지 수정.
  ///
  /// [thumbnailFile]이 있으면 새 표지를 업로드하고, [removeThumbnail]이
  /// true이면 표지를 제거한다(둘 다 아니면 표지는 현재값 유지). [author],
  /// [publisher], [totalPages]는 null을 명시적으로 보내면 서버가 null로
  /// 저장한다(문서 기준, 메인 PATCH와 다른 의미론).
  Future<Map<String, dynamic>> patchBookInfo({
    required int userBookId,
    required String title,
    String? author,
    String? publisher,
    int? totalPages,
    File? thumbnailFile,
    bool removeThumbnail = false,
  }) async {
    final dataMap = {
      'title': title,
      'author': author,
      'publisher': publisher,
      'totalPages': totalPages,
    };

    try {
      final Response<Map<String, dynamic>> response;
      if (thumbnailFile != null || removeThumbnail) {
        final formData = FormData.fromMap({
          'data': MultipartFile.fromString(
            jsonEncode(dataMap),
            contentType: MediaType('application', 'json'),
          ),
          if (thumbnailFile != null)
            'thumbnail': await MultipartFile.fromFile(thumbnailFile.path),
        });
        response = await _apiClient.dio.patch<Map<String, dynamic>>(
          '/api/me/books/$userBookId/book-info',
          data: formData,
          queryParameters: {if (removeThumbnail) 'removeThumbnail': true},
        );
      } else {
        response = await _apiClient.dio.patch<Map<String, dynamic>>(
          '/api/me/books/$userBookId/book-info',
          data: dataMap,
        );
      }
      return _unwrapMap(response);
    } on DioException catch (e) {
      throw _mapError(e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// GET /api/books/options — 전자책/오디오북 플랫폼 선택 목록.
  Future<Map<String, List<String>>> getPlatformOptions() async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        '/api/books/options',
      );
      final data = _unwrapMap(response);
      final platforms = data['platforms'] as Map<String, dynamic>? ?? const {};
      return platforms.map(
        (key, value) => MapEntry(key, (value as List<dynamic>).cast<String>()),
      );
    } on DioException catch (e) {
      throw _mapError(e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// GET /api/me/tags — 태그 자동완성 제안 목록.
  Future<List<BookTag>> getMyTags({String? status}) async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        '/api/me/tags',
        queryParameters: {'status': ?status},
      );
      final body = response.data;
      if (body == null || body['data'] is! List) {
        throw const ApiException('서버 응답을 처리할 수 없습니다.');
      }
      return (body['data'] as List<dynamic>)
          .map((e) => BookTag.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw _mapError(e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// POST /api/me/books/:userBookId/tags — 태그 추가. 이미 추가된 태그면 409.
  Future<BookTag> postTag({
    required int userBookId,
    required String name,
  }) async {
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/me/books/$userBookId/tags',
        data: {'name': name},
      );
      return BookTag.fromJson(_unwrapMap(response));
    } on DioException catch (e) {
      throw _mapError(
        e,
        overrides: const {409: '이미 추가된 태그입니다.', 400: '태그명을 확인해주세요.'},
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// DELETE /api/me/books/:userBookId/tags/:tagId — 태그 제거.
  Future<void> deleteTag({required int userBookId, required int tagId}) async {
    try {
      await _apiClient.dio.delete<Map<String, dynamic>>(
        '/api/me/books/$userBookId/tags/$tagId',
      );
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// DELETE /api/me/books/:userBookId — 서재에서 책 제거(soft delete).
  Future<void> deleteUserBook(int userBookId) async {
    try {
      await _apiClient.dio.delete<Map<String, dynamic>>(
        '/api/me/books/$userBookId',
      );
    } on DioException catch (e) {
      throw _mapError(e);
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
          404 => '존재하지 않거나 접근할 수 없는 책입니다.',
          _ => '요청 처리 중 오류가 발생했습니다.',
        };
    return ApiException(message, statusCode: statusCode, cause: e);
  }
}
