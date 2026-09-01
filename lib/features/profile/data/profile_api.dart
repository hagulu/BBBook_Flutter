import 'dart:io';

import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/patch_field.dart';
import '../models/profile_me.dart';

/// 프로필(개인 페이지) 메인·수정 화면 API 호출.
///
/// 문서: ../../../../../api-doc/api-me-profile-get.md,
/// api-me-profile-patch.md, api-me-profile-image-post.md, api-me-delete.md
///
/// 독서 통계 요약은 서버 API(`api-me-reading-stats-profile-summary-get.md`) 대신
/// 로컬 서재 데이터([BookshelfRepository])로 직접 계산한다
/// (`lib/features/profile/providers/profile_providers.dart`의
/// `profileStatsSummaryProvider` 참고).
///
/// 인증 필요 요청이므로 401 시 1회 재시도 후 실패하면 로그아웃 처리하는
/// [ApiClient]를 통해서만 호출한다(CLAUDE.md 인증 API 호출 규칙).
class ProfileApi {
  ProfileApi({required this._apiClient});

  final ApiClient _apiClient;

  /// GET /api/me/profile
  Future<ProfileMe> getMyProfile() async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        '/api/me/profile',
      );
      return ProfileMe.fromJson(_unwrapMap(response));
    } on DioException catch (e) {
      throw _mapError(e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// PATCH /api/me/profile
  ///
  /// [nickname]이 null이면 요청에서 생략(기존 값 유지). [profileImageUrl]은
  /// 생략(유지)/[PatchField.value](수정)/[PatchField.clear](이미지 제거) 3-상태다.
  Future<ProfileMe> patchMyProfile({
    String? nickname,
    PatchField<String>? profileImageUrl,
  }) async {
    try {
      final response = await _apiClient.dio.patch<Map<String, dynamic>>(
        '/api/me/profile',
        data: {
          'nickname': ?nickname,
          if (profileImageUrl.isPresent)
            'profileImageUrl': profileImageUrl.requestValue,
        },
      );
      return ProfileMe.fromJson(_unwrapMap(response));
    } on DioException catch (e) {
      throw _mapError(e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// POST /api/me/profile/image — 업로드된 이미지의 공개 URL을 반환한다(이
  /// 호출만으로는 프로필에 반영되지 않고, 이어서 [patchMyProfile]을 호출해야 한다).
  Future<String> postProfileImage(File file) async {
    try {
      final fileName = file.path.split(Platform.pathSeparator).last;
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(file.path, filename: fileName),
      });
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/me/profile/image',
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

  /// DELETE /api/me — 회원 탈퇴(소프트 삭제, 리프레시 토큰 즉시 만료).
  /// 403(이미 탈퇴한 사용자)은 호출부가 [ApiException.statusCode]로 구분해
  /// 전용 안내 문구를 보여준다(api-me-delete.md 에러 규격).
  Future<void> deleteMe() async {
    try {
      await _apiClient.dio.delete<Map<String, dynamic>>('/api/me');
    } on DioException catch (e) {
      throw _mapError(e);
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
