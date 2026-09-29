import 'dart:io';

import 'package:flutter/foundation.dart';

/// AdMob 배너 광고 단위 ID를 한 곳에서 관리한다. 지금은 Google 공식
/// 테스트 배너 광고 단위 ID만 사용하고, 실제 광고로 교체할 때는
/// 이 값만 바꾸면 된다(광고 삽입 화면들은 이 값을 몰라도 됨).
///
/// 테스트 배너 단위 ID는 플랫폼마다 다르다(Android/iOS가 같은 광고 단위 ID를
/// 공유하지 않음) — iOS에서 Android용 ID로 요청하면 로드가 실패해 광고가
/// 조용히 사라진다.
class AdConfig {
  const AdConfig._();

  /// TODO: 실제 서비스 배포 시 발급받은 배너 광고 단위 ID로 교체한다
  /// (Android/iOS 각각 별도로 발급받아야 한다). 교체 전에는 release 빌드도
  /// 이 테스트 ID를 그대로 쓰므로 [assertConfiguredForRelease]가 막는다.
  static String get bannerAdUnitId =>
      Platform.isIOS ? _iosTestBannerAdUnitId : _androidTestBannerAdUnitId;

  static const _androidTestBannerAdUnitId =
      'ca-app-pub-3940256099942544/6300978111';
  static const _iosTestBannerAdUnitId =
      'ca-app-pub-3940256099942544/2934735716';

  /// release 빌드가 실제 배너 광고 단위 ID로 교체되기 전에 테스트 ID를 그대로
  /// 배포하는 것을 막는다. `main()`에서 앱 시작 전에 한 번 호출한다
  /// (`ApiConfig`/`KakaoConfig`의 release 검사와 같은 관례).
  static void assertConfiguredForRelease() {
    const testIds = {_androidTestBannerAdUnitId, _iosTestBannerAdUnitId};
    if (kReleaseMode && testIds.contains(bannerAdUnitId)) {
      throw StateError(
        'AdMob 배너 광고 단위 ID가 아직 Google 공식 테스트 값입니다. release 빌드 '
        '전에 lib/core/config/ad_config.dart의 배너 광고 단위 ID를 실제 발급받은 '
        'ID로 교체하세요.',
      );
    }
  }
}
