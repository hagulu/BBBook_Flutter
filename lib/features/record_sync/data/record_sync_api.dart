import 'dart:developer' as developer;

import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../models/record_sync_payload.dart';

/// 최초 기록 전체 조회 API.
///
/// 문서: ../../../../../api-doc/api-me-records-get.md
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
}
