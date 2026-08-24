import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_confirm.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/record_dialog_shell.dart';
import '../models/book_reflection.dart';
import '../providers/book_reflection_providers.dart';
import '../services/book_reflection_content_adapter.dart';
import 'book_reflection_editor_screen.dart';
import 'widgets/reflection_image_embed_builder.dart';
import 'widgets/reflection_title_body_divider.dart';

/// 독후감 상세. 현재 Quill Delta와 레거시 Tiptap JSON을 같은 어댑터로
/// 읽어 서식·이미지를 표시하고, 본인 로컬 데이터의 수정 화면으로 연결한다.
class BookReflectionDetailScreen extends ConsumerWidget {
  const BookReflectionDetailScreen({
    super.key,
    required this.ownerUserId,
    required this.userBookId,
    required this.bookTitle,
    required this.reflectionId,
  });

  final int ownerUserId;
  final int userBookId;
  final String bookTitle;
  final int reflectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = BookReflectionDetailArgs(
      ownerUserId: ownerUserId,
      userBookId: userBookId,
      reflectionId: reflectionId,
    );
    final asyncReflection = ref.watch(bookReflectionDetailProvider(args));

    return Scaffold(
      appBar: AppBar(
        title: Text(bookTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        backgroundColor: AppColors.pageBackground,
        foregroundColor: AppColors.textStrong,
        elevation: 0,
      ),
      body: switch (asyncReflection) {
        AsyncData(:final value) =>
          value == null
              ? const _ReflectionNotFound()
              : _ReflectionBody(
                  reflection: value,
                  onMore: () => _openActions(context, ref, value, args),
                ),
        AsyncError() => _ReflectionLoadError(
          onRetry: () => ref.invalidate(bookReflectionDetailProvider(args)),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref,
    BookReflection reflection,
    BookReflectionDetailArgs args,
  ) async {
    await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => BookReflectionEditorScreen(
          ownerUserId: ownerUserId,
          userBookId: userBookId,
          bookTitle: bookTitle,
          reflection: reflection,
        ),
      ),
    );
    ref.invalidate(bookReflectionDetailProvider(args));
  }

  Future<void> _openActions(
    BuildContext context,
    WidgetRef ref,
    BookReflection reflection,
    BookReflectionDetailArgs args,
  ) async {
    final action = await showModalBottomSheet<_ReflectionAction>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => RecordDialogShell(
        title: '독후감 관리',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: reflection.isPublic,
              onChanged: (_) =>
                  Navigator.of(sheetContext).pop(_ReflectionAction.visibility),
              secondary: Icon(
                reflection.isPublic
                    ? PhosphorIconsRegular.globe
                    : PhosphorIconsRegular.lock,
              ),
              title: const Text('공개 여부'),
              subtitle: Text(reflection.isPublic ? '공개' : '비공개'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(PhosphorIconsRegular.pencil),
              title: const Text('수정'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_ReflectionAction.edit),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                PhosphorIconsRegular.trash,
                color: AppColors.error,
              ),
              title: const Text('삭제', style: TextStyle(color: AppColors.error)),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_ReflectionAction.delete),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;

    switch (action) {
      case _ReflectionAction.visibility:
        await _setPublic(context, ref, reflection, args);
        return;
      case _ReflectionAction.edit:
        await _openEditor(context, ref, reflection, args);
        return;
      case _ReflectionAction.delete:
        await _delete(context, ref, reflection);
        return;
    }
  }

  Future<void> _setPublic(
    BuildContext context,
    WidgetRef ref,
    BookReflection reflection,
    BookReflectionDetailArgs args,
  ) async {
    try {
      await ref
          .read(bookReflectionRepositoryProvider)
          .setPublic(
            ownerUserId: ownerUserId,
            userBookId: userBookId,
            reflectionId: reflection.id,
            isPublic: !reflection.isPublic,
          );
      ref.read(bookReflectionSyncVersionProvider.notifier).state++;
      ref.invalidate(bookReflectionDetailProvider(args));
      if (context.mounted) {
        AppSnackBar.success(
          context,
          reflection.isPublic ? '비공개로 변경했습니다.' : '공개로 변경했습니다.',
        );
      }
    } catch (_) {
      if (context.mounted) {
        AppSnackBar.error(context, '공개 여부를 변경하지 못했습니다.');
      }
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    BookReflection reflection,
  ) async {
    final confirmed = await AppConfirm.show(
      context,
      title: '독후감 삭제',
      message: '이 독후감을 삭제할까요?',
      confirmText: '삭제',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    try {
      await ref
          .read(bookReflectionRepositoryProvider)
          .delete(
            ownerUserId: ownerUserId,
            userBookId: userBookId,
            reflectionId: reflection.id,
          );
      ref.read(bookReflectionSyncVersionProvider.notifier).state++;
      if (context.mounted) Navigator.of(context).pop();
    } catch (_) {
      if (context.mounted) {
        AppSnackBar.error(context, '독후감을 삭제하지 못했습니다.');
      }
    }
  }
}

enum _ReflectionAction { visibility, edit, delete }

class _ReflectionBody extends StatelessWidget {
  const _ReflectionBody({required this.reflection, required this.onMore});

  final BookReflection reflection;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    if (reflection.isHidden) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            '숨김 처리된 독후감입니다.',
            style: TextStyle(color: AppColors.textMuted),
          ),
        ),
      );
    }

    final title = reflection.title?.trim();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(10, 16, 10, 40),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title == null || title.isEmpty ? '제목 없음' : title,
                    style: const TextStyle(
                      color: AppColors.textStrong,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _formatDate(reflection.updatedAt),
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onMore,
                  tooltip: '독후감 관리',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(PhosphorIconsRegular.dotsThree, size: 22),
                ),
              ],
            ),
            const ReflectionTitleBodyDivider(horizontalInset: 0),
            if (reflection.contentJson != null)
              _ReflectionRichContent(
                key: ValueKey(reflection.updatedAt),
                reflectionId: reflection.id,
                contentJson: reflection.contentJson!,
              )
            else
              Text(
                reflection.contentText?.trim().isNotEmpty == true
                    ? reflection.contentText!.trim()
                    : '내용이 없습니다.',
                style: const TextStyle(
                  color: AppColors.textBody,
                  fontSize: 15,
                  height: 1.6,
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    return '${local.year}.${local.month}.${local.day}';
  }
}

