import 'package:bbbook/features/auth/models/auth_user.dart';
import 'package:bbbook/features/auth/providers/auth_access_providers.dart';
import 'package:bbbook/features/auth/providers/auth_notifier.dart';
import 'package:bbbook/features/auth/providers/auth_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('징계 상태 변경 직후 공개 작성 권한이 제한되고 해제 시 복구된다', () {
    final container = ProviderContainer(
      overrides: [authNotifierProvider.overrideWith(_FakeAuthNotifier.new)],
    );
    addTearDown(container.dispose);

    expect(container.read(canPublishCommunityContentProvider), isTrue);
    (container.read(authNotifierProvider.notifier) as _FakeAuthNotifier)
        .setSanctioned(true);
    expect(container.read(canPublishCommunityContentProvider), isFalse);
    (container.read(authNotifierProvider.notifier) as _FakeAuthNotifier)
        .setSanctioned(false);
    expect(container.read(canPublishCommunityContentProvider), isTrue);
  });
}

class _FakeAuthNotifier extends AuthNotifier {
  @override
  AuthState build() => const AuthState(
    status: AuthStatus.authenticated,
    user: AuthUser(
      id: 1,
      nickname: null,
      profileImageUrl: null,
      isFinishedBooksPublic: false,
    ),
  );

  void setSanctioned(bool value) {
    state = AuthState(
      status: AuthStatus.authenticated,
      user: AuthUser(
        id: 1,
        nickname: null,
        profileImageUrl: null,
        isFinishedBooksPublic: false,
        isSanctioned: value,
      ),
    );
  }
}
