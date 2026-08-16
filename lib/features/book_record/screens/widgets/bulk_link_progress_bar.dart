import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../../core/theme/app_theme.dart';

/// ISBN 일괄 연결 흐름(`bulk_isbn_link_banner.dart`) 전용 "건너뛰기"/"중단"
/// 행. 책 정보 수정 시트(`book_info_edit_dialog.dart`)에서 쓴다(검색
/// 바텀시트는 제목 행에 [SkipStopButtons]를 직접 얹어 쓴다). 진행
/// 개수("N / 전체")는 각 시트의 제목 행에서 따로 보여준다 — 이 행은
/// 버튼만 담당한다. [leading]이 있으면(검색 시트의 "즉시 저장" 토글)
/// 왼쪽에, 버튼은 오른쪽에 붙는다.
class BulkLinkProgressBar extends StatelessWidget {
  const BulkLinkProgressBar({
    super.key,
    required this.onSkip,
    required this.onStop,
    this.leading,
  });

  final VoidCallback onSkip;
  final VoidCallback onStop;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    // `Row` + `Spacer`는 폭이 좁은 기기나 시스템 글자 배율이 큰 환경에서
    // (leading 토글 + 버튼 2개 폭 합이 가용 폭을 넘으면) RenderFlex
    // 오버플로가 난다. `Wrap`으로 바꿔 공간이 모자라면 건너뛰기/중단
    // 묶음이 다음 줄로 자연스럽게 내려가게 한다.
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [?leading, SkipStopButtons(onSkip: onSkip, onStop: onStop)],
    );
  }
}

/// "건너뛰기"/"중단" 필 버튼 한 쌍. 검색 시트의 제목 행, [BulkLinkProgressBar]
/// 양쪽에서 같은 모양으로 재사용한다.
class SkipStopButtons extends StatelessWidget {
  const SkipStopButtons({super.key, required this.onSkip, required this.onStop});

  final VoidCallback onSkip;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BulkActionPillButton(
          label: '건너뛰기',
          icon: PhosphorIconsRegular.skipForward,
          onTap: onSkip,
          color: AppColors.primary,
        ),
        const SizedBox(width: 8),
        BulkActionPillButton(
          label: '중단',
          icon: PhosphorIconsRegular.prohibit,
          onTap: onStop,
          color: AppColors.error,
        ),
      ],
    );
  }
}

/// "건너뛰기"/"중단"의 작은 필 버튼(아이콘 + 라벨).
class BulkActionPillButton extends StatelessWidget {
  const BulkActionPillButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    required this.color,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
