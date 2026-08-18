import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_confirm.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../models/book_memo.dart';
import '../providers/book_memo_providers.dart';
import 'widgets/book_memo_item_sheet.dart';

class BookMemoDetailScreen extends ConsumerStatefulWidget {
  const BookMemoDetailScreen({
    super.key,
    required this.ownerUserId,
    required this.userBookId,
    required this.bookTitle,
    this.memoId,
  });

  final int ownerUserId;
  final int userBookId;
  final String bookTitle;
  final int? memoId;

  @override
  ConsumerState<BookMemoDetailScreen> createState() =>
      _BookMemoDetailScreenState();
}

enum _TitleSaveStatus { idle, saving, saved, error }

class _BookMemoDetailScreenState extends ConsumerState<BookMemoDetailScreen> {
  late final TextEditingController _titleController;
  late final FocusNode _titleFocusNode;
  late final BookMemoDetailArgs _args;
  bool _titleInitialized = false;
  bool _importantOnly = false;
  bool _isSavingItem = false;
  bool _allowPop = false;
  bool _isClosing = false;
  _TitleSaveStatus _titleStatus = _TitleSaveStatus.idle;
  Future<void> _titleSaveChain = Future.value();

  @override
  void initState() {
    super.initState();
    _args = BookMemoDetailArgs(
      ownerUserId: widget.ownerUserId,
      userBookId: widget.userBookId,
      memoId: widget.memoId,
    );
    _titleController = TextEditingController();
    _titleFocusNode = FocusNode()..addListener(_onTitleFocusChanged);
    if (widget.memoId == null) _titleInitialized = true;
  }

