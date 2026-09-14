import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/app_confirm.dart';
import '../data/social_auth_service.dart';
import '../providers/auth_notifier.dart';
import '../providers/auth_providers.dart';
import '../widgets/social_login_button.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

enum _LoadingProvider { none, google, apple, kakao, naver }

/// 온보딩(로그인) 화면.
///
/// 문서: docs/porting-reference/features/auth.md,
/// docs/porting-reference/screenshots/onboarding.jpg
///
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.reauthentication = false});

  final bool reauthentication;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  _LoadingProvider _loading = _LoadingProvider.none;

  bool get _isBusy => _loading != _LoadingProvider.none;

  Future<void> _handleGoogleLogin() {
    return _handleLogin(
      _LoadingProvider.google,
      () => ref
          .read(authNotifierProvider.notifier)
          .loginWithGoogle(confirmAccountChange: _confirmAccountChange),
    );
  }

  Future<void> _handleKakaoLogin() {
    return _handleLogin(
      _LoadingProvider.kakao,
      () => ref
          .read(authNotifierProvider.notifier)
          .loginWithKakao(confirmAccountChange: _confirmAccountChange),
    );
  }

  Future<void> _handleNaverLogin() {
    return _handleLogin(
      _LoadingProvider.naver,
      () => ref
          .read(authNotifierProvider.notifier)
          .loginWithNaver(confirmAccountChange: _confirmAccountChange),
    );
  }

  Future<void> _handleAppleLogin() {
    return _handleLogin(
      _LoadingProvider.apple,
      () => ref
          .read(authNotifierProvider.notifier)
          .loginWithApple(confirmAccountChange: _confirmAccountChange),
    );
  }

  Future<void> _handleLogin(
    _LoadingProvider provider,
    Future<bool> Function() action,
  ) async {
    setState(() => _loading = provider);
    try {
      final loggedIn = await action();
      if (loggedIn && widget.reauthentication && mounted) {
        Navigator.of(context).pop();
      }
    } on SocialAuthException catch (e) {
      _showError(e.message);
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('로그인하지 못했습니다. 다시 시도해 주세요.');
    } finally {
      if (mounted) {
        setState(() => _loading = _LoadingProvider.none);
      }
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

  @override
  Widget build(BuildContext context) {
    final isAppleSignInSupported = ref
        .watch(socialAuthServiceProvider)
        .isAppleSignInSupported;

    return Scaffold(
      appBar: widget.reauthentication
          ? AppBar(title: const Text('다시 로그인'))
          : null,
      backgroundColor: AppColors.of(context).pageBackground,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: AppColors.of(context).surface,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.of(context).shadowSoft,
                      blurRadius: 24,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.of(context).accentFill,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        PhosphorIconsRegular.bookOpen,
                        color: AppColors.of(context).textStrong,
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '북꾸러미',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.of(context).textStrong,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.reauthentication
                          ? '기록을 동기화하려면 같은 계정으로 로그인해 주세요.'
                          : '로그인하고 기록을 시작하세요.',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.of(context).textMuted,
                      ),
                    ),
                    const SizedBox(height: 28),
                    ..._buildSocialLoginButtons(
                      context,
                      isAppleSignInSupported: isAppleSignInSupported,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSocialLoginButtons(
    BuildContext context, {
    required bool isAppleSignInSupported,
  }) {
    // Google 로그인 브랜딩 가이드라인의 플랫폼별 좌측 여백(로고 → 버튼 좌측)
    // 규격. iOS: 16, Android: 12.
    final isIOS = defaultTargetPlatform == TargetPlatform.iOS;
    final googleLeadingPadding = isIOS ? 16.0 : 12.0;
    final appleButtonHeight = MediaQuery.textScalerOf(context).scale(48);
    const appleButtonRadius = BorderRadius.all(Radius.circular(12));

    final buttons = <Widget>[
      if (isAppleSignInSupported)
        MediaQuery.withNoTextScaling(
          // 패키지는 높이로 글자 크기를 계산하므로 배율은 높이에 한 번만 적용한다.
          child: SizedBox(
            height: appleButtonHeight,
            width: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SignInWithAppleButton(
                  text: 'Apple로 계속하기',
                  height: appleButtonHeight,
                  borderRadius: appleButtonRadius,
                  iconAlignment: SignInWithAppleIconAlignment.left,
                  onPressed: _isBusy ? null : _handleAppleLogin,
                ),
                if (_loading == _LoadingProvider.apple)
                  const Positioned.fill(
                    child: ClipRRect(
                      borderRadius: appleButtonRadius,
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
        ),
      SocialLoginButton(
        iconAsset: 'assets/icon/social/google.svg',
        label: 'Google로 계속하기',
        backgroundColor: Colors.white,
        foregroundColor: AppBrandColors.googleLabel,
        border: const BorderSide(color: AppBrandColors.googleBorder),
        leadingPadding: googleLeadingPadding,
        isLoading: _loading == _LoadingProvider.google,
        onPressed: _isBusy ? null : _handleGoogleLogin,
      ),
      SocialLoginButton(
        iconAsset: 'assets/icon/social/kakao.svg',
        label: '카카오로 계속하기',
        backgroundColor: AppBrandColors.kakao,
        foregroundColor: AppBrandColors.kakaoLabel,
        borderRadius: 12,
        isLoading: _loading == _LoadingProvider.kakao,
        onPressed: _isBusy ? null : _handleKakaoLogin,
      ),
      SocialLoginButton(
        iconAsset: 'assets/icon/social/naver.svg',
        label: '네이버로 계속하기',
        backgroundColor: AppBrandColors.naver,
        foregroundColor: Colors.white,
        leadingPadding: 20,
        isLoading: _loading == _LoadingProvider.naver,
        onPressed: _isBusy ? null : _handleNaverLogin,
      ),
    ];

    return [
      for (var i = 0; i < buttons.length; i++) ...[
        if (i > 0) const SizedBox(height: 12),
        buttons[i],
      ],
    ];
  }
}
