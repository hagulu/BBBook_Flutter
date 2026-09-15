import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_confirm.dart';
import '../../../shared/widgets/app_dialog_shell.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../server_storage_migration/screens/server_storage_migration_screen.dart';
import '../data/social_auth_service.dart';
import '../models/standalone_session.dart';
import '../providers/auth_notifier.dart';
import '../providers/auth_providers.dart';
import 'social_login_button.dart';

enum _LoadingProvider { none, google, apple, kakao, naver }

/// 지원하는 소셜 로그인 버튼 묶음과 로그인 처리.
///
/// 온보딩 화면과 MY 화면 상단 로그인 유도 영역이 공유한다 — 로그인 직후
/// 처리(계정 변경 확인, 계정 없이 쌓아 둔 기록 이어가기 선택, 기존 로컬 →
/// 서버 저장 전환 화면 연결)를 한 곳에만 둔다.
class SocialLoginSection extends ConsumerStatefulWidget {
  const SocialLoginSection({super.key, this.compact = false, this.onLoggedIn});

  /// MY 화면처럼 좁은 영역에 넣을 때 2열 그리드의 작은 버튼으로 그린다.
  final bool compact;

  /// 로그인이 끝난 뒤(저장 방식 전환 화면까지 마친 뒤) 호출된다.
  final VoidCallback? onLoggedIn;

  @override
  ConsumerState<SocialLoginSection> createState() => _SocialLoginSectionState();
}

class _SocialLoginSectionState extends ConsumerState<SocialLoginSection> {
  _LoadingProvider _loading = _LoadingProvider.none;

  bool get _isBusy => _loading != _LoadingProvider.none;

