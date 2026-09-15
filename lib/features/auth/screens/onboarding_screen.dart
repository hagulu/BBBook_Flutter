import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_loading.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../providers/auth_notifier.dart';
import '../widgets/social_login_section.dart';

/// 온보딩(로그인) 화면.
///
/// 문서: docs/porting-reference/features/auth.md,
/// docs/porting-reference/screenshots/onboarding.jpg
///
/// 소셜 로그인 아래에 "로그인 없이 사용하기"를 둔다 — 계정을 만들지 않고
/// 이 기기에만 기록을 남기는 진입점이다(임시 서버 계정을 만들지 않는다).
/// 다시 로그인(재인증) 진입에서는 이미 계정이 있는 사용자이므로 감춘다.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.reauthentication = false});

  final bool reauthentication;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  Future<void> _continueWithoutAccount() async {
    AppLoading.show(context);
    try {
      await ref.read(authNotifierProvider.notifier).continueWithoutAccount();
    } catch (_) {
      if (mounted) {
        AppSnackBar.error(context, '시작하지 못했습니다. 다시 시도해 주세요.');
      }
    } finally {
      AppLoading.hide();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Scaffold(
      appBar: widget.reauthentication
          ? AppBar(title: const Text('다시 로그인'))
          : null,
      backgroundColor: colors.pageBackground,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: colors.shadowSoft,
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
                        color: colors.accentFill,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        PhosphorIconsRegular.bookOpen,
                        color: colors.textStrong,
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '북꾸러미',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: colors.textStrong,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.reauthentication
                          ? '기록을 동기화하려면 같은 계정으로 로그인해 주세요.'
                          : '로그인하고 기록을 시작하세요.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: colors.textMuted),
                    ),
                    const SizedBox(height: 28),
                    SocialLoginSection(
                      onLoggedIn: widget.reauthentication
                          ? () {
                              if (mounted) Navigator.of(context).pop();
                            }
                          : null,
                    ),
                    if (!widget.reauthentication) ...[
                      const SizedBox(height: 20),
                      Divider(height: 1, color: colors.border),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _continueWithoutAccount,
                        style: TextButton.styleFrom(
                          foregroundColor: colors.textBody,
                          minimumSize: const Size.fromHeight(44),
                        ),
                        child: const Text(
                          '로그인 없이 사용하기',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '기록은 이 기기에만 저장되고 다른 기기와 동기화되지 않습니다.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: colors.textMuted),
                      ),
                    ],
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
