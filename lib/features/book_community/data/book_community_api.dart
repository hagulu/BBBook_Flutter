import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../models/book_community.dart';

/// 책 검색 상세·책 기록 상세(생각나눔 탭)가 공유하는 커뮤니티 미리보기·개수
/// API 호출.
///
/// 문서: ../../../../../api-doc/api-books-isbn13-community-preview-get.md,
/// api-books-isbn13-community-counts-get.md
///
/// 두 요청 모두 비로그인 사용자도 조회 가능하지만, 로그인 상태라면 다른
/// 인증 API와 동일하게 401 시 refresh 1회 재시도를 보장하는 [ApiClient]를
/// 사용한다.
class BookCommunityApi {
  BookCommunityApi({required this.apiClient});

  final ApiClient apiClient;

  /// GET /api/books/{isbn13}/community-preview
  Future<BookCommunityPreview> getPreview(String isbn13) async {
    try {
      final response = await apiClient.dio.get<Map<String, dynamic>>(
        '/api/books/$isbn13/community-preview',
      );
      return BookCommunityPreview.fromJson(_unwrapMap(response));
    } on DioException catch (e) {
      throw _mapError(e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// GET /api/books/{isbn13}/community-counts
  Future<BookCommunityCounts> getCounts(String isbn13) async {
    try {
      final response = await apiClient.dio.get<Map<String, dynamic>>(
        '/api/books/$isbn13/community-counts',
      );
      return BookCommunityCounts.fromJson(_unwrapMap(response));
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
      404 => '해당 책을 찾을 수 없습니다.',
      _ => '커뮤니티 정보를 불러오지 못했습니다.',
    };
    return ApiException(message, statusCode: statusCode, cause: e);
  }
}
