import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../models/public_reflection.dart';
import 'public_reflection_source.dart';

/// 공개 독후감 목록과 상세 조회 API.
///
/// 문서: ../../../../../api-doc/api-books-isbn13-reflections-get.md,
/// api-reflections-reflectionId-get.md
///
/// 로그인 상태에서는 공감 여부 등 사용자 기준 응답을 받을 수 있으므로, 401 시
/// refresh 1회 재시도를 보장하는 [ApiClient]를 사용한다.
class PublicReflectionApi implements PublicReflectionSource {
  PublicReflectionApi({required this.apiClient});

  final ApiClient apiClient;

  @override
  Future<PublicReflectionsPage> fetchPage({
    required String isbn13,
    int? cursor,
    required int size,
  }) async {
    try {
      final response = await apiClient.dio.get<Map<String, dynamic>>(
        '/api/books/$isbn13/reflections',
        queryParameters: {'cursor': ?cursor, 'size': size},
      );
      return PublicReflectionsPage.fromJson(_unwrapMap(response));
    } on DioException catch (error) {
      throw _mapError(error);
    } on ApiException {
      rethrow;
    } catch (error) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: error);
    }
  }

  @override
  Future<PublicReflectionDetail> fetchDetail(int reflectionId) async {
    try {
      final response = await apiClient.dio.get<Map<String, dynamic>>(
        '/api/reflections/$reflectionId',
      );
      return PublicReflectionDetail.fromJson(_unwrapMap(response));
    } on DioException catch (error) {
      throw _mapError(
        error,
        overrides: const {403: '숨김 처리된 독후감입니다.', 404: '독후감을 찾을 수 없습니다.'},
      );
    } on ApiException {
      rethrow;
    } catch (error) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: error);
    }
  }

  /// POST /api/likes/REFLECTION/{reflectionId} — 공개 독후감 공감 추가.
  @override
  Future<int> postLike(int reflectionId) async {
    try {
      final response = await apiClient.dio.post<Map<String, dynamic>>(
        '/api/likes/REFLECTION/$reflectionId',
      );
      return _unwrapMap(response)['likeCount'] as int;
    } on DioException catch (error) {
      throw _mapError(
        error,
        overrides: const {404: '독후감을 찾을 수 없습니다.', 409: '이미 공감한 독후감입니다.'},
      );
    } on ApiException {
      rethrow;
    } catch (error) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: error);
    }
  }

  /// DELETE /api/likes/REFLECTION/{reflectionId} — 공개 독후감 공감 취소.
  @override
  Future<int> deleteLike(int reflectionId) async {
    try {
      final response = await apiClient.dio.delete<Map<String, dynamic>>(
        '/api/likes/REFLECTION/$reflectionId',
      );
      return _unwrapMap(response)['likeCount'] as int;
    } on DioException catch (error) {
      throw _mapError(error, overrides: const {404: '취소할 공감을 찾을 수 없습니다.'});
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

  ApiException _mapError(DioException error, {Map<int, String>? overrides}) {
    final statusCode = error.response?.statusCode;
    final message =
        overrides?[statusCode] ??
        switch (statusCode) {
          400 => 'ISBN 또는 요청값을 확인해주세요.',
          401 => '인증에 실패했습니다.',
          403 => '접근할 수 없는 독후감입니다.',
          404 => '독후감을 찾을 수 없습니다.',
          _ => '독후감을 불러오지 못했습니다.',
        };
    return ApiException(message, statusCode: statusCode, cause: error);
  }
}
