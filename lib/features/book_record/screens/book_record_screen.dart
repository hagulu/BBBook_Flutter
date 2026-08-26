import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/patch_field.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/author_display.dart';
import '../../../shared/widgets/app_confirm.dart';
import '../../../shared/widgets/app_loading.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../book_note/screens/book_note_list.dart';
import '../../book_reflection/screens/book_reflection_list.dart';
import '../../bookshelf/models/book_item.dart';
import '../../bookshelf/models/book_status.dart';
import '../../bookshelf/models/record_patch.dart';
import '../../bookshelf/providers/bookshelf_providers.dart';
import '../../bookshelf/screens/widgets/book_cover.dart';
import '../models/record_labels.dart';
import '../providers/book_record_providers.dart';
import 'widgets/book_info_edit_dialog.dart';
import 'widgets/finish_confirm_dialog.dart';
import 'widgets/meta_dialogs.dart';
import 'widgets/meta_summary_card.dart';
import 'widgets/progress_card.dart';
import 'widgets/rating_review_card.dart';
import 'widgets/reading_status_tile.dart';
import 'widgets/record_field_tile.dart';
import 'widgets/record_section_card.dart';
import 'widgets/reread_dialog.dart';
import 'widgets/tag_section.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// 책 기록 상세 화면(`/records/[userBookId]` 대응). 자체 AppBar만 갖고
/// 공통 하단 탭은 쓰지 않는다(book-record.md — 별도 `Navigator.push`로 진입).
/// 조회는 로컬 DB(bookRecordControllerProvider)만 사용한다. 기본 기록 필드
/// 수정(updateRecord)은 로컬 우선이라 로딩·에러 UI 없이 즉시 반영된 결과를
/// 보여주고, 서재 삭제는 서버 응답을 기다려 로딩·에러를 그대로 노출한다.
class BookRecordScreen extends ConsumerWidget {
  const BookRecordScreen({super.key, required this.userBookId});

  final int userBookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(bookRecordControllerProvider(userBookId));

    Widget body;
    if (state.hasValue) {
      final book = state.value;
      body = AppLoadingOverlay(
        isLoading: state.isLoading,
        child: book == null
            ? const _NotFoundBody()
            : _BookRecordBody(userBookId: userBookId, book: book),
      );
    } else if (state.hasError) {
      body = _ErrorBody(
        onRetry: () => ref.invalidate(bookRecordControllerProvider(userBookId)),
      );
    } else {
      body = const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('책 기록'),
        backgroundColor: AppColors.pageBackground,
        foregroundColor: AppColors.textStrong,
        elevation: 0,
      ),
      body: body,
    );
  }
}

class _NotFoundBody extends StatelessWidget {
  const _NotFoundBody();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        '책을 찾을 수 없습니다.',
        style: TextStyle(color: AppColors.textMuted),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '불러오지 못했습니다.',
            style: TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    );
  }
}

class _BookRecordBody extends ConsumerWidget {
  const _BookRecordBody({required this.userBookId, required this.book});

  final int userBookId;
  final BookItem book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(
      bookRecordControllerProvider(userBookId).notifier,
    );

