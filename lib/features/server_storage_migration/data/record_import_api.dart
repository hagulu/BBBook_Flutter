import 'dart:developer' as developer;
import 'dart:io';

import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../models/record_import_models.dart';

/// 로컬 → 서버 저장 모드 재전환 Import 세션 API 호출.
///
/// 문서: ../../../../../api-doc/api-me-records-import-start-post.md,
/// api-me-records-import-importId-items-post.md,
/// api-me-records-import-importId-attachments-post.md,
/// api-me-records-import-importId-complete-post.md,
/// api-me-records-import-importId-cancel-post.md
///
/// 인증 필요 요청이므로 401 시 1회 재시도 후 실패하면 로그아웃 처리하는
/// [ApiClient]를 통해서만 호출한다(CLAUDE.md 인증 API 호출 규칙).
class RecordImportApi {
  const RecordImportApi(this._apiClient);

  final ApiClient _apiClient;

  /// POST /api/me/records/import/start
  Future<RecordImportSession> start() async {
    const api = '/api/me/records/import/start';
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(api);
      final session = RecordImportSession.fromJson(_unwrapMap(response));
      developer.log('[Import 시작] importId=${session.importId} result=SUCCESS');
      return session;
    } on DioException catch (e) {
      developer.log('[Import 시작] result=FAIL reason=status_${e.response?.statusCode}');
      throw _mapError(e);
    }
  }

  /// POST /api/me/records/import/{importId}/items
  Future<RecordImportChunkResult> uploadItems(
    int importId,
    Map<String, dynamic> payload,
  ) async {
    final api = '/api/me/records/import/$importId/items';
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        api,
        data: payload,
      );
      developer.log('[Import 청크 업로드] importId=$importId result=SUCCESS');
      return RecordImportChunkResult.fromJson(_unwrapMap(response));
    } on DioException catch (e) {
      developer.log(
        '[Import 청크 업로드] importId=$importId result=FAIL '
        'reason=status_${e.response?.statusCode}',
      );
      throw _mapError(e);
    }
  }

  /// POST /api/me/records/import/{importId}/attachments
  Future<RecordImportAttachmentResult> uploadAttachment({
    required int importId,
    required RecordImportAttachmentEntityType entityType,
    required int localId,
    String? placeholder,
    required File file,
  }) async {
    final api = '/api/me/records/import/$importId/attachments';
    try {
      final fileName = file.path.split(Platform.pathSeparator).last;
      final formData = FormData.fromMap({
        'entityType': entityType.apiValue,
        'localId': localId.toString(),
        'placeholder': ?placeholder,
        'file': await MultipartFile.fromFile(file.path, filename: fileName),
      });
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        api,
        data: formData,
      );
      developer.log(
        '[Import 이미지 업로드] importId=$importId entityType=${entityType.apiValue} '
        'result=SUCCESS',
      );
      return RecordImportAttachmentResult.fromJson(_unwrapMap(response));
    } on DioException catch (e) {
      developer.log(
        '[Import 이미지 업로드] importId=$importId entityType=${entityType.apiValue} '
        'result=FAIL reason=status_${e.response?.statusCode}',
      );
      throw _mapError(e);
    }
  }

  /// POST /api/me/records/import/{importId}/complete
  Future<void> complete(int importId, RecordImportCounts counts) async {
    final api = '/api/me/records/import/$importId/complete';
    try {
      await _apiClient.dio.post<Map<String, dynamic>>(
        api,
        data: counts.toJson(),
      );
      developer.log('[Import 완료] importId=$importId result=SUCCESS');
    } on DioException catch (e) {
      developer.log(
        '[Import 완료] importId=$importId result=FAIL '
        'reason=status_${e.response?.statusCode}',
      );
      throw _mapError(e);
    }
  }

  /// POST /api/me/records/import/{importId}/cancel
  ///
  /// 세션이 아직 살아 있는 동안 클라이언트가 직접 중단할 때만 호출한다.
  /// items/attachments/complete 실패 이후에는 서버가 이미 세션 전체를
  /// 정리했으므로(문서 "실패 시 동작") 호출하지 않는다 —
  /// [ServerStorageMigrationService]는 그런 실패에 이 메서드를 쓰지 않는다.
  /// 이미 정리돼 사라진 세션(404)이나 완료된 세션(409)에 대한 호출은 안전하게
  /// 무시한다.
  Future<void> cancel(int importId) async {
    final api = '/api/me/records/import/$importId/cancel';
    try {
      await _apiClient.dio.post<Map<String, dynamic>>(api);
      developer.log('[Import 취소] importId=$importId result=SUCCESS');
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      if (statusCode == 404 || statusCode == 409) return;
      developer.log('[Import 취소] importId=$importId result=FAIL reason=status_$statusCode');
      throw _mapError(e);
    }
  }

  Map<String, dynamic> _unwrapMap(Response<Map<String, dynamic>> response) {
    final body = response.data;
    if (body == null || body['data'] is! Map<String, dynamic>) {
      throw const RecordImportException(
        '서버 응답을 처리할 수 없습니다.',
        kind: RecordImportFailureKind.unknown,
      );
    }
    return body['data'] as Map<String, dynamic>;
  }

  RecordImportException _mapError(DioException e) {
    final statusCode = e.response?.statusCode;
    final kind = switch (statusCode) {
      404 => RecordImportFailureKind.sessionNotFound,
      409 => RecordImportFailureKind.sessionCompleted,
      410 => RecordImportFailureKind.sessionExpired,
      400 || 500 => RecordImportFailureKind.requestFailed,
      null => RecordImportFailureKind.network,
      _ => RecordImportFailureKind.unknown,
    };
    final message = statusCode == 401 ? '인증에 실패했습니다.' : '가져오기 요청 처리 중 오류가 발생했습니다.';
    return RecordImportException(
      message,
      kind: kind,
      statusCode: statusCode,
      cause: e,
    );
  }
}
