import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

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
                child: RecordDialogActionCard(
                  icon: PhosphorIconsRegular.downloadSimple,
                  label: '불러오기',
                  onTap: () => Navigator.of(context).pop(IsbnLinkAction.reload),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: RecordDialogActionCard(
                  icon: PhosphorIconsRegular.arrowsClockwise,
                  label: '변경',
                  onTap: () => Navigator.of(context).pop(IsbnLinkAction.change),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: RecordDialogActionCard(
                  icon: PhosphorIconsRegular.linkBreak,
                  label: '연결 끊기',
                  destructive: true,
                  onTap: () => Navigator.of(context).pop(IsbnLinkAction.unlink),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
