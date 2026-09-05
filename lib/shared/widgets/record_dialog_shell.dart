import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

enum RecordDialogButtonStyle { neutral, primary, destructive }

/// 앱 바텀시트가 공유하는 크기·간격 규격.
///
/// 기능별 시트가 고유한 높이와 콘텐츠 배치를 유지하더라도 바깥 표면과
/// 헤더의 시각 리듬은 이 값을 사용한다.
abstract final class RecordDialogMetrics {
  static const cornerRadius = 24.0;
  static const horizontalPadding = 24.0;
  static const topPadding = 12.0;
  static const bottomPadding = 24.0;
  static const handleWidth = 36.0;
  static const handleHeight = 4.0;
  static const handleToHeader = 16.0;
  static const headerToContent = 18.0;
  static const contentToButtons = 20.0;
  static const itemSpacing = 8.0;
  static const buttonSpacing = 12.0;
  static const controlRadius = 14.0;
  static const buttonHeight = 48.0;
}

class RecordDialogButton {
  const RecordDialogButton({
    required this.label,
    required this.onPressed,
    this.style = RecordDialogButtonStyle.primary,
  });

  final String label;
  final VoidCallback? onPressed;
  final RecordDialogButtonStyle style;
}

/// 모든 바텀시트가 공유하는 흰 표면, 상단 모서리, 키보드·홈 인디케이터
/// 여백. 검색형·빠른 입력형처럼 [RecordDialogShell]의 콘텐츠 구조가 맞지
/// 않는 시트도 이 표면은 재사용한다.
class RecordDialogSurface extends StatelessWidget {
  const RecordDialogSurface({
    super.key,
    required this.child,
    this.height,
    this.horizontalPadding = RecordDialogMetrics.horizontalPadding,
    this.topPadding = RecordDialogMetrics.topPadding,
    this.bottomPadding = RecordDialogMetrics.bottomPadding,
  });

  final Widget child;
  final double? height;
  final double horizontalPadding;
  final double topPadding;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        height: height,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(RecordDialogMetrics.cornerRadius),
          ),
        ),
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          topPadding,
          horizontalPadding,
          0,
        ),
        // 키보드 인셋만 따로 애니메이션 없는 Padding으로 뺀다 — 이
        // AnimatedContainer의 180ms 트랜지션과 키보드가 올라오는 시스템
        // 애니메이션 길이가 서로 달라, 같이 애니메이션시키면 키보드와 시트
        // 사이에 순간적으로 공백이 보인다. 매 프레임 그대로 따라가는 일반
        // Padding을 쓰면 키보드 움직임과 항상 정확히 맞아떨어진다.
        child: Padding(
          padding: EdgeInsets.only(
            bottom:
                bottomPadding +
                MediaQuery.viewInsetsOf(context).bottom +
                MediaQuery.viewPaddingOf(context).bottom,
          ),
          child: child,
        ),
      ),
    );
  }
}

class RecordDialogHandle extends StatelessWidget {
  const RecordDialogHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: RecordDialogMetrics.handleWidth,
        height: RecordDialogMetrics.handleHeight,
        decoration: BoxDecoration(
          color: AppColors.border,
          borderRadius: BorderRadius.circular(
            RecordDialogMetrics.handleHeight / 2,
          ),
        ),
      ),
    );
  }
}

class RecordDialogHeader extends StatelessWidget {
  const RecordDialogHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textStrong,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// 여러 기능의 선택·수정 폼이 공유하는 바텀시트 뼈대. 커스텀 콘텐츠가
/// 필요한 폼에도 필 버튼 시각 언어를 동일하게 적용한다.
/// `showModalBottomSheet`의 `builder`에서 반환해 사용한다(선택/수정 항목은
/// 바텀시트로, 단순 알림/확인은 `AppAlert`/`AppConfirm`을 그대로 쓴다).
class RecordDialogShell extends StatelessWidget {
  const RecordDialogShell({
    super.key,
    required this.title,
    required this.content,
    this.buttons = const [],
    this.titleTrailing,
    this.scrollController,
  });

  final String title;
  final Widget content;
  final List<RecordDialogButton> buttons;

  /// 제목 오른쪽에 붙는 보조 액션(예: 항목 추가 "+" 버튼). 지정하지 않으면
  /// 제목만 표시한다.
  final Widget? titleTrailing;

