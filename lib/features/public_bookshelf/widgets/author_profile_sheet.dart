import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../shared/widgets/community_content.dart';
import '../../../shared/widgets/record_dialog_shell.dart';
import '../screens/public_finished_bookshelf_screen.dart';

/// 커뮤니티 콘텐츠(독후감·토론·독자평)의 작성자 프로필 영역 탭 핸들러.
///
/// 웹의 `UserMenu`와 동일하게, 완독 책장이 공개된 작성자만 탭 가능하게
/// 한다 — 비공개면 null을 반환해 [CommunityAuthorRow]가 평범한 텍스트로
/// 남는다(신호 없는 클릭 영역을 만들지 않기 위함).
VoidCallback? authorProfileSheetHandler(
  BuildContext context, {
  required int userId,
  required String? nickname,
  required bool isFinishedBooksPublic,
}) {
  if (!isFinishedBooksPublic) return null;
  return () => _openAuthorProfileSheet(
    context,
    userId: userId,
    nickname: nickname,
  );
}

Future<void> _openAuthorProfileSheet(
  BuildContext context, {
  required int userId,
  required String? nickname,
}) async {
  final normalizedNickname = nickname?.trim();
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => RecordDialogShell(
      title: normalizedNickname?.isNotEmpty == true
          ? normalizedNickname!
          : '프로필',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CommunityMenuTile(
            icon: PhosphorIconsRegular.bookOpen,
            label: '완독 책장 보러가기',
            onTap: () => Navigator.pop(sheetContext, true),
          ),
        ],
      ),
    ),
  );
  if (confirmed != true || !context.mounted) return;
  Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => PublicFinishedBookshelfScreen(
        userId: userId,
        nickname: normalizedNickname,
      ),
    ),
  );
}
