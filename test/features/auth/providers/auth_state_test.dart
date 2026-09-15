import 'package:bbbook/features/auth/models/auth_user.dart';
import 'package:bbbook/features/auth/models/standalone_session.dart';
import 'package:bbbook/features/auth/providers/auth_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// 인증 상태 → 앱 진입 가능 여부/기록 소유자 매핑 테스트.
///
/// 계정 없이 쓰는 상태는 "앱은 쓸 수 있지만 로그인은 아니다"라는 중간 상태라,
/// 이 매핑이 틀어지면 라우터가 진입을 막거나(빈 화면) 반대로 서버 계정 전용
/// 화면이 열린다.
void main() {
  const user = AuthUser(
    id: 42,
    nickname: '독자',
    profileImageUrl: null,
    isFinishedBooksPublic: false,
  );

  test('계정 없이 쓰는 상태도 앱에 진입할 수 있지만 로그인 상태는 아니다', () {
    const state = AuthState(status: AuthStatus.standalone);

    expect(state.canUseApp, isTrue);
    expect(state.isStandalone, isTrue);
    expect(state.isLoggedIn, isFalse);
    expect(state.isAuthLoading, isFalse);
  });

  test('계정 없이 쓰는 상태의 기록 소유자는 고정 sentinel이다', () {
    const state = AuthState(status: AuthStatus.standalone);

    expect(state.recordOwnerId, standaloneOwnerUserId);
    // 서버 계정이 없다는 사실 자체는 그대로 유지한다 — 프로필 화면이 이
    // 값으로 계정 유무를 판단한다.
    expect(state.user, isNull);
  });

  test('로그인 사용자의 기록 소유자는 계정 id다', () {
    const state = AuthState(status: AuthStatus.authenticated, user: user);

    expect(state.recordOwnerId, 42);
    expect(state.isLoggedIn, isTrue);
    expect(state.isStandalone, isFalse);
  });

  test('인증이 풀린 로컬 전용 상태도 계정 기록 소유자를 유지한다', () {
    const state = AuthState(
      status: AuthStatus.localOnly,
      user: user,
      requiresLogin: true,
    );

    expect(state.canUseApp, isTrue);
    expect(state.isLoggedIn, isFalse);
    expect(state.recordOwnerId, 42);
  });

  test('미인증 상태는 앱에 진입할 수 없고 기록 소유자도 없다', () {
    const state = AuthState(status: AuthStatus.unauthenticated);

    expect(state.canUseApp, isFalse);
    expect(state.recordOwnerId, isNull);
  });

  test('sentinel은 서버가 발급하지 않는 값이라 실제 계정 id와 겹치지 않는다', () {
    expect(standaloneOwnerUserId, lessThan(0));
  });
}
