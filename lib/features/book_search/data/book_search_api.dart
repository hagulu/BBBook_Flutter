import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../models/book_search_item.dart';

/// 책 검색 및 직접 등록 API 호출.
///
/// 문서: ../../../../../api-doc/api-books.md, api-me-books-custom-post.md
///
/// 인증 필요 요청이므로 401 시 1회 재시도 후 실패하면 로그아웃 처리하는
/// [ApiClient]를 통해서만 호출한다(CLAUDE.md 인증 API 호출 규칙).
class BookSearchApi {
  BookSearchApi({required this._apiClient});

  final ApiClient _apiClient;

  /// GET /api/books — 키워드로 책 목록 검색(알라딘 Open API 기반).
  Future<BookSearchPage> searchBooks({
    required String query,
    required int page,
    int size = 10,
  }) async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        '/api/books',
        queryParameters: {'query': query, 'page': page, 'size': size},
      );
      return BookSearchPage.fromJson(_unwrapMap(response));
    } on DioException catch (e) {
      throw _mapError(e, overrides: const {400: '검색어를 입력해주세요.'});
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// POST /api/me/books/custom — ISBN 없이 직접 입력한 정보로 서재에 추가.
  /// 책 기록 상세의 "책 정보 수정" 팝업과 동일한 항목(제목/저자/출판사/
  /// 총쪽수/표지/카테고리)에 상태·완독 옵션을 더해 받는다. [thumbnailFile]이
  /// 있으면 multipart(방식 B)로, 없으면 JSON(방식 A)으로 보낸다 — 새로
  /// 등록하는 책이라 기존 표지를 지우는 개념(removeThumbnail)은 없다.
  Future<int> postCustomBook({
    required String title,
    String? author,
    String? publisher,
    int? totalPages,
    int? categoryId,
    File? thumbnailFile,
    required String status,
    String? sourceType,
    double? myRating,
    String? shortReview,
    String? difficulty,
    String? finishedAt,
  }) async {
    final dataMap = {
      'title': title,
      'author': ?author,
      'publisher': ?publisher,
      'totalPages': ?totalPages,
      'categoryId': ?categoryId,
      'status': status,
      'sourceType': ?sourceType,
      'myRating': ?myRating,
      'shortReview': ?shortReview,
      'difficulty': ?difficulty,
      'finishedAt': ?finishedAt,
    };

    try {
      final Response<Map<String, dynamic>> response;
      if (thumbnailFile != null) {
        final formData = FormData.fromMap({
          'data': MultipartFile.fromString(
            jsonEncode(dataMap),
            contentType: MediaType('application', 'json'),
          ),
          'thumbnail': await MultipartFile.fromFile(thumbnailFile.path),
        });
        response = await _apiClient.dio.post<Map<String, dynamic>>(
          '/api/me/books/custom',
          data: formData,
          options: Options(headers: const {'X-Timezone': 'Asia/Seoul'}),
        );
      } else {
        response = await _apiClient.dio.post<Map<String, dynamic>>(
          '/api/me/books/custom',
          data: dataMap,
          options: Options(headers: const {'X-Timezone': 'Asia/Seoul'}),
        );
      }
      final data = _unwrapMap(response);
      return data['userBookId'] as int;
    } on DioException catch (e) {
      throw _mapError(e, overrides: const {400: '입력값을 확인해주세요.'});
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
          401 => '인증에 실패했습니다.',
          404 => '해당 책을 찾을 수 없습니다.',
          502 => '도서 검색 서비스에 일시적인 문제가 발생했습니다.',
          _ => '요청 처리 중 오류가 발생했습니다.',
        };
    return ApiException(message, statusCode: statusCode, cause: e);
  }
}
