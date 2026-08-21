import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_confirm.dart';
import '../../../shared/widgets/record_dialog_shell.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../models/book_note.dart';
import '../providers/book_note_providers.dart';
import '../utils/memo_highlight.dart';
import 'widgets/book_note_memo_sheet.dart';
import 'widgets/book_note_refresh_indicator.dart';

class BookNoteDetailScreen extends ConsumerStatefulWidget {
  const BookNoteDetailScreen({
    super.key,
    required this.ownerUserId,
    required this.userBookId,
    required this.bookTitle,
    this.noteId,
  });

  final int ownerUserId;
  final int userBookId;
  final String bookTitle;
  final int? noteId;

  @override
  ConsumerState<BookNoteDetailScreen> createState() =>
      _BookNoteDetailScreenState();
}

class _BookNoteDetailScreenState extends ConsumerState<BookNoteDetailScreen> {
  late final TextEditingController _titleController;
  late final FocusNode _titleFocusNode;
  late final ScrollController _scrollController;
  late final BookNoteDetailArgs _args;
  bool _titleInitialized = false;
  bool _importantOnly = false;
  bool _isSavingMemo = false;
  bool _allowPop = false;
  bool _isClosing = false;
  bool _scrolledToInitialPosition = false;
  Future<void> _titleSaveChain = Future.value();

  @override
  void initState() {
    super.initState();
    _args = BookNoteDetailArgs(
      ownerUserId: widget.ownerUserId,
      userBookId: widget.userBookId,
      noteId: widget.noteId,
    );
    _titleController = TextEditingController();
    _titleFocusNode = FocusNode()..addListener(_onTitleFocusChanged);
    _scrollController = ScrollController();
    if (widget.noteId == null) _titleInitialized = true;
  }

