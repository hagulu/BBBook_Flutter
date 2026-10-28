import 'dart:developer' as developer;
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

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
      developer.log(
        '[Import 시작] api=$api importId=${session.importId} '
        'importedCount=${session.importedCount} result=SUCCESS',
      );
      return session;
    } on DioException catch (e) {
      final error = _mapError(e);
      _logRequestFailure(operation: 'Import 시작', api: api, error: error);
      throw error;
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
      developer.log(
        '[Import 청크 업로드] api=$api importId=$importId '
        '${_payloadCountLog(payload)} result=SUCCESS',
      );
      return RecordImportChunkResult.fromJson(_unwrapMap(response));
    } on DioException catch (e) {
      final error = _mapError(e);
      _logRequestFailure(
        operation: 'Import 청크 업로드',
        api: api,
        importId: importId,
        error: error,
        context: _payloadCountLog(payload),
      );
      throw error;
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
        '[Import 이미지 업로드] api=$api importId=$importId '
        'entityType=${entityType.apiValue} result=SUCCESS',
      );
      return RecordImportAttachmentResult.fromJson(_unwrapMap(response));
    } on DioException catch (e) {
      final error = _mapError(e);
      _logRequestFailure(
        operation: 'Import 이미지 업로드',
        api: api,
        importId: importId,
        error: error,
        context: 'entityType=${entityType.apiValue}',
      );
      throw error;
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
      developer.log(
        '[Import 완료] api=$api importId=$importId '
        '${_countLog(counts)} result=SUCCESS',
      );
    } on DioException catch (e) {
      final error = _mapError(e);
      _logRequestFailure(
        operation: 'Import 완료',
        api: api,
        importId: importId,
        error: error,
        context: _countLog(counts),
      );
      throw error;
    }
  }

  /// [complete]의 응답을 받지 못했을 때 같은 세션의 확정 여부를 다시 확인한다.
  ///
  /// 응답이 유실돼도 서버는 이미 COMPLETED일 수 있다. 그 상태를 실패로 끝내면
  /// 다음 재시도는 `/start`부터 새 세션을 열고, 이미 활성인 기존 행을 재사용하는
  /// 그 세션은 사진 재첨부가 400으로 반복 실패하거나 확정 반영이 그 사이의 로컬
  /// 편집을 덮을 수 있다. 그래서 매핑을 아직 들고 있는 이 실행 안에서만 같은
  /// importId로 다시 확인한다(앱이 종료된 뒤의 복구는 하지 않는다).
  ///
  /// - 재요청이 성공하면 첫 요청은 서버에 닿지 않았던 것이다.
  /// - 재요청의 409는 "이미 COMPLETED"와 "이번 재요청의 검증 실패로 롤백"을
  ///   구분하지 못한다. 취소 API는 COMPLETED 세션에만 409를 돌려주므로 그
  ///   응답으로 확정 여부를 판정한다(롤백된 세션은 404).
  /// - 그 밖의 응답이나 재시도 소진은 원래처럼 실패로 던진다.
  Future<void> completeConfirmingDelivery(
    int importId,
    RecordImportCounts counts,
  ) async {
    try {
      await complete(importId, counts);
      return;
    } on RecordImportException catch (error) {
      if (error.kind != RecordImportFailureKind.network) rethrow;
    }
    for (var attempt = 1; ; attempt++) {
      // 연결 오류 직후에는 ApiClient가 잠시 새 요청을 통신 없이 거절한다.
      await _waitForRetryWindow();
      try {
        await complete(importId, counts);
        return;
      } on RecordImportException catch (error) {
        if (error.kind == RecordImportFailureKind.sessionCompleted) {
          if (await _isSessionCompleted(importId)) {
            developer.log(
              '[Import 완료] importId=$importId result=SUCCESS '
              'reason=confirmed_after_lost_response',
            );
            return;
          }
          rethrow;
        }
        if (error.kind != RecordImportFailureKind.network ||
            attempt >= _maxCompleteConfirmAttempts) {
          rethrow;
        }
      }
    }
  }

  static const _maxCompleteConfirmAttempts = 2;

  Future<void> _waitForRetryWindow() async {
    final retryAfter = _apiClient.retryAfter;
    final wait = retryAfter == null
        ? const Duration(seconds: 1)
        : retryAfter.difference(DateTime.now()) +
              const Duration(milliseconds: 500);
    if (wait > Duration.zero) await Future<void>.delayed(wait);
  }

  /// 응답 유실 뒤 재요청이 409를 받았을 때만 쓰는 확정 여부 확인. 그 시점의
  /// 세션은 COMPLETED이거나 이미 롤백돼 사라진 상태라 취소 요청이 기록을
  /// 건드리지 않는다(정리 실패로 EXPIRED가 남았다면 이 요청이 정리를 마친다).
  Future<bool> _isSessionCompleted(int importId) async {
    final api = '/api/me/records/import/$importId/cancel';
    try {
      await _apiClient.dio.post<Map<String, dynamic>>(api);
      return false;
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      if (statusCode == 409) return true;
      if (statusCode == 404) return false;
      final error = _mapError(e);
      _logRequestFailure(
        operation: 'Import 완료 확인',
        api: api,
        importId: importId,
        error: error,
      );
      throw error;
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
      developer.log('[Import 취소] api=$api importId=$importId result=SUCCESS');
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      if (statusCode == 404 || statusCode == 409) return;
      final error = _mapError(e);
      _logRequestFailure(
        operation: 'Import 취소',
        api: api,
        importId: importId,
        error: error,
      );
      throw error;
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
    final responseBody = e.response?.data;
    final rawServerMessage = responseBody is Map
        ? responseBody['message']
        : null;
    final serverMessage =
        rawServerMessage is String && rawServerMessage.trim().isNotEmpty
        ? rawServerMessage.trim()
        : null;
    final message = statusCode == 401
        ? '인증에 실패했습니다.'
        : serverMessage ?? '가져오기 요청 처리 중 오류가 발생했습니다.';
    return RecordImportException(
      message,
      kind: kind,
      statusCode: statusCode,
      serverMessage: serverMessage,
      cause: e,
    );
  }

  void _logRequestFailure({
    required String operation,
    required String api,
    required RecordImportException error,
    int? importId,
    String? context,
  }) {
    final cause = error.cause;
    final causeType = cause is DioException ? cause.type.name : 'unknown';
    final diagnosticMessage = (error.serverMessage ?? error.message)
        .replaceAll(RegExp(r'[\r\n]+'), ' ')
        .trim();
    final limitedMessage = diagnosticMessage.length <= 300
        ? diagnosticMessage
        : '${diagnosticMessage.substring(0, 300)}…';
    developer.log(
      '[$operation] api=$api '
      '${importId == null ? '' : 'importId=$importId '}'
      '${context == null ? '' : '$context '}'
      'status=${error.statusCode} dioType=$causeType result=FAIL '
      'reason=${error.kind.name}'
      '${kDebugMode ? ' serverMessage="$limitedMessage"' : ''}',
      error: kDebugMode ? cause : null,
      stackTrace: kDebugMode && cause is DioException ? cause.stackTrace : null,
    );
  }

  String _payloadCountLog(Map<String, dynamic> payload) {
    int lengthOf(String key) => switch (payload[key]) {
      final List<dynamic> values => values.length,
      _ => -1,
    };
    return 'bookCount=${lengthOf('books')} '
        'noteCount=${lengthOf('notes')} '
        'noteMemoCount=${lengthOf('noteMemos')} '
        'reflectionCount=${lengthOf('reflections')} '
        'tagCount=${lengthOf('tags')} '
        'tagMapCount=${lengthOf('tagMaps')}';
  }

  String _countLog(RecordImportCounts counts) {
    return 'bookCount=${counts.bookCount} '
        'noteCount=${counts.noteCount} '
        'noteMemoCount=${counts.noteMemoCount} '
        'reflectionCount=${counts.reflectionCount} '
        'tagCount=${counts.tagCount} '
        'tagMapCount=${counts.tagMapCount}';
  }
}