class _ReflectionRichContent extends ConsumerStatefulWidget {
  const _ReflectionRichContent({
    super.key,
    required this.reflectionId,
    required this.contentJson,
  });

  final int reflectionId;
  final Map<String, dynamic> contentJson;

  @override
  ConsumerState<_ReflectionRichContent> createState() =>
      _ReflectionRichContentState();
}

class _ReflectionRichContentState
    extends ConsumerState<_ReflectionRichContent> {
  static const _adapter = BookReflectionContentAdapter();
  late final QuillController _controller;
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller = QuillController(
      document: _adapter.fromServerJson(widget.contentJson),
      selection: const TextSelection.collapsed(offset: 0),
      readOnly: true,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 본문의 서버 이미지는 로컬 사본이 있으면 그것으로 보여준다(아직
    // 로드 전이면 서버 URL로 표시하고, 매칭이 도착하면 다시 그린다).
    final localImagePaths =
        ref.watch(reflectionLocalImagesProvider(widget.reflectionId)).value ??
        const <String, String>{};
    return ReflectionQuillEditor(
      controller: _controller,
      focusNode: _focusNode,
      scrollController: _scrollController,
      config: QuillEditorConfig(
        scrollable: false,
        padding: EdgeInsets.zero,
        enableInteractiveSelection: true,
        showCursor: false,
        customStyles: bookReflectionQuillStyles,
        textSpanBuilder: reflectionTextSpanBuilder,
        embedBuilders: [
          ReflectionImageEmbedBuilder(localImagePaths: localImagePaths),
        ],
      ),
    );
  }
}

class _ReflectionNotFound extends StatelessWidget {
  const _ReflectionNotFound();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        '독후감을 찾을 수 없습니다.',
        style: TextStyle(color: AppColors.textMuted),
      ),
    );
  }
}

class _ReflectionLoadError extends StatelessWidget {
  const _ReflectionLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '독후감을 불러오지 못했습니다.',
            style: TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    );
  }
}
