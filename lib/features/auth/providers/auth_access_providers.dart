import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_notifier.dart';

/// 로컬 개인 기록(노트·독후감)의 소유자 id.
///
/// 로그인 사용자는 계정 id, 계정 없이 쓰는 사용자는 고정 sentinel이다
/// ([AuthState.recordOwnerId]). 기록 계열 provider/화면은 `auth.user?.id`를
/// 직접 읽지 말고 이 값을 쓴다 — 그래야 비로그인 지원 때문에 화면마다 인증
/// 분기를 다시 쓰지 않는다.
final recordOwnerIdProvider = Provider<int?>((ref) {
  return ref.watch(authNotifierProvider.select((auth) => auth.recordOwnerId));
});

/// 서버 계정이 필요한 작성·참여 기능(독자평/토론/공감/신고/독후감 공개 등)을
/// 화면에 노출해도 되는지.
///
/// 계정 없이 쓰는 사용자에게만 false다. 비활성화가 아니라 아예 숨기는 것이
/// 정책이므로 호출부는 이 값으로 위젯 자체를 만들지 않는다.
final canUseAccountFeaturesProvider = Provider<bool>((ref) {
  return !ref.watch(authNotifierProvider.select((auth) => auth.isStandalone));
});
