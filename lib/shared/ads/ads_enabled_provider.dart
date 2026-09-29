import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 앱 전체 광고 노출 여부를 결정하는 단일 지점.
///
/// 지금은 항상 켜져 있지만(`true`), 추후 "광고 제거" 구매·프리미엄 등급
/// 등 출처가 생기면 이 provider의 구현(override)만 바꾸면 화면마다 따로
/// 조건을 넣지 않아도 모든 광고(`AppBannerAd`/`AppInlineBannerAd` 공통,
/// 그리고 목록 중간 광고의 슬롯 계산 자체)가 함께 꺼진다.
final adsEnabledProvider = Provider<bool>((ref) => true);
