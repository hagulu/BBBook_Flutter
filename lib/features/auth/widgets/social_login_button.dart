import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 온보딩 화면의 소셜 로그인 버튼 공통 위젯.
///
/// 심볼은 좌측 고정 여백에 배치하고, 레이블은 버튼 전체 폭 기준 가운데
/// 정렬한다(우측에 심볼과 동일한 폭의 여백을 대칭으로 둬 겹침 없이 중앙 정렬).
class SocialLoginButton extends StatelessWidget {
  const SocialLoginButton({
    super.key,
    required this.iconAsset,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    this.onPressed,
    this.isLoading = false,
    this.border,
    this.borderRadius = 14,
    this.leadingPadding = 16,
  });

  final String iconAsset;
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback? onPressed;
  final bool isLoading;
  final BorderSide? border;
  final double borderRadius;
  final double leadingPadding;

  static const _iconSize = 20.0;

  @override
  Widget build(BuildContext context) {
    final isDisabled = onPressed == null;
    final icon = isLoading
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: isDisabled
                  ? foregroundColor.withValues(alpha: 0.5)
                  : foregroundColor,
            ),
          )
        : Opacity(
            opacity: isDisabled ? 0.5 : 1,
            child: SvgPicture.asset(
              iconAsset,
              width: _iconSize,
              height: _iconSize,
            ),
          );

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          disabledBackgroundColor: backgroundColor.withValues(alpha: 0.5),
          disabledForegroundColor: foregroundColor.withValues(alpha: 0.5),
          elevation: 0,
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
            side: border ?? BorderSide.none,
          ),
        ),
        child: Row(
          children: [
            SizedBox(width: leadingPadding),
            icon,
            Expanded(
              child: Center(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
            // 좌측(여백+심볼)과 동일한 폭을 우측에도 확보해 레이블이 버튼
            // 전체 폭 기준으로 가운데 오도록 대칭을 맞춘다.
            SizedBox(width: leadingPadding + _iconSize),
          ],
        ),
      ),
    );
  }
}
