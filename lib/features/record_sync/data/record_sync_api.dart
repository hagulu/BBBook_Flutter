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
  Future<void> deleteAllRecords() async {
    const api = '/api/me/records';
    try {
      await _apiClient.dio.delete<Map<String, dynamic>>(api);
      developer.log('[서버 기록 일괄 삭제] api=$api result=SUCCESS');
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      developer.log(
        '[서버 기록 일괄 삭제] api=$api result=FAIL '
        'reason=status_${statusCode ?? "unknown"}',
      );
      throw ApiException(
        statusCode == 401 ? '인증에 실패했습니다.' : '서버 기록을 정리하지 못했습니다.',
        statusCode: statusCode,
        cause: e,
      );
    }
  }
}
