import 'dart:developer' as developer;

import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../models/record_sync_payload.dart';

/// 기록 전체 조회·일괄 삭제 API.
///
/// 문서: ../../../../../api-doc/api-me-records-get.md,
/// api-me-records-delete.md
class RecordSyncApi {
  const RecordSyncApi(this._apiClient);

  final ApiClient _apiClient;

  Future<RecordSyncPayload> getAllRecords() async {
    const api = '/api/me/records';
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(api);
      final body = response.data;
      if (body == null ||
          body['success'] != true ||
          body['data'] is! Map<String, dynamic>) {
        throw const ApiException('서버 응답을 처리할 수 없습니다.');
      }
      final payload = RecordSyncPayload.fromJson(
        body['data'] as Map<String, dynamic>,
      );
      developer.log('[초기 기록 조회] api=$api result=SUCCESS');
      return payload;
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      developer.log(
        '[초기 기록 조회] api=$api result=FAIL '
        'reason=status_${statusCode ?? "unknown"}',
      );
      throw ApiException(
        statusCode == 401 ? '인증에 실패했습니다.' : '기록을 불러오지 못했습니다.',
        statusCode: statusCode,
        cause: e,
      );
    } on ApiException {
      developer.log('[초기 기록 조회] api=$api result=FAIL reason=invalid_response');
      rethrow;
    } catch (e) {
      developer.log('[초기 기록 조회] api=$api result=FAIL reason=invalid_response');
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// DELETE /api/me/records — 책장·노트·메모·독후감을 일괄 소프트 삭제한다.
  ///
  /// 로컬 저장 모드 전환의 마지막 단계 전용이다. 멱등이라(이미 삭제된 항목은
  /// 건너뛴다) 실패 후 다시 호출해도 안전하다.
  ///
  /// [exportedAt]은 로컬에 반영한 [getAllRecords] 응답의 값이다. 그 시각
  /// 이후 다른 기기·웹에서 추가·수정된 기록이 있으면 서버가 아무것도 지우지
  /// 않고 409([recordsChangedSinceExport])로 거절한다. null이면 그 확인 없이
  /// 전체를 지운다 — 최신 기록을 받지 못한 채 사용자가 전환을 승인했거나,
  /// 그 기록까지 지우기로 사용자가 직접 확인한 경우에만 쓴다.
  Future<void> deleteAllRecords({String? exportedAt}) async {
    const api = '/api/me/records';
    try {
      await _apiClient.dio.delete<Map<String, dynamic>>(
        api,
        queryParameters: {'exportedAt': ?exportedAt},
      );
      developer.log(
        '[서버 기록 일괄 삭제] api=$api guarded=${exportedAt != null} '
        'result=SUCCESS',
      );
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final body = e.response?.data;
      final errorCode = body is Map ? body['errorCode'] as String? : null;
      final changedSinceExport =
          statusCode == 409 && errorCode == recordsChangedSinceExport;
      final reason = changedSinceExport
          ? 'records_changed_since_export'
          : 'status_${statusCode ?? "unknown"}';
      developer.log(
        '[서버 기록 일괄 삭제] api=$api guarded=${exportedAt != null} '
        'result=FAIL reason=$reason',
      );
      throw ApiException(
        switch (statusCode) {
          401 => '인증에 실패했습니다.',
          _ when changedSinceExport =>
            '다른 기기나 웹에서 바뀐 기록이 있어 서버 기록을 정리하지 않았습니다.',
          _ => '서버 기록을 정리하지 못했습니다.',
        },
        statusCode: statusCode,
        errorCode: errorCode,
        cause: e,
      );
    }
  }

  /// [deleteAllRecords]가 exportedAt 이후 바뀐 기록 때문에 거절됐을 때의
  /// errorCode. 이 경우 서버에서는 아무것도 삭제되지 않았다.
  static const recordsChangedSinceExport = 'RECORDS_CHANGED_SINCE_EXPORT';

  static bool isRecordsChangedSinceExport(Object error) =>
      error is ApiException && error.errorCode == recordsChangedSinceExport;
}
