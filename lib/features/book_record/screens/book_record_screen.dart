import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_confirm.dart';
import '../../../shared/widgets/app_loading.dart';
import '../../bookshelf/models/book_item.dart';
import '../../bookshelf/models/book_status.dart';
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
/// 조회는 로컬 DB(bookRecordControllerProvider)만 사용하고, 수정은 서버 PATCH
/// 성공 후 로컬에 반영된 결과를 그대로 반영한다.
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
        foregroundColor: AppColors.titleText,
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
        style: TextStyle(color: AppColors.tertiaryText),
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
            style: TextStyle(color: AppColors.tertiaryText),
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

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            book: book,
            onEditBookInfo: () => showBookInfoEditDialog(
              context,
              userBookId: userBookId,
              book: book,
            ),
          ),
          if (book.status == BookStatus.reading ||
              book.status == BookStatus.paused) ...[
            const SizedBox(height: 12),
            ProgressCard(userBookId: userBookId, book: book),
          ],
          const SizedBox(height: 20),
          RecordSectionCard(
            child: Row(
              children: [
                Expanded(
                  child: ReadingStatusTile(
                    status: book.status,
                    summary: _statusSummary(book),
                    onTap: () => _openReadingStatusDialog(context, controller),
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
                        Text(
                          '명작',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: book.isMasterpiece
                                ? AppColors.masterpieceGold
                                : AppColors.mutedIcon,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Icon(
                          book.isMasterpiece
                              ? PhosphorIconsFill.crown
                              : PhosphorIconsRegular.crown,
                          size: 28,
                          color: book.isMasterpiece
                              ? AppColors.masterpieceGold
                              : AppColors.mutedIcon,
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
            onTapSource: () => _openSourceDialog(context, ref, controller),
            sourceIcon: BookSourceType.fromApiValue(book.sourceType)?.icon,
            difficultyValue:
                DifficultyLevel.fromApiValue(book.difficulty)?.label ??
                DifficultyLevel.values.map((d) => d.label).join(' · '),
            difficultyHasValue:
                DifficultyLevel.fromApiValue(book.difficulty) != null,
            onTapDifficulty: () => _openDifficultyDialog(context, controller),
            difficultyIcon: DifficultyLevel.fromApiValue(book.difficulty)?.icon,
          ),
          const SizedBox(height: 12),
          RatingReviewCard(userBookId: userBookId, book: book),
          const SizedBox(height: 12),
          RecordSectionCard(
            child: RecordFieldTile(
              label: '알게 된 경로',
              value: book.discoverySource ?? '미설정',
              hasValue: book.discoverySource != null,
              onTap: () => _openDiscoverySourceDialog(context, controller),
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
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 12,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(
                      PhosphorIconsRegular.trash,
                      size: 16,
                      color: AppColors.tertiaryText,
                    ),
                    SizedBox(width: 6),
                    Text(
                      '서재에서 삭제',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.tertiaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
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
  ) async {
    try {
      await controller.updateRecord(isMasterpiece: !book.isMasterpiece);
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _onStatusTap(
    BuildContext context,
    BookRecordController controller,
    BookStatus tapped,
  ) async {
    try {
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
                // 이미 완독 상태면 status를 다시 보내지 않는다 — status가
                // FINISHED인데 finishedAt을 안 보내면 서버가 완독일을 오늘
                // 날짜로 새로 설정해버려(api-doc), 횟수만 고치려던 사용자의
                // 완독일이 의도치 않게 바뀐다. 완독이 아닌 상태(읽는 중 등)에서
                // 재독을 완료하는 경우에만 상태를 FINISHED로 바꿔 완독일이
                // 오늘로 새로 기록되게 한다.
                status: book.status == BookStatus.finished
                    ? null
                    : tapped.apiValue,
                rereadCount: count,
                // totalPages를 아는 책은 마지막 쪽으로 진행률을 맞춘다(실제
                // 웹 클라이언트와 동일 — 완독인데 진행률이 중간에 멈춰 있는
                // 모순 방지). 재독 팝업은 완독 상태가 아닌 책에서도 열릴 수
                // 있어 이 값이 항상 이미 반영돼 있지는 않다.
                currentPage: book.totalPages,
              );
            case RereadFinishCancelled():
              // 실제 웹 클라이언트(BookRecordPage.tsx)도 완독 취소 시 재독
              // 횟수를 0으로 되돌린다 — 다음에 다시 완독 처리하면 재독
              // 횟수가 이전 값에서 이어지지 않고 새로 시작해야 자연스럽다.
              await controller.updateRecord(
                status: BookStatus.reading.apiValue,
                rereadCount: 0,
              );
          }
          return;
        }

        final result = await showFinishConfirmDialog(context);
        if (result == null) return;
        await controller.updateRecord(
          status: tapped.apiValue,
          // totalPages를 아는 책은 마지막 쪽으로 진행률을 맞춘다(실제 웹
          // 클라이언트와 동일 — 완독인데 진행률이 중간에 멈춰 있는 모순 방지).
          currentPage: book.totalPages,
          difficulty: result.difficulty,
          myRating: result.myRating,
          shortReview: result.shortReview,
        );
        return;
      }

      if (tapped == book.status) return;

      await controller.updateRecord(status: tapped.apiValue);
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
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

    try {
      await controller.updateRecord(
        sourceType: result.sourceType.apiValue,
        platformName: result.platformName,
      );
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
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
    try {
      await controller.updateRecord(difficulty: value);
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _pickDate(
    BuildContext context,
    BookRecordController controller, {
    required DateTime? current,
    required bool isStartedAt,
  }) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: isStartedAt ? '시작일 선택' : '완독일 선택',
    );
    if (picked == null) return;
    final formatted = _formatApiDate(picked);
    try {
      await controller.updateRecord(
        startedAt: isStartedAt ? formatted : null,
        finishedAt: isStartedAt ? null : formatted,
      );
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
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
    try {
      await controller.updateRecord(discoverySource: value);
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
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
                          color:
                              (categoryColor ?? AppColors.mutedIcon)
                                  .withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          book.category!,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.bodyText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      book.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                        color: AppColors.titleText,
                      ),
                    ),
                    if (book.author != null && book.author!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        book.author!,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.tertiaryText,
                        ),
                      ),
                    ],
                    if (book.publisher != null &&
                        book.publisher!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        book.publisher!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.tertiaryText,
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
