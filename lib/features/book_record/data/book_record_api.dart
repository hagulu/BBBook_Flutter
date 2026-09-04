import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../bookshelf/models/book_tag.dart';
import '../../bookshelf/models/record_patch.dart';

/// 책 기록 상세 화면의 API 호출.
///
/// 문서: ../../../../../../api-doc/api-me-books-userBookId-patch.md,
/// api-me-books-userBookId-book-info-patch.md, api-me-books-userBookId-link-patch.md,
/// api-me-tags-get.md, api-me-books-userBookId-delete.md
///
/// 태그 추가/삭제(POST/DELETE `.../tags`)는 로컬 우선 동기화 대상이라
/// `TagApi`/`TagRepository`가 전담한다 — 이 클래스는 태그 자동완성 제안
/// 목록 조회(`getMyTags`)만 남아 있다.
///
/// 카테고리 목록(`GET /api/books/categories`)은 계정과 무관한 전역 마스터
/// 데이터라 `BookshelfApi.getCategories`가 대신 다룬다.
///
/// 인증 필요 요청이므로 401 시 1회 재시도 후 실패하면 로그아웃 처리하는
/// [ApiClient]를 통해서만 호출한다(CLAUDE.md 인증 API 호출 규칙).
///
/// 이 클래스의 PATCH류 응답에는 `createdAt`이 내려오지 않으므로(`updatedAt`은
/// 내려온다 — api-doc 기준) `Map<String, dynamic>`(순수 data 파트)을 그대로
/// 반환한다. `BookItem`으로 변환하는 것은 로컬 행의 createdAt을 알고 있는
/// 리포지토리 쪽 책임이다.
class BookRecordApi {
  BookRecordApi({required this._apiClient});

  final ApiClient _apiClient;