    return DefaultTabController(
      length: 3,
      child: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverPersistentHeader(
            pinned: true,
            delegate: _CollapsingBookHeaderDelegate(
              book: book,
              onEditBookInfo: () => showBookInfoEditDialog(
                context,
                userBookId: userBookId,
                book: book,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: ColoredBox(
              color: AppColors.pageBackground,
              child: TabBar(
                tabs: const [
                  Tab(text: '정보'),
                  Tab(text: '노트'),
                  Tab(text: '독후감'),
                ],
                labelColor: AppColors.textStrong,
                unselectedLabelColor: AppColors.textMuted,
                indicatorColor: AppColors.accentForeground,
                dividerColor: AppColors.border,
              ),
            ),
          ),
        ],
        body: TabBarView(
          children: [
            ListView(
              key: const PageStorageKey('book-record-info'),
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
              children: [
                if (book.status == BookStatus.reading ||
                    book.status == BookStatus.paused) ...[
                  ProgressCard(userBookId: userBookId, book: book),
                  const SizedBox(height: 12),
                ],
                RecordSectionCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: ReadingStatusTile(
                          status: book.status,
                          summary: _statusSummary(book),
                          onTap: () =>
                              _openReadingStatusDialog(context, controller),
                        ),
                      ),
                      InkWell(
                        onTap: () => _toggleMasterpiece(context, controller),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                '명작',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textStrong,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Icon(
                                book.isMasterpiece
                                    ? PhosphorIconsFill.crown
                                    : PhosphorIconsRegular.crown,
                                size: 28,
                                color: book.isMasterpiece
                                    ? AppColors.highlightGold
                                    : AppColors.textMuted,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                MetaSummaryCard(
                  startedAt: book.startedAt,
                  onTapStartedAt: () => _pickDate(
                    context,
                    controller,
                    current: book.startedAt,
                    isStartedAt: true,
                  ),
                  finishedAt: book.finishedAt,
                  onTapFinishedAt: () => _pickDate(
                    context,
                    controller,
                    current: book.finishedAt,
                    isStartedAt: false,
                  ),
                  sourceValue: _sourceSummary(book),
                  sourceHasValue:
                      BookSourceType.fromApiValue(book.sourceType) != null,
                  onTapSource: () =>
                      _openSourceDialog(context, ref, controller),
                  sourceIcon: BookSourceType.fromApiValue(
                    book.sourceType,
                  )?.icon,
                  difficultyValue:
                      DifficultyLevel.fromApiValue(book.difficulty)?.label ??
                      DifficultyLevel.values.map((d) => d.label).join(' · '),
                  difficultyHasValue:
                      DifficultyLevel.fromApiValue(book.difficulty) != null,
                  onTapDifficulty: () =>
                      _openDifficultyDialog(context, controller),
                  difficultyIcon: DifficultyLevel.fromApiValue(
                    book.difficulty,
                  )?.icon,
                ),
                const SizedBox(height: 12),
                RatingReviewCard(userBookId: userBookId, book: book),
                const SizedBox(height: 12),
                RecordSectionCard(
                  child: RecordFieldTile(
                    label: '알게 된 경로',
                    value: book.discoverySource ?? '미설정',
                    hasValue: book.discoverySource != null,
                    onTap: () =>
                        _openDiscoverySourceDialog(context, controller),
                  ),
                ),
                const SizedBox(height: 12),
                RecordSectionCard(
                  child: TagSection(userBookId: userBookId, tags: book.tags),
                ),
                const SizedBox(height: 20),
                Center(
                  child: InkWell(
                    onTap: () => _confirmDelete(context, ref),
                    borderRadius: BorderRadius.circular(8),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 12,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            PhosphorIconsRegular.trash,
                            size: 16,
                            color: AppColors.textMuted,
                          ),
                          SizedBox(width: 6),
                          Text(
                            '서재에서 삭제',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            BookNoteList(userBookId: userBookId, bookTitle: book.title),
            BookReflectionList(userBookId: userBookId, bookTitle: book.title),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await AppConfirm.show(
      context,
      title: '책 삭제',
      message: '이 책을 서재에서 삭제할까요? 삭제하면 되돌릴 수 없습니다.',
      confirmText: '삭제',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;

    AppLoading.show(context);
    try {
      await ref
          .read(bookRecordControllerProvider(userBookId).notifier)
          .deleteBook();
      if (context.mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (context.mounted) {
        AppSnackBar.error(context, e.message);
      }
    } finally {
      AppLoading.hide();
    }
  }

  String _statusSummary(BookItem book) {
    if (book.status == BookStatus.finished && book.rereadCount >= 2) {
      return '${book.status.label} · ${book.rereadCount}회';
    }
    return book.status.label;
  }

  String _sourceSummary(BookItem book) {
    final source = BookSourceType.fromApiValue(book.sourceType);
    if (source == null) {
      return BookSourceType.values.map((s) => s.label).join(' · ');
    }
    if (book.platformName == null || book.platformName!.isEmpty) {
      return source.label;
    }
    return '${source.label} · ${book.platformName}';
  }

  Future<void> _openReadingStatusDialog(
    BuildContext context,
    BookRecordController controller,
  ) async {
    final status = await showReadingStatusDialog(
      context,
      initialStatus: book.status,
    );
    if (status == null || !context.mounted) return;
    await _onStatusTap(context, controller, status);
  }

  Future<void> _toggleMasterpiece(
    BuildContext context,
    BookRecordController controller,
  ) {
    return controller.updateRecord(
      RecordPatch(isMasterpiece: !book.isMasterpiece),
    );
  }

  Future<void> _onStatusTap(
    BuildContext context,
    BookRecordController controller,
    BookStatus tapped,
  ) async {
    if (tapped == BookStatus.finished) {
      // finishedAt이 있으면 과거에 한 번 이상 완독한 책이다(현재 상태가
      // 완독이 아니어도 마찬가지) — 바로 완독 처리하지 않고 완독 횟수
      // 조정 팝업을 띄운다.
      if (book.finishedAt != null) {
        final result = await showRereadDialog(
          context,
          initialCount: book.rereadCount + 1,
        );
        if (result == null) return;
        switch (result) {
          case RereadCountUpdated(:final count):
            await controller.updateRecord(
              RecordPatch(
                // 이미 완독 상태면 status를 다시 보내지 않는다 — status가
                // FINISHED인데 finishedAt을 안 보내면 서버가 완독일을 오늘
                // 날짜로 새로 설정해버려(api-doc), 횟수만 고치려던 사용자의
                // 완독일이 의도치 않게 바뀐다. 완독이 아닌 상태(읽는 중 등)
                // 에서 재독을 완료하는 경우에만 상태를 FINISHED로 바꿔
                // 완독일이 오늘로 새로 기록되게 한다.
                status: book.status == BookStatus.finished
                    ? null
                    : tapped.apiValue,
                rereadCount: count,
                // totalPages를 아는 책은 마지막 쪽으로 진행률을 맞춘다(실제
                // 웹 클라이언트와 동일 — 완독인데 진행률이 중간에 멈춰 있는
                // 모순 방지). 재독 팝업은 완독 상태가 아닌 책에서도 열릴 수
                // 있어 이 값이 항상 이미 반영돼 있지는 않다.
                currentPage: book.totalPages,
              ),
            );
          case RereadFinishCancelled():
            // 실제 웹 클라이언트(BookRecordPage.tsx)도 완독 취소 시 재독
            // 횟수를 0으로 되돌린다 — 다음에 다시 완독 처리하면 재독
            // 횟수가 이전 값에서 이어지지 않고 새로 시작해야 자연스럽다.
            await controller.updateRecord(
              RecordPatch(status: BookStatus.reading.apiValue, rereadCount: 0),
            );
        }
        return;
      }

      final result = await showFinishConfirmDialog(context);
      if (result == null) return;
      await controller.updateRecord(
        RecordPatch(
          status: tapped.apiValue,
          // totalPages를 아는 책은 마지막 쪽으로 진행률을 맞춘다(실제 웹
          // 클라이언트와 동일 — 완독인데 진행률이 중간에 멈춰 있는 모순 방지).
          currentPage: book.totalPages,
          // 완독 팝업에서 입력하지 않은 항목은 아예 보내지 않는다(기존 값
          // 유지) — 빈 값을 지움 신호로 쓰지 않는다.
          difficulty: patchIfPresent(result.difficulty),
          myRating: patchIfPresent(result.myRating),
          shortReview: patchIfPresent(result.shortReview),
        ),
      );
      return;
    }

    if (tapped == book.status) return;

    await controller.updateRecord(RecordPatch(status: tapped.apiValue));
  }

  Future<void> _openSourceDialog(
    BuildContext context,
    WidgetRef ref,
    BookRecordController controller,
  ) async {
    Map<String, List<String>> options;
    try {
      options = await ref.read(platformOptionsProvider.future);
    } catch (_) {
      options = const {};
    }
    if (!context.mounted) return;

    final result = await showSourcePlatformDialog(
      context,
      initialSource: BookSourceType.fromApiValue(book.sourceType),
      initialPlatform: book.platformName,
      platformOptions: options,
    );
    if (result == null) return;

    await controller.updateRecord(
      RecordPatch(
        sourceType: PatchField.value(result.sourceType.apiValue),
        platformName: result.platformName,
      ),
    );
  }

  Future<void> _openDifficultyDialog(
    BuildContext context,
    BookRecordController controller,
  ) async {
    final value = await showDifficultyDialog(
      context,
      initialDifficulty: book.difficulty,
    );
    if (value == null) return;
    await controller.updateRecord(
      RecordPatch(difficulty: PatchField.value(value)),
    );
  }

  Future<void> _pickDate(
    BuildContext context,
    BookRecordController controller, {
    required DateTime? current,
    required bool isStartedAt,
  }) async {
    final now = DateTime.now();
    final result = await showReadingDateDialog(
      context,
      initialDate: current,
      lastDate: now,
      isStartedAt: isStartedAt,
      // 완독 상태에서는 완독일을 지울 수 없다 — 서버가 삭제를 무시하고 기존
      // 값(없으면 오늘)을 유지한다(api-doc). 날짜를 없애려면 상태를 먼저
      // 바꿔야 한다.
      canClear:
          isStartedAt || book.status != BookStatus.finished,
    );
    if (result == null) return;
    // "선택 해제"는 명시적 null(삭제), 날짜 선택은 그 값으로 수정이다.
    // 고르지 않은 쪽(시작일/완독일 중 다른 하나)은 아예 담지 않아 요청에서
    // 빠진다(기존 값 유지).
    final picked = result.cleared
        ? const PatchField<String>.clear()
        : PatchField.value(_formatApiDate(result.date!));
    await controller.updateRecord(
      RecordPatch(
        startedAt: isStartedAt ? picked : null,
        finishedAt: isStartedAt ? null : picked,
      ),
    );
  }

  String _formatApiDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<void> _openDiscoverySourceDialog(
    BuildContext context,
    BookRecordController controller,
  ) async {
    final value = await showDiscoverySourceDialog(
      context,
      initialValue: book.discoverySource,
    );
    if (value == null) return;
    await controller.updateRecord(
      RecordPatch(
        // 입력을 비운 채 저장했으면 "지움"(명시적 null)이다 — 빈 문자열은
        // 서버가 삭제가 아니라 값으로 저장하므로 그대로 보내면 안 된다.
        discoverySource: value.isEmpty
            ? const PatchField.clear()
            : PatchField.value(value),
      ),
    );
  }
}

/// 스크롤에 따라 책 정보 카드가 점점 작아지며 상단에 썸네일+제목만 남는
/// 컴팩트 바로 자연스럽게 전환되는 헤더. `shrinkOffset`이 곧 스크롤 진행도라
/// 별도 AnimationController 없이 opacity/scale을 직접 보간한다.
class _CollapsingBookHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _CollapsingBookHeaderDelegate({
    required this.book,
    required this.onEditBookInfo,
  });

  final BookItem book;
  final VoidCallback onEditBookInfo;

  static const double _expandedHeight = 178;
  static const double _collapsedHeight = 56;

  @override
  double get minExtent => _collapsedHeight;

  @override
  double get maxExtent => _expandedHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    const range = _expandedHeight - _collapsedHeight;
    final progress = (shrinkOffset / range).clamp(0.0, 1.0);
    final expandedOpacity = 1 - Curves.easeOut.transform(progress);
    final compactOpacity = Curves.easeIn.transform(progress);

    return ClipRect(
      child: ColoredBox(
        color: AppColors.pageBackground,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (expandedOpacity > 0)
              Opacity(
                opacity: expandedOpacity,
                child: Transform.scale(
                  alignment: Alignment.topCenter,
                  scale: 1 - progress * 0.1,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: _Header(
                      book: book,
                      onEditBookInfo: onEditBookInfo,
                    ),
                  ),
                ),
              ),
            if (compactOpacity > 0)
              Align(
                alignment: Alignment.topCenter,
                child: Opacity(
                  opacity: compactOpacity,
                  child: SizedBox(
                    height: _collapsedHeight,
                    child: _CompactHeaderRow(book: book),
                  ),
                ),
              ),
            if (overlapsContent && compactOpacity > 0)
              const Align(
                alignment: Alignment.bottomCenter,
                child: Divider(height: 1, thickness: 1, color: AppColors.border),
              ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _CollapsingBookHeaderDelegate oldDelegate) =>
      // BookItem은 값 동등성(==)을 오버라이드하지 않고 상태 갱신마다
      // copyWith로 새 인스턴스가 나오므로, 참조 비교만으로 표시 필드는 물론
      // onEditBookInfo 콜백(캡처된 book)까지 항상 최신 상태로 갱신된다.
      // 필드를 나열해 비교하면 displayCategoryId 같은 항목이 누락되기 쉽다.
      oldDelegate.book != book;
}

/// 컴팩트 헤더에 표시되는 썸네일+제목 한 줄.
class _CompactHeaderRow extends StatelessWidget {
  const _CompactHeaderRow({required this.book});

  final BookItem book;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: BookCover(imageUrl: book.coverImageUrl, title: book.title),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              book.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: AppColors.textStrong,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.book, required this.onEditBookInfo});

  final BookItem book;
  final VoidCallback onEditBookInfo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 색을 맞출 카테고리가 애초에 없는 책이면 카테고리 목록 provider를
    // 구독하지 않는다(불필요한 리빌드/조회 방지).
    Color? categoryColor;
    if (book.displayCategoryId != null) {
      final categories = ref.watch(bookCategoriesProvider).valueOrNull;
      if (categories != null) {
        for (final category in categories) {
          if (category.id == book.displayCategoryId) {
            categoryColor = category.color;
            break;
          }
        }
      }
    }

    return RecordSectionCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onEditBookInfo,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 84,
                child: BookCover(
                  imageUrl: book.coverImageUrl,
                  title: book.title,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (book.category != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: (categoryColor ?? AppColors.controlInactive)
                              .withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          book.category!,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textBody,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                        color: AppColors.textStrong,
                      ),
                    ),
                    if (book.author != null && book.author!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        displayAuthor(book.author!),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                    if (book.publisher != null &&
                        book.publisher!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        book.publisher!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
