import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../models/tag_sync_changes_result.dart';

/// 태그 추가/삭제 및 증분 동기화 API 호출.
///
/// 문서: ../../../../../api-doc/api-me-books-userBookId-tags-post.md,
/// api-me-books-userBookId-tags-tagId-delete.md,
/// api-me-tags-sync-changes-get.md
///
/// 인증 필요 요청이므로 401 시 1회 재시도 후 실패하면 로그아웃 처리하는
/// [ApiClient]를 통해서만 호출한다(CLAUDE.md 인증 API 호출 규칙).
class TagApi {
  TagApi({required this._apiClient});

  final ApiClient _apiClient;

  /// POST /api/me/books/{userBookId}/tags — 태그 추가(없으면 생성/복원,
  /// 있으면 재사용). 응답은 태그 정보(id/name)만 담고 매핑 자체의 ID는
  /// 내려주지 않는다 — 매핑 ID는 이후 증분/전체 동기화가 채운다
  /// ([TagDao]의 매핑 upsert 참고).
  ///
  /// 이미 활성 상태로 추가된 태그면 409를 던진다 — 호출부([TagRepository])는
  /// 이를 "서버에는 이미 있음"으로 보고 dirty를 유지한 채 곧 이어질 증분
  /// 동기화로 정리한다.
  Future<({int id, String name})> postTag({
    required int userBookId,
    required String name,
  }) async {
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/me/books/$userBookId/tags',
        data: {'name': name},
      );
      final data = _unwrapMap(response);
      return (id: data['id'] as int, name: data['name'] as String);
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

  /// DELETE /api/me/books/{userBookId}/tags/{tagId} — 태그 제거(매핑 soft
  /// delete). 이미 제거된 매핑을 다시 지우면 404를 반환하는데, 이는 "지우려는
  /// 목표는 이미 달성됨"과 같으므로 성공으로 취급한다(`BookNoteApi.deleteNote`와
  /// 같은 이유).
  Future<void> deleteTag({required int userBookId, required int tagId}) async {
    try {
      await _apiClient.dio.delete<Map<String, dynamic>>(
        '/api/me/books/$userBookId/tags/$tagId',
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return;
      throw _mapError(e);
    }
  }

  /// GET /api/me/tags/sync/changes — since 이후 변경분만 조회하는 증분 동기화.
  Future<TagSyncChangesResult> getSyncChanges({required DateTime since}) async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        '/api/me/tags/sync/changes',
        queryParameters: {'since': since.toUtc().toIso8601String()},
      );
      final data = _unwrapMap(response);
      return TagSyncChangesResult.fromJson(data);
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

  ApiException _mapError(DioException e, {Map<int, String>? overrides}) {
    final statusCode = e.response?.statusCode;
    final message =
        overrides?[statusCode] ??
        switch (statusCode) {
          401 => '인증에 실패했습니다.',
          404 => '존재하지 않거나 접근할 수 없는 책입니다.',
          _ => '요청 처리 중 오류가 발생했습니다.',
        };
    return ApiException(message, statusCode: statusCode, cause: e);
  }
}
