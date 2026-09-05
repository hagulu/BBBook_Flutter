import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../../core/theme/app_theme.dart';

/// "또 볼래" 회귀/다시 읽기 토글. 책 검색 상세의 완독 추가 팝업
/// (`FinishOptionsDialog`)과 재독 횟수 조정 팝업, 책 기록 상세 화면
/// (`book_record_screen.dart`)이 공유한다. 완독 확인 팝업(`FinishConfirmDialog`)
/// 은 같은 라벨/아이콘/색을 쓰되 `BoolIconOption`으로 명작과 한 행에 두므로
/// 이 위젯 자체는 쓰지 않는다. 내가 나에게
/// 남기는 기록이라 라벨은 존댓말이 아니라 반말로 쓴다. 전용 색상을 새로
/// 만들지 않고 [AppColors.error] 색을 그대로 쓴다.
///
/// [compact]가 true면 작은 원형 아이콘 옆에 짧은 라벨만 붙인 필 형태로
/// 그린다 — 재독 횟수 팝업처럼 콘텐츠가 가운데 정렬된 화면에서, 전체 폭
/// 행이 아니라 시트 제목 옆(`RecordDialogHeader.trailing`)에 붙이는 용도다.
/// 아이콘만 두면 무슨 뜻인지 알기 어려워 라벨은 compact에서도 유지한다.
class WantToRereadToggle extends StatelessWidget {
  const WantToRereadToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.compact = false,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 30.0 : 40.0;
    final iconSize = compact ? 16.0 : 20.0;
    final labelColor = value ? AppColors.error : AppColors.textBody;
    final badge = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: value
            ? AppColors.error.withValues(alpha: 0.12)
            : AppColors.surfaceSubtle,
      ),
      // 다른 상태 아이콘(ReadingStatusTile/명작 토글)과 같은 "원형 배경 +
      // 아이콘" 언어를 재사용해 이질감 없이 어울리게 한다. 회귀/다시 읽기를
      // 뜻하는 아이콘을 쓴다(book_record_screen.dart의 또 볼래요 토글과 동일).
      child: Icon(
        value ? PhosphorIconsFill.repeat : PhosphorIconsRegular.repeat,
        size: iconSize,
        color: value ? AppColors.error : AppColors.controlInactive,
      ),
    );

    final row = Row(
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      children: [
        badge,
        SizedBox(width: compact ? 6 : 12),
        compact
            ? Text(
                '또 볼래',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: labelColor,
                ),
              )
            : Expanded(
                child: Text(
                  '또 볼래',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: labelColor,
                  ),
                ),
              ),
      ],
    );

    return Semantics(
      button: true,
      toggled: value,
      label: '또 볼래',
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(compact ? 999 : 14),
        // compact는 시각 배지가 30px로 작아 권장 최소 터치 영역(44px)에
        // 못 미친다 — 보이는 크기는 그대로 두고 탭 영역만 투명하게 넓힌다.
        child: compact
            ? ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                child: Center(child: row),
              )
            : Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: row,
              ),
      ),
    );
  }
}