  @override
  void dispose() {
    _titleFocusNode.removeListener(_onTitleFocusChanged);
    _titleFocusNode.dispose();
    _titleController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncDetail = ref.watch(bookNoteDetailProvider(_args));
    final detail = asyncDetail.valueOrNull;
    if (detail?.note != null) {
      final syncedTitle = detail!.note!.title ?? '';
      if (!_titleInitialized ||
          (!_titleFocusNode.hasFocus && _titleController.text != syncedTitle)) {
        _titleController.text = syncedTitle;
        _titleInitialized = true;
      }
    }

    return PopScope<void>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_closeScreen());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.bookTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          backgroundColor: AppColors.pageBackground,
          foregroundColor: AppColors.textStrong,
          elevation: 0,
          actions: [
            if (switch (asyncDetail) {
              AsyncData(:final value) => value.note != null,
              _ => false,
            })
              IconButton(
                onPressed: _isSavingMemo ? null : _deleteNote,
                tooltip: '노트 삭제',
                icon: const Icon(PhosphorIconsRegular.trash),
              ),
          ],
        ),
        body: Stack(
          children: [
            switch (asyncDetail) {
              AsyncData(:final value) =>
                widget.noteId != null && value.note == null
                    ? const _NoteNotFound()
                    : _buildContent(value),
              AsyncError() => _LoadError(
                onRetry: () => ref.invalidate(bookNoteDetailProvider(_args)),
              ),
              _ => const Center(child: CircularProgressIndicator()),
            },
            if (switch (asyncDetail) {
              AsyncData(:final value) =>
                widget.noteId == null || value.note != null,
              _ => false,
            })
              Positioned(
                left: 16,
                bottom: 16 + MediaQuery.paddingOf(context).bottom,
                child: FilterChip(
                  selected: _importantOnly,
                  onSelected: (selected) =>
                      setState(() => _importantOnly = selected),
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
                  elevation: 3,
                  labelStyle: const TextStyle(
                    color: AppColors.textBody,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        floatingActionButton: switch (asyncDetail) {
          AsyncData(:final value)
              when widget.noteId == null || value.note != null =>
            FloatingActionButton(
              onPressed: _isSavingMemo ? null : _addMemo,
              tooltip: '메모 빠르게 추가',
              shape: const CircleBorder(),
              backgroundColor: _isSavingMemo
                  ? AppColors.surfaceSubtle
                  : AppColors.accentFill,
              foregroundColor: AppColors.textStrong,
              child: _isSavingMemo
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.textStrong,
                      ),
                    )
                  : const Icon(PhosphorIconsRegular.plus),
            ),
          _ => null,
        },
      ),
    );
  }

  Widget _buildContent(BookNoteDetail detail) {
    _scheduleInitialScrollToBottom();
    final visibleMemos = _importantOnly
        ? detail.memos.where((memo) => memo.isImportant).toList(growable: false)
        : detail.memos;
    return BookNoteRefreshIndicator(
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            sliver: SliverList.list(
              children: [
                TextField(
                  controller: _titleController,
                  focusNode: _titleFocusNode,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => unawaited(_saveTitle()),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textStrong,
                  ),
                  decoration: const InputDecoration(
                    hintText: '제목을 입력하세요 (선택)',
                    fillColor: Colors.transparent,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ],
            ),
          ),
          if (visibleMemos.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyMemos(importantOnly: _importantOnly),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
              sliver: SliverList.builder(
                itemCount: visibleMemos.length,
                itemBuilder: (context, index) {
                  final memo = visibleMemos[index];
                  return _NoteMemoTimelineItem(
                    memo: memo,
                    showDivider: index < visibleMemos.length - 1,
                    onTap:
                        memo.type == BookNoteMemoType.photo &&
                            memo.imageUrl != null
                        ? () => _showPhotoMemo(
                            memo,
                            totalMemoCount: detail.memos.length,
                          )
                        : () => _showMemoActions(
                            memo,
                            totalMemoCount: detail.memos.length,
                          ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  void _scheduleInitialScrollToBottom() {
    if (_scrolledToInitialPosition) return;
    _scrolledToInitialPosition = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  /// 새 메모는 목록 맨 아래(최신)에 추가되므로, 추가 직후 자연스럽게
  /// 아래까지 스크롤해 방금 추가한 메모가 바로 보이게 한다.
  void _scrollToNewestMemo() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _onTitleFocusChanged() {
    if (!_titleFocusNode.hasFocus) unawaited(_saveTitle());
  }

  Future<void> _closeScreen() async {
    if (_isClosing) return;
    if (_isSavingMemo) {
      AppSnackBar.info(context, '메모를 저장하고 있습니다.');
      return;
    }
    _isClosing = true;
    await _saveTitle();
    if (!mounted) return;
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  Future<bool> _saveTitle({bool createWhenEmpty = false}) async {
    final title = _titleController.text.trim();
    final save = _titleSaveChain.then(
      (_) => _performTitleSave(title, createWhenEmpty: createWhenEmpty),
    );
    _titleSaveChain = save.then<void>((_) {});
    return save;
  }

  Future<bool> _performTitleSave(
    String title, {
    required bool createWhenEmpty,
  }) async {
    if (!mounted) return false;
    final currentNote = ref
        .read(bookNoteDetailProvider(_args))
        .valueOrNull
        ?.note;
    if (title.isEmpty && currentNote == null && !createWhenEmpty) {
      return false;
    }
    try {
      await ref
          .read(bookNoteDetailProvider(_args).notifier)
          .saveTitle(title.isEmpty ? null : title);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _addMemo() async {
    final draft = await showBookNoteMemoQuickComposer(context);
    if (draft == null || !mounted) return;
    if (!await _saveTitle(createWhenEmpty: true)) {
      if (mounted) AppSnackBar.error(context, '노트를 준비하지 못했습니다.');
      return;
    }
    if (!mounted) return;
    await _saveMemo(() {
      return ref
          .read(bookNoteDetailProvider(_args).notifier)
          .createNoteMemo(draft);
    });
    _scrollToNewestMemo();
  }

  Future<void> _editMemo(BookNoteMemo memo) async {
    final draft = await showBookNoteMemoEditor(context, initialMemo: memo);
    if (draft == null || !mounted) return;
    await _saveMemo(() {
      return ref
          .read(bookNoteDetailProvider(_args).notifier)
          .updateNoteMemo(memo.id, draft);
    });
  }

  Future<void> _showMemoActions(
    BookNoteMemo memo, {
    required int totalMemoCount,
  }) async {
    if (_isSavingMemo) {
      AppSnackBar.info(context, '메모를 저장하고 있습니다.');
      return;
    }
    final action = await showModalBottomSheet<_NoteMemoAction>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _NoteMemoActionSheet(),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _NoteMemoAction.edit:
        await _editMemo(memo);
      case _NoteMemoAction.copy:
        await _copyMemo(memo);
      case _NoteMemoAction.delete:
        await _deleteMemo(memo, totalMemoCount: totalMemoCount);
    }
  }

  Future<void> _showPhotoMemo(
    BookNoteMemo memo, {
    required int totalMemoCount,
  }) async {
    if (_isSavingMemo) {
      AppSnackBar.info(context, '메모를 저장하고 있습니다.');
      return;
    }
    final action = await showDialog<_PhotoMemoAction>(
      context: context,
      useSafeArea: false,
      builder: (context) => _PhotoMemoViewer(imageUrl: memo.imageUrl!),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _PhotoMemoAction.edit:
        await _editMemo(memo);
      case _PhotoMemoAction.delete:
        await _deleteMemo(memo, totalMemoCount: totalMemoCount);
    }
  }

  Future<void> _copyMemo(BookNoteMemo memo) async {
    // 화면(_MemoRichText)은 앞뒤 공백·줄바꿈을 그대로 표시하므로, 복사
    // 가능 여부 판단에만 trim()을 쓰고 실제로 복사하는 값은 마크업만
    // 제거한 원문을 그대로 둔다.
    final content = stripMemoHighlightMarkup(memo.content);
    if (content.trim().isEmpty) {
      AppSnackBar.info(context, '복사할 내용이 없습니다.');
      return;
    }
    try {
      await Clipboard.setData(ClipboardData(text: content));
      developer.log(
        '[메모 복사] noteMemoId=${memo.id} target=clipboard result=SUCCESS',
      );
      if (mounted) AppSnackBar.success(context, '메모를 복사했습니다.');
    } catch (error, stackTrace) {
      developer.log(
        '[메모 복사] noteMemoId=${memo.id} target=clipboard '
        'result=FAIL reason=clipboard_write_error',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) AppSnackBar.error(context, '메모를 복사하지 못했습니다.');
    }
  }

  Future<void> _saveMemo(Future<void> Function() save) async {
    setState(() => _isSavingMemo = true);
    try {
      await save();
    } catch (error) {
      // 사진 형식/용량 거절(FileSystemException.message)처럼 원인이 분명한
      // 경우는 그대로 보여준다 — "저장하지 못했습니다"만으로는 사용자가
      // 사진을 바꿔야 하는지조차 알 수 없다.
      final reason = error is FileSystemException && error.message.isNotEmpty
          ? error.message
          : null;
      if (mounted) {
        AppSnackBar.error(context, reason ?? '메모를 저장하지 못했습니다.');
      }
    } finally {
      if (mounted) setState(() => _isSavingMemo = false);
    }
  }

  Future<void> _deleteMemo(
    BookNoteMemo memo, {
    required int totalMemoCount,
  }) async {
    final isLast = totalMemoCount == 1;
    final confirmed = await AppConfirm.show(
      context,
      title: '메모 삭제',
      message: isLast
          ? '마지막 메모를 삭제하면 이 노트도 함께 사라집니다. 삭제할까요?'
          : '이 메모를 삭제할까요?',
      confirmText: '삭제',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      final noteWasDeleted = await ref
          .read(bookNoteDetailProvider(_args).notifier)
          .deleteNoteMemo(memo.id);
      if (!mounted) return;
      if (noteWasDeleted) {
        _isClosing = true;
        setState(() => _allowPop = true);
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) Navigator.of(context).pop();
      } else {
        AppSnackBar.success(context, '메모를 삭제했습니다.');
      }
    } catch (_) {
      if (mounted) AppSnackBar.error(context, '메모를 삭제하지 못했습니다.');
    }
  }

  Future<void> _deleteNote() async {
    if (_isSavingMemo) {
      AppSnackBar.info(context, '메모를 저장하고 있습니다.');
      return;
    }
    final confirmed = await AppConfirm.show(
      context,
      title: '노트 삭제',
      message: '이 노트와 모든 메모를 삭제할까요?',
      confirmText: '삭제',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _isSavingMemo = true);
    try {
      await ref.read(bookNoteDetailProvider(_args).notifier).deleteNote();
      if (!mounted) return;
      _isClosing = true;
      setState(() => _allowPop = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) AppSnackBar.error(context, '노트를 삭제하지 못했습니다.');
    } finally {
      if (mounted) setState(() => _isSavingMemo = false);
    }
  }
}

enum _NoteMemoAction { edit, copy, delete }

enum _PhotoMemoAction { edit, delete }

class _PhotoMemoViewer extends StatelessWidget {
  const _PhotoMemoViewer({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: AppColors.mediaBackdrop,
      child: Scaffold(
        backgroundColor: AppColors.mediaBackdrop,
        body: Stack(
          fit: StackFit.expand,
          children: [
            SafeArea(
              bottom: false,
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4,
                child: Center(
                  child: _MemoPhotoImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: SafeArea(
                child: IconButton.filledTonal(
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: '닫기',
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.surface.withValues(alpha: 0.88),
                    foregroundColor: AppColors.textStrong,
                  ),
                  icon: const Icon(PhosphorIconsRegular.x),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: Material(
          color: AppColors.mediaBackdrop,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton.icon(
                    onPressed: () =>
                        Navigator.of(context).pop(_PhotoMemoAction.edit),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.surface,
                      minimumSize: const Size(96, 48),
                    ),
                    icon: const Icon(PhosphorIconsRegular.pencil, size: 19),
                    label: const Text('수정'),
                  ),
                  const SizedBox(width: 20),
                  TextButton.icon(
                    onPressed: () =>
                        Navigator.of(context).pop(_PhotoMemoAction.delete),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.error,
                      minimumSize: const Size(96, 48),
                    ),
                    icon: const Icon(PhosphorIconsRegular.trash, size: 19),
                    label: const Text('삭제'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoteMemoActionSheet extends StatelessWidget {
  const _NoteMemoActionSheet();

  @override
  Widget build(BuildContext context) {
    return RecordDialogShell(
      title: '메모',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _NoteMemoActionTile(
            icon: PhosphorIconsRegular.copy,
            label: '복사',
            onTap: () => Navigator.of(context).pop(_NoteMemoAction.copy),
          ),
          const SizedBox(height: 8),
          _NoteMemoActionTile(
            icon: PhosphorIconsRegular.pencil,
            label: '수정',
            onTap: () => Navigator.of(context).pop(_NoteMemoAction.edit),
          ),
          const SizedBox(height: 8),
          _NoteMemoActionTile(
            icon: PhosphorIconsRegular.trash,
            label: '삭제',
            destructive: true,
            onTap: () => Navigator.of(context).pop(_NoteMemoAction.delete),
          ),
        ],
      ),
    );
  }
}

class _NoteMemoActionTile extends StatelessWidget {
  const _NoteMemoActionTile({
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
    final color = destructive ? AppColors.error : AppColors.textStrong;
    return Material(
      color: AppColors.surfaceSubtle,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteMemoTimelineItem extends StatelessWidget {
  const _NoteMemoTimelineItem({
    required this.memo,
    required this.showDivider,
    required this.onTap,
  });

  final BookNoteMemo memo;
  final bool showDivider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final typeStyle = _NoteMemoTypeStyle.of(memo.type);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (memo.type != BookNoteMemoType.quote)
                Positioned(
                  left: 0,
                  top: 4,
                  bottom: showDivider ? 24 : 12,
                  child: Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: typeStyle.sidebar,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 0, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      // 왼쪽 묶음(아이콘·라벨·강조·쪽수)과 시간, 딱 두
                      // 덩어리만 flex 경쟁 없이 양 끝에 배치한다. 예전처럼
                      // 라벨/쪽수/시간을 각각 Flexible로 두고 그 사이에
                      // Spacer를 넣으면, 남는 공간이 이 flex 형제들
                      // 전부에게 균등하게(1/N씩) 나눠져 Spacer가 실제
                      // 남는 공간을 다 못 가져가고, 그 결과 시간이 오른쪽
                      // 끝이 아니라 중간쯤에서 멈춘다.
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                typeStyle.icon,
                                color: typeStyle.foreground,
                                size: 14,
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  memo.type.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: typeStyle.foreground,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (memo.isImportant) ...[
                                const SizedBox(width: 7),
                                const Icon(
                                  PhosphorIconsRegular.highlighter,
                                  size: 14,
                                  color: AppColors.highlightGold,
                                ),
                              ],
                              if (memo.pageLabel != null) ...[
                                const SizedBox(width: 16),
                                Flexible(
                                  child: Text(
                                    memo.pageLabel!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 8, right: 12),
                          child: Text(
                            _formatDateTime(memo.createdAt),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (memo.type == BookNoteMemoType.photo &&
                              memo.imageUrl != null)
                            _PhotoContent(imageUrl: memo.imageUrl!),
                          if (memo.content != null &&
                              memo.content!.isNotEmpty) ...[
                            if (memo.type == BookNoteMemoType.photo &&
                                memo.imageUrl != null)
                              const SizedBox(height: 10),
                            if (memo.type == BookNoteMemoType.quote)
                              _QuoteContent(memo.content!)
                            else
                              _MemoRichText(memo.content!, italic: false),
                          ],
                        ],
                      ),
                    ),
                    if (showDivider) ...[
                      const SizedBox(height: 26),
                      const Align(
                        alignment: Alignment.center,
                        child: SizedBox(
                          width: 312,
                          child: Divider(
                            height: 1,
                            thickness: 1,
                            color: AppColors.border,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ] else
                      const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    final difference = DateTime.now().difference(local);
    final elapsed = difference.isNegative ? Duration.zero : difference;
    if (elapsed.inSeconds < 60) {
      final seconds = elapsed.inSeconds < 1 ? 1 : elapsed.inSeconds;
      return '$seconds초 전';
    }
    if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}분 전';
    if (elapsed.inHours < 24) return '${elapsed.inHours}시간 전';
    if (elapsed.inDays < 30) return '${elapsed.inDays}일 전';

    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.month}-${local.day} $hour:$minute';
  }
}

class _NoteMemoTypeStyle {
  const _NoteMemoTypeStyle({
    required this.icon,
    required this.foreground,
    required this.background,
  });

  final IconData icon;
  final Color foreground;
  final Color background;

  Color get sidebar => Color.lerp(background, foreground, 0.32)!;

  static _NoteMemoTypeStyle of(BookNoteMemoType type) => switch (type) {
    BookNoteMemoType.summary => const _NoteMemoTypeStyle(
      icon: PhosphorIconsRegular.notePencil,
      foreground: AppColors.memoSummaryForeground,
      background: AppColors.memoSummarySurface,
    ),
    BookNoteMemoType.quote => const _NoteMemoTypeStyle(
      icon: PhosphorIconsRegular.quotes,
      foreground: AppColors.memoQuoteForeground,
      background: AppColors.memoQuoteSurface,
    ),
    BookNoteMemoType.thought => const _NoteMemoTypeStyle(
      icon: PhosphorIconsRegular.lightbulb,
      foreground: AppColors.memoThoughtForeground,
      background: AppColors.memoThoughtSurface,
    ),
    BookNoteMemoType.photo => const _NoteMemoTypeStyle(
      icon: PhosphorIconsRegular.imageSquare,
      foreground: AppColors.memoPhotoForeground,
      background: AppColors.memoPhotoSurface,
    ),
  };
}

class _QuoteContent extends StatelessWidget {
  const _QuoteContent(this.content);

  final String content;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(-16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '“',
            style: TextStyle(
              color: AppColors.memoQuoteForeground,
              fontSize: 46,
              height: 0.85,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: _MemoRichText(content, italic: true)),
        ],
      ),
    );
  }
}

class _MemoRichText extends StatelessWidget {
  const _MemoRichText(this.content, {required this.italic});

  final String content;
  final bool italic;

  @override
  Widget build(BuildContext context) {
    final baseStyle = TextStyle(
      color: AppColors.textBody,
      height: 1.55,
      fontSize: 14,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    );
    final spans = <TextSpan>[];
    final expression = RegExp(r'::hl\[\[(.*?)\]\]', dotAll: true);
    var offset = 0;
    for (final match in expression.allMatches(content)) {
      if (match.start > offset) {
        spans.add(TextSpan(text: content.substring(offset, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(1),
          style: const TextStyle(
            backgroundColor: AppColors.highlightGoldSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      offset = match.end;
    }
    if (offset < content.length) {
      spans.add(TextSpan(text: content.substring(offset)));
    }
    return Text.rich(TextSpan(style: baseStyle, children: spans));
  }
}

class _PhotoContent extends StatelessWidget {
  const _PhotoContent({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: _MemoPhotoImage(imageUrl: imageUrl, fit: BoxFit.cover),
      ),
    );
  }
}

class _MemoPhotoImage extends StatelessWidget {
  const _MemoPhotoImage({required this.imageUrl, required this.fit});

  final String imageUrl;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
      return Image.network(
        imageUrl,
        fit: fit,
        errorBuilder: (_, _, _) => const _BrokenImage(),
      );
    }
    final filePath = imageUrl.startsWith('file://')
        ? Uri.parse(imageUrl).toFilePath()
        : imageUrl;
    return Image.file(
      File(filePath),
      fit: fit,
      errorBuilder: (_, _, _) => const _BrokenImage(),
    );
  }
}

class _BrokenImage extends StatelessWidget {
  const _BrokenImage();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.surfaceSubtle,
      child: Center(
        child: Icon(
          PhosphorIconsRegular.imageSquare,
          color: AppColors.textMuted,
          size: 30,
        ),
      ),
    );
  }
}

class _EmptyMemos extends StatelessWidget {
  const _EmptyMemos({required this.importantOnly});

  final bool importantOnly;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 32, 32, 80),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              importantOnly
                  ? PhosphorIconsRegular.highlighter
                  : PhosphorIconsRegular.notePencil,
              size: 42,
              color: AppColors.controlInactive,
            ),
            const SizedBox(height: 14),
            Text(
              importantOnly ? '강조 메모가 없습니다.' : '아직 메모가 없습니다.',
              style: const TextStyle(
                color: AppColors.textStrong,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              importantOnly
                  ? '강조 표시를 한 기록이 여기에 모입니다.'
                  : '요약, 발췌, 생각, 사진을 차곡차곡 남겨보세요.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteNotFound extends StatelessWidget {
  const _NoteNotFound();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        '노트를 찾을 수 없습니다.',
        style: TextStyle(color: AppColors.textMuted),
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
