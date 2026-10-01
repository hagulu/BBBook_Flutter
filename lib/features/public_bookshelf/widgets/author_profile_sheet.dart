import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../shared/widgets/community_content.dart';
import '../../../shared/widgets/record_dialog_shell.dart';
import '../screens/public_finished_bookshelf_screen.dart';
import 'user_report_flow.dart';

/// 커뮤니티 콘텐츠(독후감·토론·독자평)의 작성자 프로필 영역 탭 핸들러.
///
/// 웹의 `UserMenu`와 동일하게, 완독 책장이 공개된 작성자만 탭 가능하게
/// 한다 — 비공개이면서 신고할 수도 없는(본인·비로그인) 작성자는 null을 반환해
/// [CommunityAuthorRow]가 평범한 텍스트로 남는다(신호 없는 클릭 영역을 만들지
/// 않기 위함). 본인이 아닌 로그인 사용자에게는 "신고" 항목이 함께 나온다.
VoidCallback? authorProfileSheetHandler(
  BuildContext context, {
  required int userId,
  required String? nickname,
  required bool isFinishedBooksPublic,
}) {
  final container = ProviderScope.containerOf(context, listen: false);
  final reportable = canReportUserNow(container, userId);
  if (!isFinishedBooksPublic && !reportable) return null;
  return () => _openAuthorProfileSheet(
    context,
    userId: userId,
    nickname: nickname,
    isFinishedBooksPublic: isFinishedBooksPublic,
    reportable: reportable,
  );
}

Future<void> _openAuthorProfileSheet(
  BuildContext context, {
  required int userId,
  required String? nickname,
  required bool isFinishedBooksPublic,
  required bool reportable,
}) async {
  final normalizedNickname = nickname?.trim();
  final action = await showModalBottomSheet<_ProfileAction>(
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
          if (isFinishedBooksPublic)
            CommunityMenuTile(
              icon: PhosphorIconsRegular.bookOpen,
              label: '완독 책장 보러가기',
              onTap: () => Navigator.pop(sheetContext, _ProfileAction.shelf),
            ),
          if (reportable)
            CommunityMenuTile(
              icon: PhosphorIconsRegular.siren,
              label: '신고',
              destructive: true,
              onTap: () => Navigator.pop(sheetContext, _ProfileAction.report),
            ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  if (action == _ProfileAction.report) {
    await reportUser(context, userId);
    return;
  }
  Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => PublicFinishedBookshelfScreen(
        userId: userId,
        nickname: normalizedNickname,
      ),
    ),
  );
}

enum _ProfileAction { shelf, report }
