import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../models/app_version_policy.dart';

/// 앱 버전 정책 API.
///
/// 문서: ../../../../../api-doc/api-app-versions-get.md
///
/// 인증이 필요 없는 공개 API라 401 refresh 인터셉터가 없는 순수 [Dio]를 쓴다.
class AppVersionApi {
  AppVersionApi({required this.dio});

  final Dio dio;

  /// GET /api/app-versions — 등록된 플랫폼별 정책 전체. 미등록 플랫폼은 빠진다.
  Future<List<AppVersionPolicy>> fetchPolicies() async {
    try {
      final response = await dio.get<Map<String, dynamic>>('/api/app-versions');
      final data = response.data?['data'];
      if (data is! Map<String, dynamic> || data['items'] is! List) {
        throw const ApiException('서버 응답을 처리할 수 없습니다.');
      }
      return (data['items'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(AppVersionPolicy.fromJson)
          .toList();
    } on DioException catch (error) {
      throw ApiException(
        '앱 버전 정보를 불러오지 못했습니다.',
        statusCode: error.response?.statusCode,
        cause: error,
      );
    } on ApiException {
      rethrow;
    } catch (error) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: error);
    }
  }
}