  @override
  void dispose() {
    _titleFocusNode.removeListener(_onTitleFocusChanged);
    _titleFocusNode.dispose();
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncDetail = ref.watch(bookMemoDetailProvider(_args));
    final detail = asyncDetail.valueOrNull;
    if (!_titleInitialized && detail?.memo != null) {
      _titleController.text = detail!.memo!.title ?? '';
      _titleInitialized = true;
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
        ),
        body: switch (asyncDetail) {
          AsyncData(:final value) =>
            widget.memoId != null && value.memo == null
                ? const _MemoNotFound()
                : _buildContent(value),
          AsyncError() => _LoadError(
            onRetry: () => ref.invalidate(bookMemoDetailProvider(_args)),
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
        floatingActionButton: switch (asyncDetail) {
          AsyncData(:final value)
              when widget.memoId == null || value.memo != null =>
            FloatingActionButton(
              onPressed: _isSavingItem ? null : _addItem,
              tooltip: '메모 조각 빠르게 추가',
              shape: const CircleBorder(),
              backgroundColor: _isSavingItem
                  ? AppColors.surfaceSubtle
                  : AppColors.accentFill,
              foregroundColor: AppColors.textStrong,
              child: _isSavingItem
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

  Widget _buildContent(BookMemoDetail detail) {
    final visibleItems = _importantOnly
        ? detail.items.where((item) => item.isImportant).toList(growable: false)
        : detail.items;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          sliver: SliverList.list(
            children: [
              TextField(
                controller: _titleController,
                focusNode: _titleFocusNode,
                textInputAction: TextInputAction.done,
                onChanged: (_) =>
                    setState(() => _titleStatus = _TitleSaveStatus.idle),
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
              SizedBox(
                height: 20,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _titleStatusText,
                    style: TextStyle(
                      fontSize: 11,
                      color: _titleStatus == _TitleSaveStatus.error
                          ? AppColors.error
                          : AppColors.textMuted,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
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
                  label: const Text('중요 조각만'),
                  selectedColor: AppColors.highlightGoldSurface,
                  backgroundColor: AppColors.surface,
                  side: const BorderSide(color: AppColors.border),
                  labelStyle: const TextStyle(
                    color: AppColors.textBody,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (visibleItems.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyItems(importantOnly: _importantOnly),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            sliver: SliverList.separated(
              itemCount: visibleItems.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) => _MemoTimelineItem(
                item: visibleItems[index],
                onTap: () => _editItem(visibleItems[index]),
                onDelete: () => _deleteItem(
                  visibleItems[index],
                  totalItemCount: detail.items.length,
                ),
              ),
            ),
          ),
      ],
    );
  }

  String get _titleStatusText => switch (_titleStatus) {
    _TitleSaveStatus.idle => '',
    _TitleSaveStatus.saving => '저장 중…',
    _TitleSaveStatus.saved => '저장됨',
    _TitleSaveStatus.error => '제목을 저장하지 못했습니다.',
  };

  void _onTitleFocusChanged() {
    if (!_titleFocusNode.hasFocus) unawaited(_saveTitle());
  }

  Future<void> _closeScreen() async {
    if (_isClosing) return;
    if (_isSavingItem) {
      AppSnackBar.info(context, '메모 조각을 저장하고 있습니다.');
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
    final currentMemo = ref
        .read(bookMemoDetailProvider(_args))
        .valueOrNull
        ?.memo;
    if (title.isEmpty && currentMemo == null && !createWhenEmpty) {
      return false;
    }
    setState(() => _titleStatus = _TitleSaveStatus.saving);
    try {
      await ref
          .read(bookMemoDetailProvider(_args).notifier)
          .saveTitle(title.isEmpty ? null : title);
      if (mounted) setState(() => _titleStatus = _TitleSaveStatus.saved);
      return true;
    } catch (_) {
      if (mounted) setState(() => _titleStatus = _TitleSaveStatus.error);
      return false;
    }
  }

  Future<void> _addItem() async {
    final draft = await showBookMemoQuickComposer(context);
    if (draft == null || !mounted) return;
    if (!await _saveTitle(createWhenEmpty: true)) {
      if (mounted) AppSnackBar.error(context, '메모를 준비하지 못했습니다.');
      return;
    }
    if (!mounted) return;
    await _saveItem(() {
      return ref.read(bookMemoDetailProvider(_args).notifier).createItem(draft);
    });
  }

  Future<void> _editItem(BookMemoItem item) async {
    final draft = await showBookMemoItemEditor(context, initialItem: item);
    if (draft == null || !mounted) return;
    await _saveItem(() {
      return ref
          .read(bookMemoDetailProvider(_args).notifier)
          .updateItem(item.id, draft);
    });
  }

  Future<void> _saveItem(Future<void> Function() save) async {
    setState(() => _isSavingItem = true);
    try {
      await save();
      if (mounted) AppSnackBar.success(context, '메모 조각을 저장했습니다.');
    } catch (_) {
      if (mounted) AppSnackBar.error(context, '메모 조각을 저장하지 못했습니다.');
    } finally {
      if (mounted) setState(() => _isSavingItem = false);
    }
  }

  Future<void> _deleteItem(
    BookMemoItem item, {
    required int totalItemCount,
  }) async {
    final isLast = totalItemCount == 1;
    final confirmed = await AppConfirm.show(
      context,
      title: '조각 삭제',
      message: isLast
          ? '마지막 조각을 삭제하면 이 메모도 함께 사라집니다. 삭제할까요?'
          : '이 메모 조각을 삭제할까요?',
      confirmText: '삭제',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      final memoWasDeleted = await ref
          .read(bookMemoDetailProvider(_args).notifier)
          .deleteItem(item.id);
      if (!mounted) return;
      if (memoWasDeleted) {
        _isClosing = true;
        setState(() => _allowPop = true);
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) Navigator.of(context).pop();
      } else {
        AppSnackBar.success(context, '메모 조각을 삭제했습니다.');
      }
    } catch (_) {
      if (mounted) AppSnackBar.error(context, '메모 조각을 삭제하지 못했습니다.');
    }
  }
}

class _MemoTimelineItem extends StatelessWidget {
  const _MemoTimelineItem({
    required this.item,
    required this.onTap,
    required this.onDelete,
  });

  final BookMemoItem item;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final typeStyle = _MemoTypeStyle.of(item.type);
    const cardBackground = AppColors.surface;
    final headerBackground = Color.lerp(
      AppColors.surface,
      typeStyle.background,
      0.62,
    )!;
    return Material(
      color: cardBackground,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: cardBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: typeStyle.foreground.withValues(alpha: 0.1),
            ),
            boxShadow: const [
              BoxShadow(
                color: AppColors.shadowSoft,
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
                decoration: BoxDecoration(
                  color: headerBackground,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(typeStyle.icon, color: typeStyle.foreground, size: 14),
                    const SizedBox(width: 5),
                    Text(
                      item.type.label,
                      style: TextStyle(
                        color: typeStyle.foreground,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (item.isImportant) ...[
                      const SizedBox(width: 7),
                      const Icon(
                        PhosphorIconsRegular.highlighter,
                        size: 14,
                        color: AppColors.highlightGold,
                      ),
                    ],
                    const Spacer(),
                    if (item.pageLabel != null) ...[
                      Text(
                        item.pageLabel!,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      _formatDateTime(item.createdAt),
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    IconButton(
                      onPressed: onDelete,
                      tooltip: '조각 삭제',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 36,
                        height: 36,
                      ),
                      icon: const Icon(
                        PhosphorIconsRegular.trash,
                        size: 16,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (item.type == BookMemoItemType.photo &&
                        item.imageUrl != null)
                      _PhotoContent(imageUrl: item.imageUrl!),
                    if (item.content != null && item.content!.isNotEmpty) ...[
                      if (item.type == BookMemoItemType.photo &&
                          item.imageUrl != null)
                        const SizedBox(height: 10),
                      _MemoRichText(
                        item.content!,
                        italic: item.type == BookMemoItemType.quote,
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

class _MemoTypeStyle {
  const _MemoTypeStyle({
    required this.icon,
    required this.foreground,
    required this.background,
  });

  final IconData icon;
  final Color foreground;
  final Color background;

  static _MemoTypeStyle of(BookMemoItemType type) => switch (type) {
    BookMemoItemType.summary => const _MemoTypeStyle(
      icon: PhosphorIconsRegular.notePencil,
      foreground: AppColors.memoSummaryForeground,
      background: AppColors.memoSummarySurface,
    ),
    BookMemoItemType.quote => const _MemoTypeStyle(
      icon: PhosphorIconsRegular.quotes,
      foreground: AppColors.memoQuoteForeground,
      background: AppColors.memoQuoteSurface,
    ),
    BookMemoItemType.thought => const _MemoTypeStyle(
      icon: PhosphorIconsRegular.lightbulb,
      foreground: AppColors.memoThoughtForeground,
      background: AppColors.memoThoughtSurface,
    ),
    BookMemoItemType.photo => const _MemoTypeStyle(
      icon: PhosphorIconsRegular.imageSquare,
      foreground: AppColors.memoPhotoForeground,
      background: AppColors.memoPhotoSurface,
    ),
  };
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
    final image = _buildImage(BoxFit.cover);
    return Semantics(
      button: true,
      label: '사진 크게 보기',
      child: GestureDetector(
        onTap: () => showDialog<void>(
          context: context,
          builder: (context) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(16),
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4,
              child: _buildImage(BoxFit.contain),
            ),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(aspectRatio: 16 / 9, child: image),
        ),
      ),
    );
  }

  Widget _buildImage(BoxFit fit) {
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

class _EmptyItems extends StatelessWidget {
  const _EmptyItems({required this.importantOnly});

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
              importantOnly ? '중요 조각이 없습니다.' : '아직 조각이 없습니다.',
              style: const TextStyle(
                color: AppColors.textStrong,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              importantOnly
                  ? '중요 조각 표시를 한 기록이 여기에 모입니다.'
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

class _MemoNotFound extends StatelessWidget {
  const _MemoNotFound();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        '메모를 찾을 수 없습니다.',
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
            '메모를 불러오지 못했습니다.',
            style: TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    );
  }
}
