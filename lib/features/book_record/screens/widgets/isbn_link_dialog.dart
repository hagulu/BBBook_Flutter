import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/record_dialog_shell.dart';

/// ISBN 터치 시 뜨는 액션 시트의 선택 결과.
enum IsbnLinkAction { reload, change, unlink }

/// "책 정보 수정" 하단 ISBN 항목을 터치하면 뜨는 액션 시트. 연결된 책에서만
/// 부른다 — 연결 안 된 책은 고를 액션이 검색(연결) 하나뿐이라 이 시트를
/// 거치지 않고 바로 검색으로 들어간다(book_info_edit_dialog.dart 참고).
Future<IsbnLinkAction?> showIsbnLinkActionSheet(BuildContext context) {
  return showModalBottomSheet<IsbnLinkAction>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => RecordDialogShell(
      title: 'ISBN',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: _IsbnActionCard(
                  icon: PhosphorIconsRegular.downloadSimple,
                  label: '불러오기',
                  onTap: () =>
                      Navigator.of(context).pop(IsbnLinkAction.reload),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _IsbnActionCard(
                  icon: PhosphorIconsRegular.arrowsClockwise,
                  label: '변경',
                  onTap: () =>
                      Navigator.of(context).pop(IsbnLinkAction.change),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _IsbnActionCard(
                  icon: PhosphorIconsRegular.linkBreak,
                  label: '연결 끊기',
                  destructive: true,
                  onTap: () =>
                      Navigator.of(context).pop(IsbnLinkAction.unlink),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// ISBN 액션 시트의 가로 네모 카드 버튼(book_search_screen.dart의
/// "직접 등록"/"바코드로 등록" 진입 버튼과 동일한 시각 언어).
class _IsbnActionCard extends StatelessWidget {
  const _IsbnActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.error : AppColors.accentForeground;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: color.withValues(alpha: 0.14),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: destructive ? color : AppColors.textStrong,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