  /// 콘텐츠를 감싸는 내부 스크롤을 호출부가 직접 제어해야 할 때(예: 특정
  /// 입력 필드에 포커스가 가면 맨 아래로 스크롤)만 넘긴다. 지정하지 않으면
  /// 이 위젯이 자체 컨트롤러를 쓴다.
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    // 흰 배경 컨테이너가 화면 맨 아래까지 이어지도록 SafeArea로 감싸 크기를
    // 줄이는 대신, 하단 세이프 에어리어(홈 인디케이터 등)만큼을 컨테이너
    // 내부 패딩에 더한다 — 그렇지 않으면 그 틈으로 투명한 모달 배리어가
    // 노출된다.
    return RecordDialogSurface(
      child: SingleChildScrollView(
        controller: scrollController,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const RecordDialogHandle(),
            const SizedBox(height: RecordDialogMetrics.handleToHeader),
            RecordDialogHeader(title: title, trailing: titleTrailing),
            const SizedBox(height: RecordDialogMetrics.headerToContent),
            content,
            if (buttons.isNotEmpty) ...[
              const SizedBox(height: RecordDialogMetrics.contentToButtons),
              Row(
                children: [
                  for (var i = 0; i < buttons.length; i++) ...[
                    if (i > 0)
                      const SizedBox(width: RecordDialogMetrics.buttonSpacing),
                    Expanded(child: _Button(buttons[i])),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button(this.button);

  final RecordDialogButton button;

  @override
  Widget build(BuildContext context) {
    final Color background;
    final Color foreground;
    switch (button.style) {
      case RecordDialogButtonStyle.primary:
        background = AppColors.accentFill;
        foreground = AppColors.textStrong;
      case RecordDialogButtonStyle.neutral:
        background = AppColors.surfaceSubtle;
        foreground = AppColors.textBody;
      case RecordDialogButtonStyle.destructive:
        background = AppColors.error;
        foreground = Colors.white;
    }
    return ElevatedButton(
      onPressed: button.onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        disabledBackgroundColor: background.withValues(alpha: 0.4),
        elevation: 0,
        minimumSize: const Size.fromHeight(RecordDialogMetrics.buttonHeight),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            RecordDialogMetrics.controlRadius,
          ),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),
      child: Text(button.label),
    );
  }
}

/// 복사·수정·삭제처럼 세로로 나열하는 작업 메뉴 항목.
class RecordDialogActionTile extends StatelessWidget {
  const RecordDialogActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.error : AppColors.textStrong;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(RecordDialogMetrics.controlRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(RecordDialogMetrics.controlRadius),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            child: Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 제한된 가로 공간에 여러 작업이나 선택지를 나란히 보여주는 카드.
/// [selected]는 크기 선택처럼 현재 값을 나타낼 때만 사용하고, 위험 작업은
/// [destructive]로 동일한 오류 색상 규칙을 적용한다.
class RecordDialogActionCard extends StatelessWidget {
  const RecordDialogActionCard({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.description,
    this.selected = false,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final String? description;
  final bool selected;
  final bool destructive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final emphasisColor = destructive
        ? AppColors.error
        : AppColors.accentForeground;
    final labelColor = destructive
        ? AppColors.error
        : selected
        ? AppColors.accentForeground
        : AppColors.textStrong;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected
            ? AppColors.accentSurface.withValues(alpha: 0.35)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(RecordDialogMetrics.controlRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(
            RecordDialogMetrics.controlRadius,
          ),
          child: Container(
            constraints: const BoxConstraints(minHeight: 88),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(
                RecordDialogMetrics.controlRadius,
              ),
              border: Border.all(
                color: selected ? AppColors.accentForeground : AppColors.border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: emphasisColor, size: 22),
                const SizedBox(height: 10),
                Text(
                  label,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: labelColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (description != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    description!,
                    maxLines: 1,
                    style: TextStyle(
                      color: selected
                          ? AppColors.accentForeground
                          : AppColors.textMuted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 바텀시트 안에서 즉시 상태를 바꾸는 공개 여부 등의 토글 항목.
class RecordDialogToggleTile extends StatelessWidget {
  const RecordDialogToggleTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(RecordDialogMetrics.controlRadius),
      child: SwitchListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            RecordDialogMetrics.controlRadius,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        secondary: Icon(icon, size: 20, color: AppColors.textStrong),
        title: Text(
          title,
          style: const TextStyle(
            color: AppColors.textStrong,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
        value: value,
        activeThumbColor: AppColors.surface,
        activeTrackColor: AppColors.accentForeground,
        inactiveThumbColor: AppColors.surface,
        inactiveTrackColor: AppColors.controlInactive,
        onChanged: onChanged,
      ),
    );
  }
}