  Future<void> _handleLogin(
    _LoadingProvider provider,
    Future<bool> Function({
      Future<bool> Function()? confirmAccountChange,
      Future<StandaloneRecordAction?> Function()? askStandaloneRecordAction,
    })
    login,
  ) async {
    setState(() => _loading = provider);
    // 로그인에 성공하면 이 위젯이 곧 사라진다(MY 화면은 프로필 카드로,
    // 온보딩은 메인 화면으로 바뀐다) — 전환 화면으로 넘어갈 Navigator는
    // await 전에 잡아 둔다.
    final navigator = Navigator.of(context, rootNavigator: true);
    // 선택 결과는 여기서 붙잡아 둔다 — "계정에 올리기"를 고른 경우에만
    // 로그인 직후 기존 저장 방식 전환(Import) 화면으로 이어 간다.
    StandaloneRecordAction? recordAction;
    try {
      final loggedIn = await login(
        confirmAccountChange: _confirmAccountChange,
        askStandaloneRecordAction: () async {
          recordAction = await _askStandaloneRecordAction();
          return recordAction;
        },
      );
      if (!loggedIn) return;
      if (recordAction == StandaloneRecordAction.uploadToAccount) {
        await navigator.push<void>(
          MaterialPageRoute(
            builder: (_) => const ServerStorageMigrationScreen(),
          ),
        );
      }
      widget.onLoggedIn?.call();
    } on SocialAuthException catch (e) {
      _showError(e.message);
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('로그인하지 못했습니다. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _loading = _LoadingProvider.none);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    AppSnackBar.error(context, message);
  }

  Future<bool> _confirmAccountChange() async {
    if (!mounted) return false;
    return AppConfirm.show(
      context,
      title: '다른 계정으로 로그인',
      message:
          '로그인하면 이 기기에 저장된 기존 계정의 책, 노트, 메모, 독후감과 이미지가 모두 삭제됩니다. 서버에 동기화하지 못한 기록은 복구할 수 없습니다. 계속할까요?',
      confirmText: '모두 삭제하고 로그인',
      destructive: true,
    );
  }

  /// 로그인 없이 남긴 기록이 있을 때만 호출된다. 어느 쪽을 고르든 기록은
  /// 지우지 않는다 — 계정에 올릴지, 이 기기에만 둘지만 정한다.
  ///
  /// [AppConfirm]은 확인/취소 2択이라 바깥 탭·뒤로 가기(dismiss)도 취소와
  /// 똑같이 `false`로 합친다. 여기서는 그 `false`가 "이 기기에만 두기"라는
  /// 유효한 선택이 되므로, dismiss와 실제 선택을 구분하지 못하면 사용자가
  /// 아무것도 고르지 않고 닫아도 로그인이 조용히 계속된다. 그래서 이
  /// 다이얼로그만 [AppConfirm]을 거치지 않고 세 값(업로드/기기에만 두기/
  /// dismiss=`null`)을 직접 구분해 반환한다. 바깥 탭·시스템 뒤로 가기는
  /// 막지 않고 `null`로 돌려보내 로그인 자체를 중단시킨다
  /// ([AuthNotifier._adoptLocalRecordsForLogin]의 `action == null` 분기).
  Future<StandaloneRecordAction?> _askStandaloneRecordAction() async {
    if (!mounted) return null;
    return showDialog<StandaloneRecordAction>(
      context: context,
      builder: (dialogContext) => AppDialogShell(
        title: '기록 동기화',
        message:
            '로그인 없이 이 기기에 남긴 기록이 있습니다.\n\n'
            '계정에 올리면 다른 기기에서도 볼 수 있고, 올리지 않으면 이 기기에만 그대로 남습니다. '
            '나중에 설정에서 동기화를 켜서 올릴 수도 있습니다.',
        actions: [
          AppDialogAction(
            label: '이 기기에만 두기',
            style: AppDialogActionStyle.neutral,
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(StandaloneRecordAction.keepOnDevice),
          ),
          AppDialogAction(
            label: '계정에 올리기',
            style: AppDialogActionStyle.primary,
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(StandaloneRecordAction.uploadToAccount),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(authNotifierProvider.notifier);
    final isAppleSignInSupported = ref
        .watch(socialAuthServiceProvider)
        .isAppleSignInSupported;

    // Google 로그인 브랜딩 가이드라인의 플랫폼별 좌측 여백(로고 → 버튼 좌측)
    // 규격. iOS: 16, Android: 12.
    final isIOS = defaultTargetPlatform == TargetPlatform.iOS;
    final googleLeadingPadding = widget.compact ? 10.0 : (isIOS ? 16.0 : 12.0);
    final buttonHeight = MediaQuery.textScalerOf(
      context,
    ).scale(widget.compact ? 42 : 48);

    final buttons = <Widget>[
      if (isAppleSignInSupported)
        _AppleButton(
          height: buttonHeight,
          label: widget.compact ? 'Apple' : 'Apple로 계속하기',
          isLoading: _loading == _LoadingProvider.apple,
          onPressed: _isBusy
              ? null
              : () => _handleLogin(
                  _LoadingProvider.apple,
                  notifier.loginWithApple,
                ),
        ),
      SocialLoginButton(
        iconAsset: 'assets/icon/social/google.svg',
        label: widget.compact ? 'Google' : 'Google로 계속하기',
        backgroundColor: Colors.white,
        foregroundColor: AppBrandColors.googleLabel,
        border: const BorderSide(color: AppBrandColors.googleBorder),
        leadingPadding: googleLeadingPadding,
        minimumHeight: buttonHeight,
        isLoading: _loading == _LoadingProvider.google,
        onPressed: _isBusy
            ? null
            : () => _handleLogin(
                _LoadingProvider.google,
                notifier.loginWithGoogle,
              ),
      ),
      SocialLoginButton(
        iconAsset: 'assets/icon/social/kakao.svg',
        label: widget.compact ? '카카오' : '카카오로 계속하기',
        backgroundColor: AppBrandColors.kakao,
        foregroundColor: AppBrandColors.kakaoLabel,
        borderRadius: 12,
        leadingPadding: widget.compact ? 10 : 16,
        minimumHeight: buttonHeight,
        isLoading: _loading == _LoadingProvider.kakao,
        onPressed: _isBusy
            ? null
            : () =>
                  _handleLogin(_LoadingProvider.kakao, notifier.loginWithKakao),
      ),
      SocialLoginButton(
        iconAsset: 'assets/icon/social/naver.svg',
        label: widget.compact ? '네이버' : '네이버로 계속하기',
        backgroundColor: AppBrandColors.naver,
        foregroundColor: Colors.white,
        leadingPadding: widget.compact ? 10 : 20,
        minimumHeight: buttonHeight,
        isLoading: _loading == _LoadingProvider.naver,
        onPressed: _isBusy
            ? null
            : () =>
                  _handleLogin(_LoadingProvider.naver, notifier.loginWithNaver),
      ),
    ];

    if (!widget.compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < buttons.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            buttons[i],
          ],
        ],
      );
    }

    // 좁은 영역에서도 프로필 카드를 넘지 않도록 2열로 접는다.
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 8.0;
        final columnWidth = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final button in buttons)
              SizedBox(width: columnWidth, child: button),
          ],
        );
      },
    );
  }
}

/// Apple 로그인 버튼. 패키지 위젯이 높이로 글자 크기를 계산하므로 글자 배율은
/// 높이에 한 번만 적용한다.
class _AppleButton extends StatelessWidget {
  const _AppleButton({
    required this.height,
    required this.label,
    required this.isLoading,
    required this.onPressed,
  });

  final double height;
  final String label;
  final bool isLoading;
  final VoidCallback? onPressed;

  static const _radius = BorderRadius.all(Radius.circular(12));

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withNoTextScaling(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SignInWithAppleButton(
              text: label,
              height: height,
              borderRadius: _radius,
              iconAlignment: SignInWithAppleIconAlignment.left,
              onPressed: onPressed,
            ),
            if (isLoading)
              const Positioned.fill(
                child: ClipRRect(
                  borderRadius: _radius,
                  child: ColoredBox(
                    color: Colors.black87,
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
