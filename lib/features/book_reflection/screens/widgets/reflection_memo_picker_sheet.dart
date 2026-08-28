import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_bar_title.dart';
import '../../../../shared/widgets/record_dialog_shell.dart';
import '../../../book_note/models/book_note.dart';
import '../../../book_note/providers/book_note_providers.dart';
import '../../../book_note/screens/book_note_detail_screen.dart';
import '../../../book_note/utils/memo_highlight.dart';

Future<BookNoteMemo?> showReflectionMemoPickerSheet(
  BuildContext context, {
  required int ownerUserId,
  required int userBookId,
}) {
  return showModalBottomSheet<BookNoteMemo>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    requestFocus: false,
    backgroundColor: Colors.transparent,
    builder: (_) => ReflectionMemoPickerSheet(
      ownerUserId: ownerUserId,
      userBookId: userBookId,
    ),
  );
}

class ReflectionMemoPickerSheet extends ConsumerStatefulWidget {
  const ReflectionMemoPickerSheet({
    super.key,
    required this.ownerUserId,
    required this.userBookId,
  });

  final int ownerUserId;
  final int userBookId;

  @override
  ConsumerState<ReflectionMemoPickerSheet> createState() =>
      _ReflectionMemoPickerSheetState();
}

class _ReflectionMemoPickerSheetState
    extends ConsumerState<ReflectionMemoPickerSheet> {
  Future<void> _openMemoList(int noteId) async {
    final memo = await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<BookNoteMemo>(
        fullscreenDialog: true,
        builder: (_) => _ReflectionMemoListScreen(
          ownerUserId: widget.ownerUserId,
          userBookId: widget.userBookId,
          noteId: noteId,
        ),
      ),
    );
    if (memo != null && mounted) Navigator.of(context).pop(memo);
  }

  @override
  Widget build(BuildContext context) {
    return RecordDialogShell(
      title: '노트 선택',
      content: SizedBox(
        height: _listHeight(context),
        child: _NoteList(
          userBookId: widget.userBookId,
          onSelected: _openMemoList,
        ),
      ),
    );
  }
}

double _listHeight(BuildContext context) {
  final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
  return (MediaQuery.sizeOf(context).height - keyboardHeight - 220).clamp(
    180.0,
    420.0,
  );
}

class _NoteList extends ConsumerWidget {
  const _NoteList({required this.userBookId, required this.onSelected});

  final int userBookId;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncNotes = ref.watch(bookNoteListProvider(userBookId));
    return switch (asyncNotes) {
      AsyncData(:final value) when value.isEmpty => const _EmptyMessage(
        icon: PhosphorIconsRegular.notepad,
        message: '불러올 노트가 없습니다.',
      ),
      AsyncData(:final value) => ListView.separated(
        itemCount: value.length,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, color: AppColors.border),
        itemBuilder: (context, index) {
          final summary = value[index];
          final title = summary.note.title?.trim();
          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              title == null || title.isEmpty
                  ? '#${value.length - index}'
                  : title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textStrong,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              '메모 ${summary.memoCount}개',
              style: const TextStyle(color: AppColors.textMuted),
            ),
            trailing: const Icon(
              PhosphorIconsRegular.caretRight,
              size: 18,
              color: AppColors.controlInactive,
            ),
            onTap: () => onSelected(summary.note.id),
          );
        },
      ),
      AsyncError() => _LoadError(
        onRetry: () => ref.invalidate(bookNoteListProvider(userBookId)),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _ReflectionMemoListScreen extends ConsumerStatefulWidget {
  const _ReflectionMemoListScreen({
    required this.ownerUserId,
    required this.userBookId,
    required this.noteId,
  });

  final int ownerUserId;
  final int userBookId;
  final int noteId;

  @override
  ConsumerState<_ReflectionMemoListScreen> createState() =>
      _ReflectionMemoListScreenState();
}

class _ReflectionMemoListScreenState
    extends ConsumerState<_ReflectionMemoListScreen> {
  bool _importantOnly = false;
  bool _didScheduleInitialScroll = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottomAfterLayout({bool force = false}) {
    if (_didScheduleInitialScroll && !force) return;
    _didScheduleInitialScroll = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final args = BookNoteDetailArgs(
      ownerUserId: widget.ownerUserId,
      userBookId: widget.userBookId,
      noteId: widget.noteId,
    );
    final asyncDetail = ref.watch(bookNoteDetailProvider(args));

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          tooltip: '메모 목록 닫기',
          icon: const Icon(PhosphorIconsRegular.x),
        ),
        title: const AppBarTitle('메모 선택'),
        backgroundColor: AppColors.pageBackground,
        foregroundColor: AppColors.textStrong,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilterChip(
              selected: _importantOnly,
              onSelected: (selected) {
                setState(() => _importantOnly = selected);
                _scrollToBottomAfterLayout(force: true);
              },
              avatar: Icon(
                PhosphorIconsRegular.highlighter,
                size: 16,
                color: _importantOnly
                    ? AppColors.textStrong
                    : AppColors.textMuted,
              ),
              label: const Text('강조 메모만'),
              selectedColor: AppColors.highlightGoldSurface,
              backgroundColor: AppColors.surface,
              side: const BorderSide(color: AppColors.border),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              labelStyle: const TextStyle(
                color: AppColors.textBody,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Expanded(child: _buildMemoList(asyncDetail, args))],
          ),
        ),
      ),
    );
  }

  Widget _buildMemoList(
    AsyncValue<BookNoteDetail> asyncDetail,
    BookNoteDetailArgs args,
  ) {
    return switch (asyncDetail) {
      AsyncData(:final value) => _buildLoadedMemoList(value),
      AsyncError() => _LoadError(
        onRetry: () => ref.invalidate(bookNoteDetailProvider(args)),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }

  Widget _buildLoadedMemoList(BookNoteDetail detail) {
    _scrollToBottomAfterLayout();
    return _MemoList(
      controller: _scrollController,
      memos: _importantOnly
          ? detail.memos.where((memo) => memo.isImportant).toList()
          : detail.memos,
      importantOnly: _importantOnly,
    );
  }
}

class _MemoList extends StatelessWidget {
  const _MemoList({
    required this.controller,
    required this.memos,
    required this.importantOnly,
  });

  final ScrollController controller;
  final List<BookNoteMemo> memos;
  final bool importantOnly;

  @override
  Widget build(BuildContext context) {
    if (memos.isEmpty) {
      return _EmptyMessage(
        icon: importantOnly
            ? PhosphorIconsRegular.highlighter
            : PhosphorIconsRegular.noteBlank,
        message: importantOnly ? '강조한 메모가 없습니다.' : '불러올 메모가 없습니다.',
      );
    }
    return ListView.separated(
      controller: controller,
      itemCount: memos.length,
      separatorBuilder: (_, _) => const SizedBox.shrink(),
      itemBuilder: (context, index) {
        final memo = memos[index];
        final hasContent = stripMemoHighlightMarkup(memo.content).trim().isNotEmpty;
        final isSelectable = memo.hasImage || hasContent;
        return BookNoteMemoTimelineItem(
          memo: memo,
          showDivider: index < memos.length - 1,
          onTap: isSelectable ? () => Navigator.of(context).pop(memo) : null,
        );
      },
    );
  }
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 32, color: AppColors.controlInactive),
          const SizedBox(height: 10),
          Text(message, style: const TextStyle(color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(onPressed: onRetry, child: const Text('다시 불러오기')),
    );
  }
}
