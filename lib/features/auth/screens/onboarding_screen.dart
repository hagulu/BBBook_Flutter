import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_confirm.dart';
import '../../../shared/widgets/app_loading.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../providers/auth_notifier.dart';
import '../widgets/login_consent_notice.dart';
import '../widgets/social_login_section.dart';

/// 온보딩(로그인) 화면.
///
/// 문서: docs/porting-reference/features/auth.md
///
/// 카드 없이 화면 전체를 쓴다 — 소셜 로그인·"로그인 없이 사용하기"·약관
/// 안내는 하단에 모으고, 로고·앱 이름·소개 문구는 그 위 남은 공간에서
/// 가운데보다 조금 아래(하단 묶음 쪽)에 둔다. 화면이 낮거나 글자 배율이
/// 커서 넘치면 스크롤된다.
///
/// "로그인 없이 사용하기"는 계정을 만들지 않고 이 기기에만 기록을 남기는
/// 진입점이다(임시 서버 계정을 만들지 않는다). 다시 로그인(재인증)
/// 진입에서는 이미 계정이 있는 사용자이므로 감춘다.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.reauthentication = false});

  final bool reauthentication;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  Future<void> _continueWithoutAccount() async {
    final confirmed = await AppConfirm.show(
      context,
      title: '로그인 없이 사용하기',
      message:
          '기록은 이 기기에만 저장되고 다른 기기와 동기화되지 않습니다.\n'
          '로그인이 필요한 일부 기능은 사용할 수 없습니다.',
      confirmText: '시작하기',
    );
    if (!confirmed || !mounted) return;

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
      // 화면 높이를 채우되 넘치면 스크롤되도록 SliverFillRemaining에 둔다.
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 남는 높이를 위 2 : 가운데 1로 나눠 소개 문구와 로그인
                        // 버튼 사이가 너무 벌어지지 않게 한다.
                        const Spacer(flex: 2),
                        _Brand(
                          message: widget.reauthentication
                              ? '기록을 동기화하려면\n같은 계정으로 로그인해 주세요.'
                              : '차곡차곡 쌓아 가는 나의 독서 기록',
                        ),
                        const SizedBox(height: 40),
                        const Spacer(),
                        SocialLoginSection(
                          onLoggedIn: widget.reauthentication
                              ? () {
                                  if (mounted) Navigator.of(context).pop();
                                }
                              : null,
                        ),
                        if (!widget.reauthentication) ...[
                          const SizedBox(height: 20),
                          Center(
                            child: SizedBox(
                              width: 240,
                              child: Divider(
                                height: 1,
                                color: colors.border.withValues(alpha: 0.65),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _continueWithoutAccount,
                            style: TextButton.styleFrom(
                              foregroundColor: colors.textBody,
                              minimumSize: const Size.fromHeight(44),
                            ),
                            // TextDecoration.underline은 한글(대체 폰트)과
                            // 공백(기본 폰트)의 밑줄 위치가 달라 공백에서
                            // 선이 들뜬다 — 글자 묶음 아래 테두리로 긋는다.
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: colors.textMuted),
                                ),
                              ),
                              child: const Text(
                                '로그인 없이 사용하기',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                          ),
                        ],
                        // 약관 안내는 로그인 묶음과 떨어뜨려 꼬리말처럼 둔다.
                        const SizedBox(height: 32),
                        const LoginConsentNotice(),
                      ],
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

/// 로고·앱 이름·소개 문구.
class _Brand extends StatelessWidget {
  const _Brand({required this.message});

  // assets/images/app_logo.png(1x) 크기. 2.0x/3.0x 변형은 같은 비율로 둔다.
  static const double _logoWidth = 56;
  static const double _logoHeight = 48;

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Column(
      children: [
        Image.asset(
          'assets/images/app_logo.png',
          width: _logoWidth,
          height: _logoHeight,
        ),
        const SizedBox(height: 20),
        Text(
          '북꾸러미',
          style: TextStyle(
            fontSize: 26,
            height: 1.2,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            color: colors.textStrong,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            letterSpacing: -0.3,
            color: colors.textMuted,
          ),
        ),
      ],
    );
  }
}
