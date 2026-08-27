import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/image/screens/shared_image_editor_screen.dart';
import '../../../shared/image/services/image_gallery_picker.dart';
import '../../../shared/widgets/app_loading.dart';
import '../../../shared/widgets/app_confirm.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../book_note/models/book_note.dart';
import '../models/book_reflection.dart';
import '../providers/book_reflection_providers.dart';
import '../services/book_reflection_content_adapter.dart';
import '../services/book_reflection_memo_insert_service.dart';
import '../services/book_reflection_quote_service.dart';
import 'widgets/reflection_image_embed_builder.dart';
import 'widgets/reflection_memo_picker_sheet.dart';
import 'widgets/reflection_title_body_divider.dart';

const _reflectionQuoteLeftSpacing = 14.0;
const _reflectionQuoteRightSpacing = 8.0;
const _reflectionQuoteMarkInset = -6.0;

/// 본문 기본 글자 크기. flutter_quill 기본값(16)은 이 앱의 기록 본문
/// (노트 메모 14)보다 커서 한 단계 줄여 쓴다. `paragraph`를 비워 두면
/// 패키지 기본값이 그대로 적용되므로 `lists`까지 함께 지정해야 목록
/// 줄에서 크기가 되돌아가지 않는다.
const _reflectionBodyTextStyle = TextStyle(
  color: AppColors.textBody,
  fontSize: 15,
  height: 1.15,
);

const bookReflectionQuillStyles = DefaultStyles(
  placeHolder: DefaultTextBlockStyle(
    TextStyle(color: AppColors.textMuted, fontSize: 15, height: 1.5),
    HorizontalSpacing.zero,
    VerticalSpacing.zero,
    VerticalSpacing.zero,
    null,
  ),
  paragraph: DefaultTextBlockStyle(
    _reflectionBodyTextStyle,
    HorizontalSpacing.zero,
    VerticalSpacing.zero,
    VerticalSpacing.zero,
    null,
  ),
  lists: DefaultListBlockStyle(
    _reflectionBodyTextStyle,
    HorizontalSpacing.zero,
    VerticalSpacing(6, 0),
    VerticalSpacing(0, 6),
    null,
    null,
  ),
  quote: DefaultTextBlockStyle(
    TextStyle(
      color: AppColors.reflectionQuoteText,
      fontStyle: FontStyle.italic,
      height: 1.5,
    ),
    HorizontalSpacing(
      _reflectionQuoteLeftSpacing,
      _reflectionQuoteRightSpacing,
    ),
    VerticalSpacing(12, 12),
    VerticalSpacing(1, 1),
    null,
  ),
);

InlineSpan reflectionTextSpanBuilder(
  BuildContext context,
  Node node,
  int nodeOffset,
  String text,
  TextStyle? style,
  GestureRecognizer? recognizer,
) {
  final attributes = node.style.attributes;
  final isStoredUnderline = attributes.containsKey(Attribute.underline.key);
  final isLink = attributes.containsKey(Attribute.link.key);
  final hasComposingUnderline =
      style?.decoration?.contains(TextDecoration.underline) == true;
  var resolvedStyle = style;
  if (hasComposingUnderline && !isStoredUnderline && !isLink) {
    resolvedStyle = style?.copyWith(
      decoration: attributes.containsKey(Attribute.strikeThrough.key)
          ? TextDecoration.lineThrough
          : TextDecoration.none,
    );
  }
  final contentSpan = TextSpan(
    text: text,
    style: resolvedStyle,
    recognizer: recognizer,
    mouseCursor: recognizer == null ? null : SystemMouseCursors.click,
  );
  return contentSpan;
}

/// 인용 표시를 문서 TextSpan과 분리해 IME가 객체 대체 문자(U+FFFC)를
/// 실제 본문으로 오인하지 않도록 한다.
class ReflectionQuillEditor extends StatefulWidget {
  const ReflectionQuillEditor({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.scrollController,
    required this.config,
  });

  final QuillController controller;
  final FocusNode focusNode;
  final ScrollController scrollController;
  final QuillEditorConfig config;

