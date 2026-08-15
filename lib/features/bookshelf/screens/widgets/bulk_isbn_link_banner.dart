import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../book_record/screens/widgets/book_info_edit_dialog.dart';
import '../../../book_record/screens/widgets/isbn_link_search_sheet.dart';
import '../../models/book_item.dart';
import '../../providers/bookshelf_providers.dart';

/// 완독 목록 상단에 붙는 "ISBN 미연결 N권" 배너. 연결 안 된 책이 없으면
/// 아무것도 그리지 않는다(`SizedBox.shrink`).
///
/// 탭하면 미연결 책을 하나씩 순서대로 연다. 매번 먼저 검색 바텀시트만
/// 뜬다(그 아래 "책 정보 수정" 시트가 미리 깔려 대기하고 있지 않다) —
/// 결과를 고른 뒤에야 그 정보로 "책 정보 수정" 시트를 열어 검토·저장하게
/// 한다. "즉시 저장"이 켜져 있으면 검색 시트가 연결 PATCH 응답까지 직접
/// 기다린 뒤(책 정보 수정 시트는 열지 않고) 다음 책으로 넘어간다. 검색을
/// 취소하거나 "건너뛰기"를 누르면 그 책만 넘어가고, "중단"을 누르면 남은
/// 책은 더 열지 않고 전체 흐름을 멈춘다.
class UnlinkedFinishedBanner extends ConsumerWidget {
  const UnlinkedFinishedBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unlinked = ref.watch(unlinkedFinishedBooksProvider).valueOrNull;
    if (unlinked == null || unlinked.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: AppColors.accentLight.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _startBulkIsbnLink(context, unlinked),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const Icon(
                  PhosphorIconsRegular.link,
                  size: 18,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'ISBN 미연결 ${unlinked.length}권 있어요',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.titleText,
                    ),
                  ),
                ),
                const Text(
                  '연결하기',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(
                  PhosphorIconsRegular.caretRight,
                  size: 14,
                  color: AppColors.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 탭한 시점의 스냅샷([books])을 그대로 순서대로 돈다. 진행 도중 다른
  /// 경로로 목록이 바뀌어도(예: 동기화) 이 순회 자체는 흔들리지 않는다 —
  /// 각 책은 자기 userBookId로 최신 로컬 데이터를 다시 조회하는
  /// [BookInfoEditDialog]가 아니라 스냅샷의 [BookItem]을 그대로 초기값으로
  /// 쓰므로, 아주 드물게 그 사이 값이 바뀌었으면 시트에 약간 오래된 값이
  /// 보일 수 있다 — 사용자가 직접 여는 편집과 동일한 수준의 위험이라 별도
  /// 처리하지 않는다.
  Future<void> _startBulkIsbnLink(
    BuildContext context,
    List<BookItem> books,
  ) async {
    var stopped = false;
    // 검색 시트의 "즉시 저장" 토글 상태. 책마다 새로 만들지 않고 이 흐름
    // 전체에서 하나를 공유해, 한 번 켜면 다음 책에도 그대로 유지된다.
    final immediateSave = ValueNotifier<bool>(false);
    try {
      for (var i = 0; i < books.length; i++) {
        if (!context.mounted || stopped) break;
        final book = books[i];
        final query = [
          book.title,
          if (book.publisher != null && book.publisher!.isNotEmpty)
            book.publisher!,
        ].join(' ');
        final result = await showIsbnLinkSearchSheet(
          context,
          initialQuery: query,
          bulkProgress: (index: i + 1, total: books.length),
          userBookId: book.userBookId,
          immediateSave: immediateSave,
        );
        if (!context.mounted) break;
        // null(취소)/건너뛰기/즉시 저장(검색 시트가 이미 응답까지 기다려
        // 처리를 끝냄) 모두 이 책에 대해 더 할 일이 없다 — 바로 다음 책으로.
        if (result == null ||
            result.action == IsbnSearchAction.skip ||
            result.action == IsbnSearchAction.savedDirectly) {
          continue;
        }
        if (result.action == IsbnSearchAction.stop) {
          stopped = true;
          continue;
        }
        await showBookInfoEditDialog(
          context,
          userBookId: book.userBookId,
          book: book,
          initialIsbnToFill: result.isbn,
          bulkProgress: (index: i + 1, total: books.length),
          onBulkStop: () => stopped = true,
        );
      }
    } finally {
      immediateSave.dispose();
    }
    if (context.mounted) {
      AppSnackBar.info(
        context,
        stopped ? 'ISBN 연결을 중단했습니다.' : 'ISBN 연결 작업을 마쳤습니다.',
      );
    }
  }
}