  /// PATCH /api/me/books/:userBookId — 독서 상태/진행률/평가 등 기본 기록 필드 수정.
  ///
  /// 어떤 필드를 어떻게 바꿀지는 [RecordPatch]가 전부 담는다 — 요청 body에
  /// 들어가는 키는 [RecordPatch.toJson]이 만든 것뿐이라, 사용자가 건드리지
  /// 않은 필드는 애초에 전송되지 않는다(서버는 "기존 값 유지"로 처리).
  /// 값 삭제는 `PatchField.clear()`로 표현한 명시적 `null`로만 가능하며,
  /// 빈 문자열은 삭제가 아니라 그대로 저장되는 값이다(문서 기준).
  ///
  /// status를 FINISHED로 보낼 때 `finishedAt`을 생략하면, 서버가
  /// `X-Timezone` 헤더로 오늘 날짜를 계산해 자동 설정한다. 이 앱은 한국어
  /// 전용 서비스라 타임존 판별 플러그인 없이 'Asia/Seoul'을 고정으로 보낸다.
  ///
  /// [updatedAt]은 이 요청이 기준으로 삼는 서버의 마지막 `updated_at`이다
  /// (문서 기준 낙관적 동시성 검사용). 값을 보내면 서버의 현재 updated_at과
  /// 달라졌을 때 409로 거부되고([ApiException.statusCode] == 409), 생략하면
  /// 충돌 검사 없이 무조건 수정된다.
  Future<Map<String, dynamic>> patchRecord({
    required int userBookId,
    required RecordPatch patch,
    DateTime? updatedAt,
  }) async {
    final body = <String, dynamic>{
      ...patch.toJson(),
      'updatedAt': ?updatedAt?.toUtc().toIso8601String(),
    };

    try {
      final response = await _apiClient.dio.patch<Map<String, dynamic>>(
        '/api/me/books/$userBookId',
        data: body,
        options: Options(headers: const {'X-Timezone': 'Asia/Seoul'}),
      );
      return _unwrapMap(response);
    } on DioException catch (e) {
      throw _mapError(e, overrides: const {409: '다른 곳에서 이미 수정된 기록입니다.'});
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// PATCH /api/me/books/:userBookId/book-info — 표시용 제목/저자/출판사/총쪽수/표지 수정.
  ///
  /// [thumbnailFile]이 있으면 새 표지를 업로드하고, [removeThumbnail]이
  /// true이면 표지를 제거한다(둘 다 아니면 표지는 현재값 유지). [author],
  /// [publisher], [statsTotalPages], [displayTotalPages], [categoryId]는
  /// null을 명시적으로 보내면 서버가 null로 저장한다(문서 기준, 메인 PATCH와
  /// 다른 의미론). [displayTotalPages]에 null을 보내면 override를 해제하고
  /// [statsTotalPages] 기준으로 되돌아간다.
  ///
  /// [coverImageUrl]은 [thumbnailFile]/[removeThumbnail]과 달리 값이 있을
  /// 때만 요청에 포함한다(생략 시 표지 현재값 유지 — 문서 기준 처리 우선순위
  /// 1.thumbnail 파트 2.removeThumbnail 3.coverImageUrl 4.유지). ISBN
  /// 불러오기/변경으로 채운 공개 책 표지 URL을 그대로 저장할 때 쓴다 —
  /// 파일 업로드/삭제와 동시에 쓸 일이 없어 그 두 값이 있으면 무시해도 된다.
  Future<Map<String, dynamic>> patchBookInfo({
    required int userBookId,
    required String title,
    String? author,
    String? publisher,
    int? statsTotalPages,
    int? displayTotalPages,
    int? categoryId,
    String? coverImageUrl,
    File? thumbnailFile,
    bool removeThumbnail = false,
  }) async {
    final dataMap = {
      'title': title,
      'author': author,
      'publisher': publisher,
      'statsTotalPages': statsTotalPages,
      'displayTotalPages': displayTotalPages,
      'categoryId': categoryId,
      'coverImageUrl': ?coverImageUrl,
    };

    try {
      final Response<Map<String, dynamic>> response;
      if (thumbnailFile != null || removeThumbnail) {
        final formData = FormData.fromMap({
          'data': MultipartFile.fromString(
            jsonEncode(dataMap),
            contentType: MediaType('application', 'json'),
          ),
          if (thumbnailFile != null)
            'thumbnail': await MultipartFile.fromFile(thumbnailFile.path),
        });
        response = await _apiClient.dio.patch<Map<String, dynamic>>(
          '/api/me/books/$userBookId/book-info',
          data: formData,
          queryParameters: {if (removeThumbnail) 'removeThumbnail': true},
        );
      } else {
        response = await _apiClient.dio.patch<Map<String, dynamic>>(
          '/api/me/books/$userBookId/book-info',
          data: dataMap,
        );
      }
      return _unwrapMap(response);
    } on DioException catch (e) {
      throw _mapError(e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// PATCH /api/me/books/:userBookId/link — 공용 book과 연결/재연결/연결 해제.
  ///
  /// [isbn13]이 null이면 연결 해제(커스텀 책 전환)다. 서버가 "필드 자체가
  /// 없으면 400"으로 구분하므로(문서 기준) null이어도 항상 키 자체는
  /// 요청 본문에 포함해야 한다 — 다른 메서드의 `'x': ?x`(null이면 키 생략)
  /// 패턴을 여기서 그대로 쓰면 연결 해제가 400으로 실패한다.
  Future<Map<String, dynamic>> patchLink({
    required int userBookId,
    required String? isbn13,
  }) async {
    try {
      final response = await _apiClient.dio.patch<Map<String, dynamic>>(
        '/api/me/books/$userBookId/link',
        data: {'isbn13': isbn13},
      );
      return _unwrapMap(response);
    } on DioException catch (e) {
      throw _mapError(
        e,
        overrides: const {
          400: '연결할 책 정보를 확인해주세요(이미 읽은 쪽수가 총 쪽수보다 많을 수 있어요).',
          404: '연결할 책을 찾을 수 없습니다.',
          409: '이미 다른 책에 연결된 ISBN입니다.',
        },
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// GET /api/books/options — 전자책/오디오북 플랫폼 선택 목록.
  Future<Map<String, List<String>>> getPlatformOptions() async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        '/api/books/options',
      );
      final data = _unwrapMap(response);
      final platforms = data['platforms'] as Map<String, dynamic>? ?? const {};
      return platforms.map(
        (key, value) => MapEntry(key, (value as List<dynamic>).cast<String>()),
      );
    } on DioException catch (e) {
      throw _mapError(e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// GET /api/me/tags — 태그 자동완성 제안 목록. 순수 조회 전용이라 응답의
  /// `BookTag.id`는 서버 태그 ID 그대로다([BookTag] 문서의 "로컬 ID" 규칙과
  /// 다름) — 호출부(`tag_section.dart`)는 이 목록에서 `name`만 골라 태그
  /// 추가에 쓰고 `id`는 쓰지 않는다.
  Future<List<BookTag>> getMyTags({String? status}) async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        '/api/me/tags',
        queryParameters: {'status': ?status},
      );
      final body = response.data;
      if (body == null || body['data'] is! List) {
        throw const ApiException('서버 응답을 처리할 수 없습니다.');
      }
      return (body['data'] as List<dynamic>)
          .map((e) => BookTag.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw _mapError(e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// DELETE /api/me/books/:userBookId — 서재에서 책 제거(soft delete).
  Future<void> deleteUserBook(int userBookId) async {
    try {
      await _apiClient.dio.delete<Map<String, dynamic>>(
        '/api/me/books/$userBookId',
      );
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Map<String, dynamic> _unwrapMap(Response<Map<String, dynamic>> response) {
    final body = response.data;
    if (body == null || body['data'] is! Map<String, dynamic>) {
      throw const ApiException('서버 응답을 처리할 수 없습니다.');
    }
    return body['data'] as Map<String, dynamic>;
  }

  ApiException _mapError(DioException e, {Map<int, String>? overrides}) {
    final statusCode = e.response?.statusCode;
    final message =
        overrides?[statusCode] ??
        switch (statusCode) {
          400 => '입력값을 확인해주세요.',
          401 => '인증에 실패했습니다.',
          404 => '존재하지 않거나 접근할 수 없는 책입니다.',
          _ => '요청 처리 중 오류가 발생했습니다.',
        };
    return ApiException(message, statusCode: statusCode, cause: e);
  }
}
