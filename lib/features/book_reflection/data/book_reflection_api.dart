import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../models/book_reflection.dart';
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

  /// POST /api/me/books/{userBookId}/reflections — 독후감 생성.
  Future<BookReflectionServerResult> create({
    required int userBookId,
    required BookReflectionDraft draft,
    required String? clientRequestId,
  }) async {
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/me/books/$userBookId/reflections',
        data: {
          'title': draft.title,
          'contentJson': draft.contentJson,
          'contentText': draft.contentText,
          'isPublic': draft.isPublic,
          'clientRequestId': clientRequestId,
        },
      );
      return BookReflectionServerResult.fromJson(_unwrapMap(response));
    } on DioException catch (e) {
      throw _mapError(e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// PATCH /api/reflections/{reflectionId} — 독후감 수정.
  Future<BookReflectionServerResult> update({
    required int reflectionId,
    required BookReflectionDraft draft,
  }) async {
    try {
      final response = await _apiClient.dio.patch<Map<String, dynamic>>(
        '/api/reflections/$reflectionId',
        data: {
          'title': draft.title,
          'contentJson': draft.contentJson,
          'contentText': draft.contentText,
          'isPublic': draft.isPublic,
        },
      );
      return BookReflectionServerResult.fromJson(_unwrapMap(response));
    } on DioException catch (e) {
      throw _mapError(e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// PATCH /api/reflections/{reflectionId} — 공개 여부만 수정.
  Future<void> updateVisibility({
    required int reflectionId,
    required bool isPublic,
  }) async {
    try {
      await _apiClient.dio.patch<Map<String, dynamic>>(
        '/api/reflections/$reflectionId',
        data: {'isPublic': isPublic},
      );
    } on DioException catch (e) {
      throw _mapError(e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// DELETE /api/reflections/{reflectionId} — 독후감 삭제.
  Future<void> delete(int reflectionId) async {
    try {
      await _apiClient.dio.delete<void>('/api/reflections/$reflectionId');
    } on DioException catch (e) {
      throw _mapError(e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// POST /api/reflections/images/temp — 본문 이미지 임시 업로드.
  Future<String> uploadTempImage(File file) async {
    try {
      final form = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          file.path,
          filename: path.basename(file.path),
        ),
      });
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/reflections/images/temp',
        data: form,
      );
      final data = _unwrapMap(response);
      final url = data['url'];
      if (url is! String || url.isEmpty) {
        throw const ApiException('서버 응답을 처리할 수 없습니다.');
      }
      return url;
    } on DioException catch (e) {
      throw _mapError(e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

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
      400 => '입력한 내용을 확인해 주세요.',
      404 => '독후감을 찾을 수 없습니다.',
      _ => '요청 처리 중 오류가 발생했습니다.',
    };
    return ApiException(message, statusCode: statusCode, cause: e);
  }
}
