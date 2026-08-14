import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_snackbar.dart';
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
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  _LoadingProvider _loading = _LoadingProvider.none;

  bool get _isBusy => _loading != _LoadingProvider.none;

  Future<void> _handleGoogleLogin() {
    return _handleLogin(
      _LoadingProvider.google,
      () => ref.read(authNotifierProvider.notifier).loginWithGoogle(),
    );
  }

  Future<void> _handleAppleLogin() {
    return _handleLogin(
      _LoadingProvider.apple,
      () => ref.read(authNotifierProvider.notifier).loginWithApple(),
    );
  }

  Future<void> _handleLogin(
    _LoadingProvider provider,
    Future<void> Function() action,
  ) async {
    setState(() => _loading = provider);
    try {
      await action();
    } on SocialAuthException catch (e) {
      _showError(e.message);
    } on ApiException catch (e) {
      _showError(e.message);
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

  @override
  Widget build(BuildContext context) {
    final isAppleSignInSupported = ref
        .watch(socialAuthServiceProvider)
        .isAppleSignInSupported;

    return Scaffold(
      backgroundColor: AppColors.onboardingBackground,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: AppColors.cardBackground,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14181C20),
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
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        PhosphorIconsRegular.bookOpen,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '책책책',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.titleText,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '로그인하고 기록을 시작하세요.',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.tertiaryText,
                      ),
                    ),
                    const SizedBox(height: 28),
                    const SocialLoginButton(
                      label: '카카오로 시작하기',
                      icon: Icon(
                        PhosphorIconsRegular.chatCircle,
                        color: Color(0xFF3C1E1E),
                        size: 20,
                      ),
                      backgroundColor: Color(0xFFFEE500),
                      foregroundColor: Color(0xFF3C1E1E),
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
                      backgroundColor: Color(0xFF03C75A),
                      foregroundColor: Colors.white,
                      onPressed: null,
                    ),
                    const SizedBox(height: 12),
                    SocialLoginButton(
                      label: 'Google로 시작하기',
                      icon: const Text(
                        'G',
                        style: TextStyle(
                          color: Color(0xFF4285F4),
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.titleText,
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
