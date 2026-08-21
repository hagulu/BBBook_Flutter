import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../models/book_reflection_sync_changes_result.dart';

/// 독후감 증분 동기화 API 호출.
///
/// 문서: ../../../../../api-doc/api-me-reflections-sync-changes-get.md
///
/// 전체 동기화는 별도 API가 없다 — `record_sync` 기능의
/// `GET /api/me/records`(전체 책장/메모/독후감 통합 조회)를 그대로
/// 재사용한다([BookNoteApi]와 같은 구조).
///
/// 인증 필요 요청이므로 401 시 1회 재시도 후 실패하면 로그아웃 처리하는
/// [ApiClient]를 통해서만 호출한다(CLAUDE.md 인증 API 호출 규칙).
class BookReflectionApi {
  BookReflectionApi({required this._apiClient});

  final ApiClient _apiClient;

  /// GET /api/me/reflections/sync/changes — since 이후 변경분만 조회하는
  /// 증분 동기화.
  Future<BookReflectionSyncChangesResult> getSyncChanges({
    required DateTime since,
  }) async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        '/api/me/reflections/sync/changes',
        queryParameters: {'since': since.toUtc().toIso8601String()},
      );
      final data = _unwrapMap(response);
      return BookReflectionSyncChangesResult.fromJson(data);
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
