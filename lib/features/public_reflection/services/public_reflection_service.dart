import 'dart:developer' as developer;

import '../../../core/network/api_exception.dart';
import '../data/public_reflection_source.dart';
import '../models/public_reflection.dart';

/// 공개 목록과 리더에 노출 가능한 데이터만 통과시키는 조회 서비스.
///
/// 목록 API가 숨김 항목을 마스킹해 내려주는 기존 계약도 방어적으로 처리한다.
/// 상세 노출 가능 여부는 `GET /api/reflections/{reflectionId}` 계약이 판정한다.
/// 공개 목록에서 선택한 ID만 이 서비스로 들어오므로 성공 응답에는 웹과 같은
/// 추가 상태·ISBN 검증을 적용하지 않는다.
class PublicReflectionService {
  const PublicReflectionService(this._source);

  final PublicReflectionSource _source;

  Future<PublicReflectionsPage> getPage({
    required String isbn13,
    int? cursor,
    int size = 20,
  }) async {
    var requestCursor = cursor;
    final visibleItems = <PublicReflectionSummary>[];
    int? nextCursor;
    var hasNext = true;

    while (hasNext && visibleItems.length < size) {
      late final PublicReflectionsPage page;
      try {
        page = await _source.fetchPage(
          isbn13: isbn13,
          cursor: requestCursor,
          size: size,
        );
      } catch (error) {
        developer.log(
          '[공개 독후감 목록 조회] isbn13=$isbn13 result=FAIL '
          'reason=${_reasonOf(error)}',
        );
        rethrow;
      }

      visibleItems.addAll(
        page.items.where((reflection) => !reflection.isHidden),
      );
      nextCursor = page.nextCursor;
      hasNext = page.hasNext;

      if (hasNext && (nextCursor == null || nextCursor == requestCursor)) {
        developer.log(
          '[공개 독후감 목록 조회] isbn13=$isbn13 result=FAIL '
          'reason=invalid_cursor',
        );
        throw const ApiException('서버 응답을 처리할 수 없습니다.');
      }

      requestCursor = nextCursor;
    }

    developer.log('[공개 독후감 목록 조회] isbn13=$isbn13 result=SUCCESS');
    return PublicReflectionsPage(
      items: List.unmodifiable(visibleItems),
      nextCursor: nextCursor,
      hasNext: hasNext,
    );
  }

  Future<PublicReflectionDetail> getDetail({
    required String isbn13,
    required int reflectionId,
  }) async {
    late final PublicReflectionDetail detail;
    try {
      detail = await _source.fetchDetail(reflectionId);
    } catch (error) {
      developer.log(
        '[공개 독후감 상세 조회] reflectionId=$reflectionId result=FAIL '
        'reason=${_reasonOf(error)}',
      );
      rethrow;
    }

    developer.log(
      '[공개 독후감 상세 조회] isbn13=$isbn13 reflectionId=$reflectionId '
      'result=SUCCESS',
    );
    return detail;
  }

  String _reasonOf(Object error) {
    if (error is ApiException) {
      return error.statusCode == null
          ? 'invalid_response'
          : 'http_${error.statusCode}';
    }
    return 'request_failed';
  }
}
