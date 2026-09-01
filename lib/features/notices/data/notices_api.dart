import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../models/notice_detail.dart';
import '../models/notice_summary.dart';

/// 공지사항 목록·상세 API(`notices-screens.md` §3).
///
/// 문서: ../../../../../api-doc/api-notices-get.md,
/// api-notices-id-get.md
///
/// 두 요청 모두 인증이 필요 없는 공개 API다(`notices-screens.md` §1-2, §2-3).
class NoticesApi {
  NoticesApi({required this.apiClient});

  final ApiClient apiClient;

  /// GET /api/notices
  Future<NoticeSummaryPage> fetchNotices({
    int? cursor,
    required int size,
  }) async {
    try {
      final response = await apiClient.dio.get<Map<String, dynamic>>(
        '/api/notices',
        queryParameters: {'cursor': ?cursor, 'size': size},
      );
      return NoticeSummaryPage.fromJson(_unwrapMap(response));
    } on DioException catch (error) {
      throw _mapError(error);
    } on ApiException {
      rethrow;
    } catch (error) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: error);
    }
  }

  /// GET /api/notices/{id}
  Future<NoticeDetail> fetchNotice(int id) async {
    try {
      final response = await apiClient.dio.get<Map<String, dynamic>>(
        '/api/notices/$id',
      );
      return NoticeDetail.fromJson(_unwrapMap(response));
    } on DioException catch (error) {
      throw _mapError(error);
    } on ApiException {
      rethrow;
    } catch (error) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: error);
    }
  }

  Map<String, dynamic> _unwrapMap(Response<Map<String, dynamic>> response) {
    final body = response.data;
    if (body == null || body['data'] is! Map<String, dynamic>) {
      throw const ApiException('서버 응답을 처리할 수 없습니다.');
    }
    return body['data'] as Map<String, dynamic>;
  }

  ApiException _mapError(DioException error) {
    final statusCode = error.response?.statusCode;
    return ApiException(
      '공지사항을 불러오지 못했습니다.',
      statusCode: statusCode,
      cause: error,
    );
  }
}
