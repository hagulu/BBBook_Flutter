import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/app_confirm.dart';
import '../data/social_auth_service.dart';
import '../providers/auth_notifier.dart';
import '../providers/auth_providers.dart';
import '../widgets/social_login_button.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

enum _LoadingProvider { none, google, apple }

/// 온보딩(로그인) 화면.
///
/// 문서: docs/porting-reference/features/auth.md,
/// docs/porting-reference/screenshots/onboarding.jpg
///
/// 카카오/네이버는 원본과 동일하게 UI만 노출하고 비활성화된 목업 버튼으로 둔다.
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
      backgroundColor: AppColors.pageBackground,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: AppColors.shadowSoft,
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
                        color: AppColors.accentFill,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        PhosphorIconsRegular.bookOpen,
                        color: AppColors.textStrong,
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '책책책',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textStrong,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.reauthentication
                          ? '기록을 동기화하려면 같은 계정으로 로그인해 주세요.'
                          : '로그인하고 기록을 시작하세요.',
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 28),
                    const SocialLoginButton(
                      label: '카카오로 시작하기',
                      icon: Icon(
                        PhosphorIconsRegular.chatCircle,
                        color: AppBrandColors.kakaoLabel,
                        size: 20,
                      ),
                      backgroundColor: AppBrandColors.kakao,
                      foregroundColor: AppBrandColors.kakaoLabel,
                      onPressed: null,
                    ),
                    const SizedBox(height: 12),
                    const SocialLoginButton(
                      label: '네이버로 시작하기',
                      icon: Text(
                        'N',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      backgroundColor: AppBrandColors.naver,
                      foregroundColor: Colors.white,
                      onPressed: null,
                    ),
                    const SizedBox(height: 12),
                    SocialLoginButton(
                      label: 'Google로 시작하기',
                      icon: const Text(
                        'G',
                        style: TextStyle(
                          color: AppBrandColors.google,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.textStrong,
                      border: const BorderSide(color: AppColors.border),
                      isLoading: _loading == _LoadingProvider.google,
                      onPressed: _isBusy ? null : _handleGoogleLogin,
                    ),
                    const SizedBox(height: 12),
                    SocialLoginButton(
                      label: 'Apple로 시작하기',
                      icon: const Icon(
                        PhosphorIconsRegular.appleLogo,
                        color: Colors.white,
                        size: 22,
                      ),
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      isLoading: _loading == _LoadingProvider.apple,
                      onPressed: (_isBusy || !isAppleSignInSupported)
                          ? null
                          : _handleAppleLogin,
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
}
