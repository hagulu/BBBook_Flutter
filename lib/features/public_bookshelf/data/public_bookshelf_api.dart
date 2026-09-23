import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../models/public_finished_book.dart';

/// 다른 사용자의 공개 완독 책장 API 호출.
///
/// 문서: ../../../../../api-doc/api-users-id-books-finished-get.md
///
/// 비로그인 사용자도 조회 가능한 인증 선택 요청이라 [ApiClient]가 토큰이
/// 있으면 함께 싣고, 없어도 그대로 보낸다(CLAUDE.md 인증 API 호출 규칙).
class PublicBookshelfApi {
  PublicBookshelfApi({required this._apiClient});

  final ApiClient _apiClient;

  /// GET /api/users/{userId}/books/finished
  Future<PublicFinishedBooksPage> fetchFinishedBooks({
    required int userId,
    int? cursor,
    DateTime? cursorDate,
    required int size,
  }) async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        '/api/users/$userId/books/finished',
        queryParameters: {
          'cursor': ?cursor,
          'cursorDate': ?cursorDate?.toIso8601String().substring(0, 10),
          'size': size,
        },
      );
      return PublicFinishedBooksPage.fromJson(_unwrapMap(response));
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
      403 => '비공개로 설정된 완독 책장입니다.',
      _ => '요청 처리 중 오류가 발생했습니다.',
    };
    return ApiException(message, statusCode: statusCode, cause: e);
  }
}
