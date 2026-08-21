import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_notifier.dart';
import '../models/book_note.dart';
import '../providers/book_note_providers.dart';
import 'book_note_detail_screen.dart';
import 'widgets/book_note_refresh_indicator.dart';

/// 책 기록 상세의 노트 탭. [bookNoteListProvider]가 로컬 DB만 조회하고,
/// 상세 화면에서 돌아오면 로컬 목록을 다시 읽는다. 서버와의 동기화(dirty
/// push + 전체/증분 새로고침)는 당겨서 새로고침([BookNoteRefreshIndicator])
/// 또는 앱 저장/수정/삭제 직후의 백그라운드 push로만 일어난다.
class BookNoteList extends ConsumerWidget {
  const BookNoteList({
    super.key,
    required this.userBookId,
    required this.bookTitle,
  });

  final int userBookId;
  final String bookTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ownerUserId = ref.watch(
      authNotifierProvider.select((auth) => auth.user?.id),
    );
    final asyncNotes = ref.watch(bookNoteListProvider(userBookId));

    return BookNoteRefreshIndicator(
      child: CustomScrollView(
        key: const PageStorageKey('book-note-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '개인 노트',
                      style: TextStyle(
                        color: AppColors.textStrong,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: ownerUserId == null
                        ? null
                        : () =>
                              _openNote(context, ref, ownerUserId: ownerUserId),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    icon: const Icon(PhosphorIconsRegular.plus, size: 15),
                    label: const Text('노트 추가'),
                  ),
                ],
              ),
            ),
          ),
          switch (asyncNotes) {
            AsyncData(:final value) when value.isEmpty =>
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyNotes(),
              ),
            AsyncData(:final value) => SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: SliverList.separated(
                itemCount: value.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final summary = value[index];
                  return _NoteCard(
                    summary: summary,
                    // 목록은 최신순(updated_at DESC)이므로, 오래된 항목일수록
                    // 작은 번호가 붙도록 뒤에서부터 센다.
                    noteNumber: value.length - index,
                    onTap: ownerUserId == null
                        ? null
                        : () => _openNote(
                            context,
                            ref,
                            ownerUserId: ownerUserId,
                            noteId: summary.note.id,
                          ),
                  );
                },
              ),
            ),
            AsyncError() => SliverFillRemaining(
              hasScrollBody: false,
              child: _NoteLoadError(
                onRetry: () => ref.invalidate(bookNoteListProvider(userBookId)),
              ),
            ),
            _ => const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            ),
          },
        ],
      ),
    );
  }

  Future<void> _openNote(
    BuildContext context,
    WidgetRef ref, {
    required int ownerUserId,
    int? noteId,
  }) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => BookNoteDetailScreen(
          ownerUserId: ownerUserId,
          userBookId: userBookId,
          bookTitle: bookTitle,
          noteId: noteId,
        ),
      ),
    );
    ref.invalidate(bookNoteListProvider(userBookId));
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.summary,
    required this.noteNumber,
    required this.onTap,
  });

  final BookNoteSummary summary;
  final int noteNumber;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final title = summary.note.title?.trim();
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
            boxShadow: const [
              BoxShadow(
                color: AppColors.shadowSoft,
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title == null || title.isEmpty
                                ? '#$noteNumber'
                                : title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textStrong,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (summary.pageLabel != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            summary.pageLabel!,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      '${_formatDate(summary.note.updatedAt)} · '
                      '메모 ${summary.memoCount}개',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                PhosphorIconsRegular.caretRight,
                color: AppColors.controlInactive,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    return '${local.year}.${local.month}.${local.day}';
  }
}

class _EmptyNotes extends StatelessWidget {
  const _EmptyNotes();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.fromLTRB(32, 24, 32, 80),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIconsRegular.notePencil,
              size: 44,
              color: AppColors.controlInactive,
            ),
            SizedBox(height: 14),
            Text(
              '아직 노트가 없습니다.',
              style: TextStyle(
                color: AppColors.textStrong,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 6),
            Text(
              '읽으며 떠오른 생각과 기억하고 싶은 문장을 남겨보세요.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteLoadError extends StatelessWidget {
  const _NoteLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '노트를 불러오지 못했습니다.',
            style: TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    );
  }
}
