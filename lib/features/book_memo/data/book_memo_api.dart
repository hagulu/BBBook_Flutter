import 'dart:io';

import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../record_sync/models/record_sync_payload.dart';
import '../models/book_memo.dart';
import '../models/book_memo_sync_changes_result.dart';

/// 메모/메모 조각 저장·수정·삭제 및 동기화 API 호출.
///
/// 문서: ../../../../../api-doc/api-me-books-userBookId-memos-title-put.md,
/// api-me-books-userBookId-memos-items-post.md,
/// api-me-books-userBookId-memos-items-itemId-patch.md,
/// api-me-books-userBookId-memos-items-itemId-delete.md,
/// api-memos-memoId-images-post.md, api-me-memos-sync-changes-get.md
///
/// 인증 필요 요청이므로 401 시 1회 재시도 후 실패하면 로그아웃 처리하는
/// [ApiClient]를 통해서만 호출한다(CLAUDE.md 인증 API 호출 규칙).
class BookMemoApi {
  BookMemoApi({required this._apiClient});

  final ApiClient _apiClient;

  /// PUT /api/me/books/{userBookId}/memos/title
  ///
  /// memoId가 null이고 title이 있으면 새 메모를 생성한다. memoId도 title도
  /// 없으면 서버는 아무것도 생성하지 않고 `data.memoId`가 null로 내려온다
  /// (호출부가 이 경우를 걸러야 한다).
  Future<({int? memoId, String? title})> putTitle({
    required int userBookId,
    required int? memoId,
    required String? title,
  }) async {
    try {
      final response = await _apiClient.dio.put<Map<String, dynamic>>(
        '/api/me/books/$userBookId/memos/title',
        data: {'memoId': memoId, 'title': title},
      );
      final data = _unwrapMap(response);
      return (memoId: data['memoId'] as int?, title: data['title'] as String?);
    } on DioException catch (e) {
      throw _mapError(e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// POST /api/me/books/{userBookId}/memos/items
  ///
  /// memoId가 null이면 새 메모를 함께 생성한다. itemType=PHOTO면 imageUrl(R2
  /// 키, [uploadImage] 응답)이 필수이며, memoId=null과 함께 쓸 수 없다(문서
  /// 참고 — 새 메모에서 첫 PHOTO를 만들려면 memoId를 먼저 확보해야 한다).
  Future<ServerBookMemoItem> postItem({
    required int userBookId,
    required int? memoId,
    required BookMemoItemType itemType,
    required int? startPage,
    required int? endPage,
    required String? content,
    required String? imageUrl,
    required bool isImportant,
  }) async {
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/me/books/$userBookId/memos/items',
        data: {
          'memoId': memoId,
          'itemType': itemType.dbValue,
          'startPage': startPage,
          'endPage': endPage,
          'content': content,
          'imageUrl': imageUrl,
          'isImportant': isImportant,
        },
      );
      final data = _unwrapMap(response);
      return ServerBookMemoItem.fromJson(data);
    } on DioException catch (e) {
      throw _mapError(e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// PATCH /api/me/books/{userBookId}/memos/items/{itemId}
  ///
  /// body에 담긴 필드만 변경된다("미전달 시 변경 없음"). [imageUrl]을
  /// 전달하지 않으려면(사진을 바꾸지 않는 PHOTO 수정) [includeImageUrl]을
  /// false로 둔다 — 이미 서버 R2 키가 아닌 전체 URL을 그대로 되돌려보내면
  /// 안 되므로, 새로 업로드해 R2 키를 새로 받았을 때만 true로 넘긴다.
  Future<ServerBookMemoItem> patchItem({
    required int userBookId,
    required int itemId,
    required BookMemoItemType itemType,
    required int? startPage,
    required int? endPage,
    required String? content,
    required bool isImportant,
    String? imageUrl,
    bool includeImageUrl = false,
  }) async {
    try {
      final response = await _apiClient.dio.patch<Map<String, dynamic>>(
        '/api/me/books/$userBookId/memos/items/$itemId',
        data: {
          'itemType': itemType.dbValue,
          'startPage': startPage,
          'endPage': endPage,
          'content': content,
          'isImportant': isImportant,
          if (includeImageUrl) 'imageUrl': imageUrl,
        },
      );
      final data = _unwrapMap(response);
      return ServerBookMemoItem.fromJson(data);
    } on DioException catch (e) {
      throw _mapError(e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// DELETE /api/me/books/{userBookId}/memos/items/{itemId}
  Future<void> deleteItem({
    required int userBookId,
    required int itemId,
  }) async {
    try {
      await _apiClient.dio.delete<Map<String, dynamic>>(
        '/api/me/books/$userBookId/memos/items/$itemId',
      );
    } on DioException catch (e) {
      // 이미 서버에서 지워진 뒤 재시도로 다시 호출된 경우(직전 시도의 응답만
      // 못 받고 실제로는 성공했던 경우 등)도 "지우려는 목표는 달성됨"으로
      // 취급해 성공 처리한다 — 그러지 않으면 dirty가 영원히 풀리지 않는다.
      if (e.response?.statusCode == 404) return;
      throw _mapError(e);
    }
  }

  /// POST /api/memos/{memoId}/images — 이미지 업로드 후 R2 키 반환.
  Future<String> uploadImage({required int memoId, required File file}) async {
    try {
      final fileName = file.path.split(Platform.pathSeparator).last;
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(file.path, filename: fileName),
      });
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/memos/$memoId/images',
        data: formData,
      );
      final data = _unwrapMap(response);
      return data['imageUrl'] as String;
    } on DioException catch (e) {
      throw _mapError(e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// GET /api/me/memos/sync/changes — since 이후 변경분만 조회하는 증분 동기화.
  Future<BookMemoSyncChangesResult> getSyncChanges({
    required DateTime since,
  }) async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        '/api/me/memos/sync/changes',
        queryParameters: {'since': since.toUtc().toIso8601String()},
      );
      final data = _unwrapMap(response);
      return BookMemoSyncChangesResult.fromJson(data);
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
      _ => '요청 처리 중 오류가 발생했습니다.',
    };
    return ApiException(message, statusCode: statusCode, cause: e);
  }
}
