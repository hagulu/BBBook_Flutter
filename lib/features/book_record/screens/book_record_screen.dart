import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_confirm.dart';
import '../../../shared/widgets/app_loading.dart';
import '../../bookshelf/models/book_item.dart';
import '../../bookshelf/models/book_status.dart';
import '../../bookshelf/screens/widgets/book_cover.dart';
import '../models/record_labels.dart';
import '../providers/book_record_providers.dart';
import 'widgets/book_info_edit_dialog.dart';
import 'widgets/finish_confirm_dialog.dart';
import 'widgets/meta_dialogs.dart';
import 'widgets/meta_summary_card.dart';
import 'widgets/progress_card.dart';
import 'widgets/rating_review_card.dart';
import 'widgets/reading_status_selector.dart';
import 'widgets/record_section_card.dart';
import 'widgets/reread_dialog.dart';
import 'widgets/tag_section.dart';

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
        actions: [
          if (state.valueOrNull != null)
            IconButton(
              tooltip: '서재에서 삭제',
              icon: const Icon(Icons.delete_outline),
              // 진행 중인 저장(PATCH)이 있으면 비활성화한다 — 그러지 않으면
              // 저장 응답이 늦게 도착했을 때 삭제된 로컬 행을 되살릴 수 있다.
              onPressed: state.isLoading
                  ? null
                  : () => _confirmDelete(context, ref),
            ),
        ],
      ),
      body: body,
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
            onToggleMasterpiece: () => _toggleMasterpiece(context, controller),
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
          const SectionLabel('독서 상태', icon: Icons.checklist_outlined),
          const SizedBox(height: 8),
          ReadingStatusSelector(
            selected: book.status,
            onSelected: (status) => _onStatusTap(context, controller, status),
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
            onTapSource: () => _openSourceDialog(context, ref, controller),
            difficultyValue:
                DifficultyLevel.fromApiValue(book.difficulty)?.label ??
                DifficultyLevel.values.map((d) => d.label).join(' · '),
            onTapDifficulty: () => _openDifficultyDialog(context, controller),
            discoverySourceValue: book.discoverySource ?? '미설정',
            onTapDiscoverySource: () =>
                _openDiscoverySourceDialog(context, controller),
          ),
          const SizedBox(height: 12),
          RatingReviewCard(userBookId: userBookId, book: book),
          const SizedBox(height: 12),
          RecordSectionCard(
            child: TagSection(userBookId: userBookId, tags: book.tags),
          ),
        ],
      ),
    );
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
      if (tapped == book.status) {
        if (tapped != BookStatus.finished) return;
        final result = await showRereadDialog(
          context,
          initialCount: book.rereadCount,
        );
        if (result == null) return;
        switch (result) {
          case RereadCountUpdated(:final count):
            await controller.updateRecord(rereadCount: count);
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

      if (tapped == BookStatus.finished) {
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

class _Header extends StatelessWidget {
  const _Header({
    required this.book,
    required this.onToggleMasterpiece,
    required this.onEditBookInfo,
  });

  final BookItem book;
  final VoidCallback onToggleMasterpiece;
  final VoidCallback onEditBookInfo;

  @override
  Widget build(BuildContext context) {
    return RecordSectionCard(
      padding: EdgeInsets.zero,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
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
                                color: AppColors.inputBackground,
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
                          if (book.author != null &&
                              book.author!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              book.author!,
                              style: const TextStyle(
                                fontSize: 12,
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
                          const SizedBox(height: 6),
                          const Row(
                            children: [
                              Icon(
                                Icons.edit_outlined,
                                size: 12,
                                color: AppColors.mutedIcon,
                              ),
                              SizedBox(width: 3),
                              Text(
                                '탭하여 책 정보 수정',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.mutedIcon,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 16, right: 12),
            child: IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: onToggleMasterpiece,
              icon: Icon(
                book.isMasterpiece
                    ? Icons.emoji_events
                    : Icons.emoji_events_outlined,
                color: book.isMasterpiece
                    ? AppColors.masterpieceGold
                    : AppColors.mutedIcon,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
