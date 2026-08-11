import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// 완독 목록 표지 전용 디스크 캐시.
///
/// 원본 바이트를 그대로 저장해 재방문 시 네트워크 재요청을 없앤다(디코딩
/// 크기 제한은 `BookCover`에서 `ResizeImage`로 별도 처리 — 이 매니저에
/// `maxWidth`/`maxHeight`를 넘기면 포맷에 따라 원본 디코딩·리사이즈
/// 디코딩·PNG 재인코딩이 추가로 들어가 콜드 캐시 스크롤이 오히려 무거워진다).
/// 완독 목록은 기록이 누적될수록 카드 수가 많아져 기본 캐시 매니저의
/// `maxNrOfCacheObjects`(200)를 넘기기 쉬우므로 별도 인스턴스로 여유를 둔다.
class FinishedCoverCacheManager extends CacheManager {
  FinishedCoverCacheManager._()
      : super(
          Config(
            key,
            stalePeriod: const Duration(days: 30),
            maxNrOfCacheObjects: 500,
          ),
        );

  static const key = 'finishedCoverCache';

  static final FinishedCoverCacheManager instance = FinishedCoverCacheManager._();
}