  @override
  State<ReflectionQuillEditor> createState() => _ReflectionQuillEditorState();
}

class _ReflectionQuillEditorState extends State<ReflectionQuillEditor> {
  static const _quoteService = BookReflectionQuoteService();
  final GlobalKey<EditorState> _editorKey = GlobalKey<EditorState>();
  final GlobalKey _stackKey = GlobalKey();
  final ValueNotifier<List<Offset>> _quoteOffsets = ValueNotifier(const []);
  bool _updateScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_scheduleQuoteUpdate);
    widget.scrollController.addListener(_scheduleQuoteUpdate);
    _scheduleQuoteUpdate();
  }

  @override
  void didUpdateWidget(covariant ReflectionQuillEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_scheduleQuoteUpdate);
      widget.controller.addListener(_scheduleQuoteUpdate);
    }
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_scheduleQuoteUpdate);
      widget.scrollController.addListener(_scheduleQuoteUpdate);
    }
    _scheduleQuoteUpdate();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_scheduleQuoteUpdate);
    widget.scrollController.removeListener(_scheduleQuoteUpdate);
    _quoteOffsets.dispose();
    super.dispose();
  }

  void _scheduleQuoteUpdate() {
    if (_updateScheduled) return;
    _updateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScheduled = false;
      if (!mounted) return;
      _updateQuoteOffsets();
    });
  }

  void _updateQuoteOffsets() {
    final editorState = _editorKey.currentState;
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (editorState == null || stackBox == null) return;
    final renderEditor = editorState.renderEditor;
    final offsets = <Offset>[];
    for (final documentOffset in _quoteService.firstQuoteLineOffsets(
      widget.controller.document,
    )) {
      final caret = renderEditor.getLocalRectForCaret(
        TextPosition(offset: documentOffset),
      );
      final global = renderEditor.localToGlobal(caret.topLeft);
      offsets.add(stackBox.globalToLocal(global));
    }
    if (_sameOffsets(offsets, _quoteOffsets.value)) return;
    _quoteOffsets.value = offsets;
  }

  bool _sameOffsets(List<Offset> left, List<Offset> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if ((left[index] - right[index]).distance > 0.1) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: _stackKey,
      clipBehavior: Clip.none,
      children: [
        QuillEditor(
          controller: widget.controller,
          focusNode: widget.focusNode,
          scrollController: widget.scrollController,
          config: widget.config.copyWith(editorKey: _editorKey),
        ),
        Positioned.fill(
          child: ValueListenableBuilder<List<Offset>>(
            valueListenable: _quoteOffsets,
            builder: (context, offsets, _) => Stack(
              clipBehavior: Clip.none,
              children: [
                for (final offset in offsets)
                  Positioned(
                    left:
                        offset.dx -
                        _reflectionQuoteLeftSpacing +
                        _reflectionQuoteMarkInset,
                    top: offset.dy - 6,
                    child: ExcludeSemantics(
                      child: IgnorePointer(
                        child: Text(
                          '“',
                          style: TextStyle(
                            color: AppColors.reflectionTextBlue.withValues(
                              alpha: 0.55,
                            ),
                            fontSize: 28.8,
                            height: 0.9,
                            fontWeight: FontWeight.w700,
                            fontStyle: FontStyle.normal,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class BookReflectionEditorScreen extends ConsumerStatefulWidget {
  const BookReflectionEditorScreen({
    super.key,
    required this.ownerUserId,
    required this.userBookId,
    required this.bookTitle,
    this.reflection,
    this.visibilityOverride,
  });

  final int ownerUserId;
  final int userBookId;
  final String bookTitle;
  final BookReflection? reflection;
  final bool? visibilityOverride;

  @override
  ConsumerState<BookReflectionEditorScreen> createState() =>
      _BookReflectionEditorScreenState();
}

class _BookReflectionEditorScreenState
    extends ConsumerState<BookReflectionEditorScreen> {
  static const _adapter = BookReflectionContentAdapter();
  static const _memoInsertService = BookReflectionMemoInsertService();

  late final TextEditingController _titleController;
  late final QuillController _quillController;
  late final String _initialTitle;
  late final String _initialDocumentJson;
  final FocusNode _editorFocusNode = FocusNode();
  final ScrollController _editorScrollController = ScrollController();
  bool _allowImageDeletion = false;
  bool _isSaving = false;
  bool _allowPop = false;
  bool _isConfirmingPop = false;

  @override
  void initState() {
    super.initState();
    final reflection = widget.reflection;
    _titleController = _NoComposingUnderlineTextController(
      text: reflection?.title ?? '',
    );
    final document = _adapter.fromServerJson(reflection?.contentJson);
    _quillController = QuillController(
      document: document,
      selection: TextSelection.collapsed(
        offset: reflection == null ? 0 : document.length - 1,
      ),
      onReplaceText: _allowTextReplacement,
    );
    _initialTitle = _titleController.text;
    _initialDocumentJson = jsonEncode(
      _quillController.document.toDelta().toJson(),
    );
    if (reflection != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _editorFocusNode.requestFocus();
      });
    }
  }

  /// 삭제 범위가 이미지 embed와 겹치면 막는다 — 어떤 값으로 대체하든(빈
  /// 문자열 삭제·글자 덮어쓰기·붙여넣기·새 이미지 삽입용 Delta 등) 이미지가
  /// 명시적 삭제 경로([_deleteImage]) 없이 사라지는 일을 막기 위해서다.
  /// [data]의 타입은 보지 않는다 — 삭제 범위(length>0)가 이미지를
  /// 포함하는지만 본다. [BookReflectionMemoInsertService]의 프로그램적
  /// 삽입([documentRangeOverlapsImage])과 같은 판정을 재사용해 두 곳이
  /// 어긋나지 않게 한다.
  bool _allowTextReplacement(int index, int length, Object? data) {
    if (_allowImageDeletion) return true;
    return !documentRangeOverlapsImage(_quillController.document, index, length);
  }

  void _deleteImage(QuillController controller, int offset) {
    _allowImageDeletion = true;
    try {
      controller
        ..skipRequestKeyboard = true
        ..replaceText(offset, 1, '', TextSelection.collapsed(offset: offset));
    } finally {
      _allowImageDeletion = false;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _quillController.dispose();
    _editorFocusNode.dispose();
    _editorScrollController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      AppSnackBar.error(context, '제목을 입력해 주세요.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      final document = _quillController.document;
      final reflection = await ref
          .read(bookReflectionRepositoryProvider)
          .save(
            ownerUserId: widget.ownerUserId,
            userBookId: widget.userBookId,
            reflectionId: widget.reflection?.id,
            draft: BookReflectionDraft(
              title: title,
              contentJson: _adapter.toServerJson(document),
              contentText: _adapter.toContentText(document),
              isPublic:
                  widget.visibilityOverride ??
                  widget.reflection?.isPublic ??
                  false,
            ),
          );
      ref.read(bookReflectionSyncVersionProvider.notifier).state++;
      await _popWithoutGuard(reflection.id);
    } catch (_) {
      if (mounted) AppSnackBar.error(context, '독후감을 저장하지 못했습니다.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// 고른 이미지를 로컬 저장소에만 넣고 그 상대 경로를 본문에 꽂는다.
  /// 서버 업로드는 저장 후 push가 맡으므로(오프라인에서도 이미지 첨부가
  /// 가능해야 한다) 여기서는 네트워크를 타지 않는다.
  Future<String?> _pickAndSaveImage(BuildContext context) async {
    final picked = await pickImageFromGallery(imageQuality: 85, maxWidth: 1600);
    if (picked == null || !context.mounted) return null;
    final edited = await openSharedImageEditor(
      context,
      imagePath: picked,
      profile: SharedImageEditorProfile.general,
    );
    if (edited == null || !context.mounted) return null;
    AppLoading.show(context);
    try {
      return await ref
          .read(bookReflectionRepositoryProvider)
          .saveLocalImage(edited);
    } on ApiException catch (error) {
      if (context.mounted) AppSnackBar.error(context, error.message);
      return null;
    } catch (_) {
      if (context.mounted) {
        AppSnackBar.error(context, '이미지를 첨부하지 못했습니다.');
      }
      return null;
    } finally {
      AppLoading.hide();
    }
  }

  Future<void> _insertImage(
    String imageSource,
    QuillController controller,
  ) async {
    final inserted = _memoInsertService.insertImageBlock(
      controller,
      imageSource,
    );
    if (!inserted && mounted) {
      AppSnackBar.error(context, '이미지가 포함된 범위에는 삽입할 수 없습니다.');
    }
  }

  Future<void> _insertMemo() async {
    final selection = _quillController.selection;
    FocusManager.instance.primaryFocus?.unfocus();
    final memo = await showReflectionMemoPickerSheet(
      context,
      ownerUserId: widget.ownerUserId,
      userBookId: widget.userBookId,
    );
    if (memo == null || !mounted) return;

    if (memo.type == BookNoteMemoType.photo) {
      await _insertPhotoMemo(memo, selection);
      return;
    }
    final inserted = _memoInsertService.insert(
      _quillController,
      memo,
      selection: selection,
    );
    if (!inserted) AppSnackBar.error(context, '메모를 삽입하지 못했습니다.');
  }

  /// 사진 확보(네트워크/파일 I/O)가 끝난 뒤에야 [mounted]를 다시 확인하고
  /// 문서를 바꾼다 — 대기 중 화면이 닫혀 [_quillController]가 이미 폐기된
  /// 채로 건드리는 일을 막기 위해서다.
  Future<void> _insertPhotoMemo(
    BookNoteMemo memo,
    TextSelection selection,
  ) async {
    AppLoading.show(context);
    String? imageSource;
    try {
      imageSource = await _memoInsertService.resolvePhotoSource(memo);
    } finally {
      AppLoading.hide();
    }
    if (!mounted) return;
    final inserted =
        imageSource != null &&
        _memoInsertService.insertPhoto(
          _quillController,
          memo,
          imageSource,
          selection: selection,
        );
    if (!inserted) AppSnackBar.error(context, '사진 메모를 불러오지 못했습니다.');
  }

  bool get _hasUnsavedChanges =>
      _titleController.text != _initialTitle ||
      jsonEncode(_quillController.document.toDelta().toJson()) !=
          _initialDocumentJson;

  Future<void> _popWithoutGuard([int? result]) async {
    if (!mounted) return;
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop(result);
  }

  Future<void> _handlePopAttempt(bool didPop) async {
    if (didPop || _allowPop || _isConfirmingPop || !mounted) return;
    if (!_hasUnsavedChanges) {
      await _popWithoutGuard();
      return;
    }
    _isConfirmingPop = true;
    final confirmed = await AppConfirm.show(
      context,
      title: '저장하지 않고 나갈까요?',
      message: '작성한 내용이 저장되지 않습니다.',
      confirmText: '나가기',
      destructive: true,
    );
    _isConfirmingPop = false;
    if (!confirmed || !mounted) return;
    await _popWithoutGuard();
  }

  @override
  Widget build(BuildContext context) {
    final reflectionId = widget.reflection?.id;
    // 이미 저장된 독후감이면 본문의 서버 이미지를 로컬 사본으로 바꿔
    // 보여준다(아직 로드 전이거나 신규 작성이면 서버 URL로 표시).
    final localImagePaths = reflectionId == null
        ? const <String, String>{}
        : ref.watch(reflectionLocalImagesProvider(reflectionId)).value ??
              const <String, String>{};
    return PopScope<int>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) => _handlePopAttempt(didPop),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: Text(
            widget.reflection == null ? '독후감 작성' : '독후감 수정',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          backgroundColor: AppColors.pageBackground,
          foregroundColor: AppColors.textStrong,
          actions: [
            TextButton(
              onPressed: _isSaving ? null : _save,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textStrong,
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              child: Text(_isSaving ? '저장 중' : '저장'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
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
                  clipBehavior: Clip.antiAlias,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // 제목을 화면에 고정하지 않고 본문과 함께 스크롤되게
                      // 하기 위해, Quill 편집기는 자체 스크롤을 끄고
                      // (scrollable: false) 제목·구분선과 한 스크롤뷰를
                      // 공유한다. 커서를 따라가는 자동 스크롤(flutter_quill의
                      // showCaretOnScreen)도 이 공유 컨트롤러가 붙은
                      // 스크롤뷰를 기준으로 동작한다. 편집기 자체 스크롤이
                      // 없어져 Scaffold의 키보드 회피와 중복이던
                      // scrollBottomInset 설정도 함께 제거했다.
                      return SingleChildScrollView(
                        controller: _editorScrollController,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          // 본문이 짧아도 카드 남은 영역 전체를 눌러 편집기에
                          // 포커스를 줄 수 있게 한다(예전 Expanded 채움과
                          // 같은 동작 유지).
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: () {
                              if (!_editorFocusNode.hasFocus) {
                                _editorFocusNode.requestFocus();
                              }
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    18,
                                    12,
                                    18,
                                    0,
                                  ),
                                  child: TextField(
                                    controller: _titleController,
                                    maxLength: 255,
                                    textInputAction: TextInputAction.next,
                                    onSubmitted: (_) =>
                                        _editorFocusNode.requestFocus(),
                                    style: const TextStyle(
                                      color: AppColors.textStrong,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    decoration: const InputDecoration(
                                      hintText: '이 기록에 제목을 붙여보세요',
                                      hintStyle: TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 20,
                                        fontWeight: FontWeight.normal,
                                      ),
                                      counterText: '',
                                      filled: false,
                                      contentPadding: EdgeInsets.zero,
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                    ),
                                  ),
                                ),
                                const ReflectionTitleBodyDivider(
                                  horizontalInset: 18,
                                ),
                                ReflectionQuillEditor(
                                  controller: _quillController,
                                  focusNode: _editorFocusNode,
                                  scrollController: _editorScrollController,
                                  config: QuillEditorConfig(
                                    scrollable: false,
                                    padding: const EdgeInsets.fromLTRB(
                                      18,
                                      0,
                                      18,
                                      16,
                                    ),
                                    placeholder: '책을 읽고 느낀 점을 기록해 보세요.',
                                    customStyles: bookReflectionQuillStyles,
                                    textSpanBuilder: reflectionTextSpanBuilder,
                                    embedBuilders: [
                                      ReflectionImageEmbedBuilder(
                                        localImagePaths: localImagePaths,
                                        onDeleteImage: _deleteImage,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _ReflectionToolbar(
                controller: _quillController,
                editorFocusNode: _editorFocusNode,
                onRequestPickImage: _pickAndSaveImage,
                onImageInsert: _insertImage,
                onPickMemo: _insertMemo,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReflectionToolbar extends StatefulWidget {
  const _ReflectionToolbar({
    required this.controller,
    required this.editorFocusNode,
    required this.onRequestPickImage,
    required this.onImageInsert,
    required this.onPickMemo,
  });

  final QuillController controller;
  final FocusNode editorFocusNode;
  final OnRequestPickImage onRequestPickImage;
  final OnImageInsertCallback onImageInsert;
  final VoidCallback onPickMemo;

  @override
  State<_ReflectionToolbar> createState() => _ReflectionToolbarState();
}

class _ReflectionToolbarState extends State<_ReflectionToolbar> {
  static const _expandDuration = Duration(milliseconds: 180);
  final ScrollController _scrollController = ScrollController();
  bool _attachmentsExpanded = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _toggleAttachments() async {
    final willExpand = !_attachmentsExpanded;
    setState(() => _attachmentsExpanded = willExpand);
    if (!willExpand) return;
    await Future<void>.delayed(_expandDuration);
    if (!mounted || !_scrollController.hasClients) return;
    await _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _insertImage() async {
    final image = await widget.onRequestPickImage(context);
    if (image == null || !mounted) return;
    await widget.onImageInsert(image, widget.controller);
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth - 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _BoldButton(controller: widget.controller),
                _EditorColorButton(
                  controller: widget.controller,
                  editorFocusNode: widget.editorFocusNode,
                  isBackground: false,
                ),
                _EditorColorButton(
                  controller: widget.controller,
                  editorFocusNode: widget.editorFocusNode,
                  isBackground: true,
                ),
                _CyclicBlockFormatButton.header(controller: widget.controller),
                _QuoteGroupButton(controller: widget.controller),
                _CyclicBlockFormatButton.list(controller: widget.controller),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    QuillToolbarIconButton(
                      onPressed: _toggleAttachments,
                      icon: const Icon(
                        PhosphorIconsRegular.paperclip,
                        size: 20,
                      ),
                      isSelected: _attachmentsExpanded,
                      iconTheme: null,
                      tooltip: _attachmentsExpanded ? '첨부 닫기' : '첨부 열기',
                    ),
                    AnimatedSize(
                      duration: _expandDuration,
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.centerLeft,
                      child: _attachmentsExpanded
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                QuillToolbarIconButton(
                                  onPressed: widget.onPickMemo,
                                  icon: const Icon(
                                    PhosphorIconsRegular.notepad,
                                    size: 20,
                                  ),
                                  isSelected: false,
                                  iconTheme: null,
                                  tooltip: '메모 가져오기',
                                ),
                                QuillToolbarIconButton(
                                  onPressed: _insertImage,
                                  icon: const Icon(
                                    PhosphorIconsRegular.image,
                                    size: 20,
                                  ),
                                  isSelected: false,
                                  iconTheme: null,
                                  tooltip: '이미지 첨부',
                                ),
                              ],
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BoldButton extends StatefulWidget {
  const _BoldButton({required this.controller});

  final QuillController controller;

  @override
  State<_BoldButton> createState() => _BoldButtonState();
}

class _BoldButtonState extends State<_BoldButton> {
  bool _isActive = false;

  @override
  void initState() {
    super.initState();
    _isActive = _readIsActive();
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant _BoldButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_handleControllerChanged);
    widget.controller.addListener(_handleControllerChanged);
    _isActive = _readIsActive();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  bool _readIsActive() => widget.controller
      .getSelectionStyle()
      .attributes
      .containsKey(Attribute.bold.key);

  void _handleControllerChanged() {
    final isActive = _readIsActive();
    if (isActive == _isActive || !mounted) return;
    setState(() => _isActive = isActive);
  }

  void _toggle() {
    widget.controller
      ..skipRequestKeyboard = true
      ..formatSelection(
        _isActive ? Attribute.clone(Attribute.bold, null) : Attribute.bold,
      );
  }

  @override
  Widget build(BuildContext context) {
    return QuillToolbarIconButton(
      onPressed: _toggle,
      icon: const Icon(PhosphorIconsRegular.textB, size: 20),
      isSelected: _isActive,
      iconTheme: null,
      tooltip: '굵게',
    );
  }
}

enum _BlockFormatCycle { header, list }

class _QuoteGroupButton extends StatefulWidget {
  const _QuoteGroupButton({required this.controller});

  final QuillController controller;

  @override
  State<_QuoteGroupButton> createState() => _QuoteGroupButtonState();
}

class _QuoteGroupButtonState extends State<_QuoteGroupButton> {
  static const _quoteService = BookReflectionQuoteService();
  bool _isActive = false;

  @override
  void initState() {
    super.initState();
    _isActive = _readIsActive();
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant _QuoteGroupButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_handleControllerChanged);
    widget.controller.addListener(_handleControllerChanged);
    _isActive = _readIsActive();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  bool _readIsActive() => _quoteService.isSelectionInQuote(widget.controller);

  void _handleControllerChanged() {
    final isActive = _readIsActive();
    if (isActive == _isActive || !mounted) return;
    setState(() => _isActive = isActive);
  }

  @override
  Widget build(BuildContext context) {
    return QuillToolbarIconButton(
      onPressed: () => _quoteService.toggle(widget.controller),
      icon: const Icon(PhosphorIconsRegular.quotes, size: 20),
      isSelected: _isActive,
      iconTheme: null,
      tooltip: _isActive ? '인용 묶음 해제' : '인용',
    );
  }
}

class _CyclicBlockFormatButton extends StatefulWidget {
  const _CyclicBlockFormatButton.header({required this.controller})
    : cycle = _BlockFormatCycle.header;

  const _CyclicBlockFormatButton.list({required this.controller})
    : cycle = _BlockFormatCycle.list;

  final QuillController controller;
  final _BlockFormatCycle cycle;

  @override
  State<_CyclicBlockFormatButton> createState() =>
      _CyclicBlockFormatButtonState();
}

class _CyclicBlockFormatButtonState extends State<_CyclicBlockFormatButton> {
  Object? _currentValue;

  @override
  void initState() {
    super.initState();
    _currentValue = _readValue();
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant _CyclicBlockFormatButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_handleControllerChanged);
    widget.controller.addListener(_handleControllerChanged);
    _currentValue = _readValue();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  Object? _readValue() {
    final key = widget.cycle == _BlockFormatCycle.header
        ? Attribute.header.key
        : Attribute.list.key;
    return widget.controller.getSelectionStyle().attributes[key]?.value;
  }

  void _handleControllerChanged() {
    final value = _readValue();
    if (value == _currentValue || !mounted) return;
    setState(() => _currentValue = value);
  }

  void _applyNext() {
    final Attribute<Object?> attribute;
    if (widget.cycle == _BlockFormatCycle.header) {
      attribute = switch (_currentValue) {
        1 => Attribute.h2,
        2 => Attribute.header,
        _ => Attribute.h1,
      };
    } else {
      attribute = switch (_currentValue) {
        'bullet' => Attribute.ol,
        'ordered' => Attribute.list,
        _ => Attribute.ul,
      };
    }
    widget.controller
      ..skipRequestKeyboard = true
      ..formatSelection(attribute);
  }

  @override
  Widget build(BuildContext context) {
    final (icon, tooltip) = widget.cycle == _BlockFormatCycle.header
        ? switch (_currentValue) {
            1 => (PhosphorIconsRegular.textHOne, '제목 1 적용됨'),
            2 => (PhosphorIconsRegular.textHTwo, '제목 2 적용됨'),
            _ => (PhosphorIconsRegular.textH, '제목 서식'),
          }
        : switch (_currentValue) {
            'bullet' => (PhosphorIconsRegular.listBullets, '글머리 목록 적용됨'),
            'ordered' => (PhosphorIconsRegular.listNumbers, '번호 목록 적용됨'),
            _ => (PhosphorIconsRegular.list, '목록 서식'),
          };

    return QuillToolbarIconButton(
      onPressed: _applyNext,
      icon: Icon(icon, size: 20),
      isSelected: _currentValue != null,
      iconTheme: null,
      tooltip: tooltip,
    );
  }
}

class _EditorColorButton extends StatefulWidget {
  const _EditorColorButton({
    required this.controller,
    required this.editorFocusNode,
    required this.isBackground,
  });

  final QuillController controller;
  final FocusNode editorFocusNode;
  final bool isBackground;

  @override
  State<_EditorColorButton> createState() => _EditorColorButtonState();
}

class _EditorColorButtonState extends State<_EditorColorButton> {
  static const _textColors = [
    _EditorColorOption(label: '기본'),
    _EditorColorOption(
      label: '파랑',
      value: '#0061a3',
      color: AppColors.reflectionTextBlue,
    ),
    _EditorColorOption(
      label: '하늘',
      value: '#0ea5e9',
      color: AppColors.reflectionTextSky,
    ),
    _EditorColorOption(
      label: '녹색',
      value: '#16a34a',
      color: AppColors.reflectionTextGreen,
    ),
    _EditorColorOption(
      label: '주황',
      value: '#ea580c',
      color: AppColors.reflectionTextOrange,
    ),
    _EditorColorOption(
      label: '빨강',
      value: '#e03c3c',
      color: AppColors.reflectionTextRed,
    ),
    _EditorColorOption(
      label: '회색',
      value: '#94a3b8',
      color: AppColors.reflectionTextGray,
    ),
  ];

  static const _backgroundColors = [
    _EditorColorOption(label: '없음'),
    _EditorColorOption(
      label: '노랑',
      value: '#fef08a',
      color: AppColors.reflectionHighlightYellow,
    ),
    _EditorColorOption(
      label: '주황',
      value: '#fed7aa',
      color: AppColors.reflectionHighlightOrange,
    ),
    _EditorColorOption(
      label: '분홍',
      value: '#fecdd3',
      color: AppColors.reflectionHighlightPink,
    ),
    _EditorColorOption(
      label: '하늘',
      value: '#bae6fd',
      color: AppColors.reflectionHighlightSky,
    ),
    _EditorColorOption(
      label: '녹색',
      value: '#bbf7d0',
      color: AppColors.reflectionHighlightGreen,
    ),
    _EditorColorOption(
      label: '보라',
      value: '#e9d5ff',
      color: AppColors.reflectionHighlightPurple,
    ),
  ];

  String? _selectedValue;

  List<_EditorColorOption> get _options =>
      widget.isBackground ? _backgroundColors : _textColors;

  @override
  void initState() {
    super.initState();
    _selectedValue = _readSelectedValue();
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant _EditorColorButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_handleControllerChanged);
    widget.controller.addListener(_handleControllerChanged);
    _selectedValue = _readSelectedValue();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    final value = _readSelectedValue();
    if (value == _selectedValue || !mounted) return;
    setState(() => _selectedValue = value);
  }

  String? _readSelectedValue() {
    final key = widget.isBackground
        ? Attribute.background.key
        : Attribute.color.key;
    final value = widget.controller.getSelectionStyle().attributes[key]?.value;
    return value is String ? value.toLowerCase() : null;
  }

  void _apply(String value) {
    final normalized = value.isEmpty ? null : value;
    widget.controller.formatSelection(
      widget.isBackground
          ? BackgroundAttribute(normalized)
          : ColorAttribute(normalized),
    );
    widget.editorFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    _EditorColorOption? selected;
    for (final option in _options) {
      if (option.value == _selectedValue) {
        selected = option;
        break;
      }
    }
    final selectedColor = selected?.color;
    final foreground = selectedColor == null
        ? AppColors.textBody
        : selectedColor.computeLuminance() < 0.45
        ? AppColors.surface
        : AppColors.textStrong;
    final tooltip = widget.isBackground ? '배경색' : '글씨색';

    return PopupMenuButton<String>(
      tooltip: tooltip,
      requestFocus: false,
      onSelected: _apply,
      color: AppColors.surface,
      position: PopupMenuPosition.over,
      offset: const Offset(0, -64),
      itemBuilder: (menuContext) => [
        PopupMenuItem<String>(
          value: _selectedValue ?? '',
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in _options)
                _EditorColorSwatch(
                  option: option,
                  selected: option.value == _selectedValue,
                  onTap: () =>
                      Navigator.of(menuContext).pop(option.value ?? ''),
                ),
            ],
          ),
        ),
      ],
      child: Semantics(
        button: true,
        label: tooltip,
        child: Container(
          width: 38,
          height: 38,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: selectedColor,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(
            widget.isBackground
                ? PhosphorIconsRegular.highlighter
                : PhosphorIconsRegular.textAa,
            size: 20,
            color: foreground,
          ),
        ),
      ),
    );
  }
}

class _EditorColorOption {
  const _EditorColorOption({required this.label, this.value, this.color});

  final String label;
  final String? value;
  final Color? color;
}

class _NoComposingUnderlineTextController extends TextEditingController {
  _NoComposingUnderlineTextController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    return super.buildTextSpan(
      context: context,
      style: style,
      withComposing: false,
    );
  }
}

class _EditorColorSwatch extends StatelessWidget {
  const _EditorColorSwatch({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _EditorColorOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: option.label,
      onTap: onTap,
      child: InkResponse(
        onTap: onTap,
        canRequestFocus: true,
        radius: 20,
        child: Container(
          width: 36,
          height: 36,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? AppColors.accentForeground : AppColors.surface,
              width: 2,
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: option.color ?? AppColors.surface,
              border: Border.all(color: AppColors.border),
            ),
            child: option.color == null
                ? Center(
                    child: Transform.rotate(
                      angle: -0.785398,
                      child: Container(
                        width: 18,
                        height: 2,
                        color: AppColors.reflectionTextRed,
                      ),
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
