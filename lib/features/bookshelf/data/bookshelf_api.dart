import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../models/book_category.dart';
import '../models/book_item.dart';
import '../models/sync_changes_result.dart';

/// 책장 관련 API 호출.
///
/// 문서: ../../../../../api-doc/api-me-books-sync-get.md,
/// api-me-books-sync-changes-get.md, api-me-privacy-setting-get.md,
/// api-me-privacy-setting-patch.md, api-books-categories-get.md
///
/// 인증 필요 요청이므로 401 시 1회 재시도 후 실패하면 로그아웃 처리하는
/// [ApiClient]를 통해서만 호출한다(CLAUDE.md 인증 API 호출 규칙). 단
/// [getCategories]는 문서상 인증이 필요 없는 API다.
class BookshelfApi {
  BookshelfApi({required this._apiClient});

  final ApiClient _apiClient;

  /// GET /api/me/books/sync — 서재 전체 목록(페이지네이션 없음). 최초 동기화 전용.
  Future<List<BookItem>> getSync() async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        '/api/me/books/sync',
      );
      final data = _unwrapList(response);
      return data
          .map((e) => BookItem.fromSyncJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw _mapError(e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// GET /api/me/books/sync/changes — since 이후 변경분만 조회하는 증분 동기화.
  Future<SyncChangesResult> getSyncChanges({required DateTime since}) async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        '/api/me/books/sync/changes',
        queryParameters: {'since': since.toUtc().toIso8601String()},
      );
      final data = _unwrapMap(response);
      return SyncChangesResult.fromJson(data);
    } on DioException catch (e) {
      throw _mapError(e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// GET /api/me/privacy-setting
  Future<bool> getPrivacySetting() async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        '/api/me/privacy-setting',
      );
      final data = _unwrapMap(response);
      return data['isFinishedBooksPublic'] as bool;
    } on DioException catch (e) {
      throw _mapError(e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// PATCH /api/me/privacy-setting
  Future<bool> patchPrivacySetting({
    required bool isFinishedBooksPublic,
  }) async {
    try {
      final response = await _apiClient.dio.patch<Map<String, dynamic>>(
        '/api/me/privacy-setting',
        data: {'isFinishedBooksPublic': isFinishedBooksPublic},
      );
      final data = _unwrapMap(response);
      return data['isFinishedBooksPublic'] as bool;
    } on DioException catch (e) {
      throw _mapError(e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// GET /api/books/categories — 활성 카테고리 목록(sort_order 오름차순). 인증 불필요.
  Future<List<BookCategory>> getCategories() async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        '/api/books/categories',
      );
      final data = _unwrapList(response);
      return data
          .map((e) => BookCategory.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw _mapError(e);
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
