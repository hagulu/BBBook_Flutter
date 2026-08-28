import 'package:flutter/material.dart';

/// 앱바 타이틀 공용 위젯. 기본 앱바 높이(56)에 맞춘 축소 글씨 크기를 쓰고,
/// `subtitle`을 지정하면 제목 아래에 작게 배치한다(서브타이틀이 필요한 화면만
/// 선택적으로 사용) — 이때는 제목도 14로 한 단계 더 줄여 두 줄이 한 덩어리로
/// 보이게 한다. 두 줄일 때도 시스템 폰트 확대 배율 최대치(AppBar가 clamp하는
/// 1.34배)까지 곱해도 56 안에 들어오도록 크기를 정했다
/// (14*1.1 + 11*1.1 ≈ 27.5, ×1.34 ≈ 36.9 < 56).
///
/// 색상은 지정하지 않는다 — `AppBar`가 화면별 `foregroundColor`로 만든
/// 주변 `DefaultTextStyle` 색을 그대로 물려받아야 어두운 배경(카메라 등)에서도
/// 깨지지 않는다. 서브타이틀은 그 색의 불투명도만 낮춰 옅게 표시한다.
class AppBarTitle extends StatelessWidget {
  const AppBarTitle(this.title, {super.key, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    final hasSubtitle = subtitle != null && subtitle.isNotEmpty;

    final titleText = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: hasSubtitle ? 14 : 16,
        fontWeight: FontWeight.w600,
        height: 1.1,
      ),
    );

    if (!hasSubtitle) {
      return titleText;
    }

    final ambientColor = DefaultTextStyle.of(context).style.color;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        titleText,
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            height: 1.1,
            color: ambientColor?.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}
