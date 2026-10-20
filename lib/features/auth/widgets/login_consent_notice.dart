import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/config/policy_link.dart';
import '../../../core/theme/app_theme.dart';

/// 온보딩 하단의 이용약관 동의·개인정보처리방침 적용 안내 문구.
///
/// '이용약관'·'개인정보처리방침'을 누르면 해당 정책 페이지를 외부 브라우저로 연다.
class LoginConsentNotice extends StatefulWidget {
  const LoginConsentNotice({super.key});

  @override
  State<LoginConsentNotice> createState() => _LoginConsentNoticeState();
}

class _LoginConsentNoticeState extends State<LoginConsentNotice> {
  late final _termsRecognizer = TapGestureRecognizer()
    ..onTap = PolicyLink.terms.open;
  late final _privacyRecognizer = TapGestureRecognizer()
    ..onTap = PolicyLink.privacy.open;

  @override
  void dispose() {
    _termsRecognizer.dispose();
    _privacyRecognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final linkStyle = TextStyle(
      color: colors.textBody,
      decoration: TextDecoration.underline,
      decorationColor: colors.border,
    );

    // 한 줄로 두고, 좁은 화면에서 넘치면 줄바꿈 대신 글자를 줄여 맞춘다.
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: '계속 진행하면 '),
              TextSpan(
                text: '이용약관',
                style: linkStyle,
                recognizer: _termsRecognizer,
              ),
              const TextSpan(text: '에 동의하며, '),
              TextSpan(
                text: '개인정보처리방침',
                style: linkStyle,
                recognizer: _privacyRecognizer,
              ),
              const TextSpan(text: '이 적용됩니다.'),
            ],
          ),
          maxLines: 1,
          style: TextStyle(
            fontSize: 10,
            height: 1.6,
            letterSpacing: -0.2,
            color: colors.textMuted,
          ),
        ),
      ),
    );
  }
}
