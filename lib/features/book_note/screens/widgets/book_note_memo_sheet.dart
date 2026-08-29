import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/image/screens/shared_image_editor_screen.dart';
import '../../../../shared/widgets/app_alert.dart';
import '../../../../shared/widgets/app_bar_title.dart';
import '../../../../shared/widgets/app_confirm.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../../shared/widgets/record_dialog_shell.dart';
import '../../models/book_note.dart';
import '../../services/note_memo_image_store.dart';
import '../memo_photo_camera_screen.dart';
import 'highlight_text_field.dart';
import 'memo_ocr_capture.dart';

Future<BookNoteMemoDraft?> showBookNoteMemoEditor(
  BuildContext context, {
  BookNoteMemo? initialMemo,
  BookNoteMemoDraft? initialDraft,
}) {
  assert(initialMemo == null || initialDraft == null);
  return Navigator.of(context).push<BookNoteMemoDraft>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _BookNoteMemoEditorScreen(
        initialMemo: initialMemo,
        initialDraft: initialDraft,
      ),
    ),
  );
}

Future<BookNoteMemoDraft?> showBookNoteMemoQuickComposer(BuildContext context) {
  return showModalBottomSheet<BookNoteMemoDraft>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (_) => const _BookNoteMemoQuickComposer(),
  );
}

class _BookNoteMemoQuickComposer extends StatefulWidget {
  const _BookNoteMemoQuickComposer();

  @override
  State<_BookNoteMemoQuickComposer> createState() =>
      _BookNoteMemoQuickComposerState();
}

class _BookNoteMemoQuickComposerState
    extends State<_BookNoteMemoQuickComposer> {
  static const _quickTypes = [
    BookNoteMemoType.summary,
    BookNoteMemoType.thought,
    BookNoteMemoType.quote,
    BookNoteMemoType.photo,
  ];

  final _contentController = TextEditingController();
  BookNoteMemoType _type = BookNoteMemoType.summary;

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _contentController.text.trim().isNotEmpty;
    return RecordDialogSurface(
      horizontalPadding: 16,
      bottomPadding: 12,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const RecordDialogHandle(),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final type in _quickTypes)
                      Builder(
                        builder: (context) {
                          final style = _NoteMemoTypeChoiceStyle.of(type);
                          final selected = _type == type;
                          return ChoiceChip(
                            avatar: Icon(
                              style.icon,
                              size: 16,
                              color: style.foreground,
                            ),
                            label: Text(type.label),
                            selected: selected,
                            showCheckmark: false,
                            selectedColor: style.background,
                            backgroundColor: AppColors.surface,
                            side: BorderSide(
                              color: selected
                                  ? style.foreground
                                  : AppColors.border,
                              width: selected ? 1.3 : 1,
                            ),
                            shape: const StadiumBorder(),
                            visualDensity: const VisualDensity(
                              horizontal: -1,
                              vertical: 1,
                            ),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            labelPadding: const EdgeInsets.only(
                              left: 3,
                              right: 5,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 5,
                            ),
                            labelStyle: TextStyle(
                              color: style.foreground,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            onSelected: (_) => _onTypeSelected(type),
                          );
                        },
                      ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _expand,
                tooltip: '전체 편집 화면으로 확장',
                visualDensity: VisualDensity.compact,
                icon: const Icon(PhosphorIconsRegular.arrowsOut, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _contentController,
                  autofocus: true,
                  minLines: 1,
                  maxLines: 5,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  style: const TextStyle(
                    color: AppColors.textBody,
                    fontSize: 15,
                    height: 1.35,
                  ),
                  decoration: const InputDecoration(
                    hintText: '메모를 빠르게 남겨보세요.',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 10,
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                onPressed: canSave ? _submit : null,
                tooltip: '메모 추가',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 46,
                  height: 46,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.accentFill,
                  disabledBackgroundColor: AppColors.surfaceSubtle,
                  foregroundColor: AppColors.textStrong,
                  disabledForegroundColor: AppColors.controlInactive,
                  shape: const CircleBorder(),
                ),
                icon: const Icon(PhosphorIconsRegular.arrowUp, size: 21),
              ),
            ],
          ),
        ],
      ),
    );
  }

  BookNoteMemoDraft get _draft => BookNoteMemoDraft(
    type: _type,
    content: _contentController.text.trim().isEmpty
        ? null
        : _contentController.text.trim(),
  );

  void _submit() => Navigator.of(context).pop(_draft);

  void _onTypeSelected(BookNoteMemoType type) {
    if (type == BookNoteMemoType.photo) {
      unawaited(_expand(initialType: type));
      return;
    }
    setState(() => _type = type);
  }

  Future<void> _expand({BookNoteMemoType? initialType}) async {
    final initialDraft = initialType == null
        ? _draft
        : BookNoteMemoDraft(
            type: initialType,
            content: _contentController.text.trim().isEmpty
                ? null
                : _contentController.text.trim(),
          );
    final draft = await showBookNoteMemoEditor(
      context,
      initialDraft: initialDraft,
    );
    if (!mounted) return;
    Navigator.of(context).pop<BookNoteMemoDraft>(draft);
  }
}

class _BookNoteMemoEditorScreen extends StatefulWidget {
  const _BookNoteMemoEditorScreen({
    required this.initialMemo,
    required this.initialDraft,
  });

  final BookNoteMemo? initialMemo;
  final BookNoteMemoDraft? initialDraft;

  @override
  State<_BookNoteMemoEditorScreen> createState() =>
      _BookNoteMemoEditorScreenState();
}

class _BookNoteMemoEditorScreenState extends State<_BookNoteMemoEditorScreen> {
  late BookNoteMemoType _type;
  late final MemoHighlightController _contentController;
  late final TextEditingController _startPageController;
  late final TextEditingController _endPageController;
  late final FocusNode _contentFocusNode;

  /// PHOTO 타입 전용 메모 전체 강조 토글. 텍스트 타입은 [_contentController]의
  /// 강조(::hl[[]]) 존재 여부로 강조가 결정되므로 이 값을 쓰지 않는다.
  late bool _photoImportant;

  /// 새로 고른 사진의 임시 경로(아직 저장소로 복사되기 전). null이면
  /// 사진을 바꾸지 않았다는 뜻이다.
  String? _pickedImagePath;

  /// 기존 사진을 지웠는지 여부. 사진 값 자체는 [widget.initialMemo]에만
  /// 있고 이 화면은 "그대로 둠/교체/제거" 의사만 [BookNoteMemoDraft]로
  /// 돌려준다([MemoImageChange]).
  bool _imageRemoved = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final memo = widget.initialMemo;
    final draft = widget.initialDraft;
    _type = memo?.type ?? draft?.type ?? BookNoteMemoType.summary;
    _contentController = MemoHighlightController.fromRaw(
      memo?.content ?? draft?.content,
    );
    _startPageController = TextEditingController(
      text: (memo?.startPage ?? draft?.startPage)?.toString() ?? '',
    );
    _endPageController = TextEditingController(
      text: (memo?.endPage ?? draft?.endPage)?.toString() ?? '',
    );
    _contentFocusNode = FocusNode();
    // isImportant는 원래 타입이 PHOTO일 때만 "메모 전체 강조" 의미를 갖는다.
    // 텍스트 타입 메모(강조는 content의 ::hl[[]]로 별도 관리)의 isImportant를
    // 그대로 물려받으면, 강조가 있던 텍스트 메모를 PHOTO로 전환했을 때 사용자가
    // 켠 적 없는 사진 강조 버튼이 ON으로 보인다.
    _photoImportant = _type == BookNoteMemoType.photo
        ? (memo?.isImportant ?? draft?.isImportant ?? false)
        : false;
    _pickedImagePath = draft?.pickedImagePath;
    if (_type == BookNoteMemoType.photo) _contentController.clearHighlights();
  }

  @override
  void dispose() {
    _contentController.dispose();
    _startPageController.dispose();
    _endPageController.dispose();
    _contentFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPhoto = _type == BookNoteMemoType.photo;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          tooltip: '닫기',
          icon: const Icon(PhosphorIconsRegular.x),
        ),
        title: AppBarTitle(widget.initialMemo == null ? '메모 작성' : '메모 수정'),
        backgroundColor: AppColors.pageBackground,
        foregroundColor: AppColors.textStrong,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _submit,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.accentForeground,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            child: const Text('저장'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _TypeSelector(
            selectedType: _type,
            lockToSelectedType:
                widget.initialMemo?.type == BookNoteMemoType.photo,
            onSelected: (type) {
              setState(() {
                _type = type;
                _errorText = null;
                if (type == BookNoteMemoType.photo) {
                  _contentController.clearHighlights();
                }
              });
              // 신규 작성일 때만 사진 종류를 고르는 즉시 촬영 화면으로
              // 넘어간다 — 수정일 때 기존 사진을 보던 중 실수로 다시
              // 눌러도 카메라가 튀어나오지 않게 한다.
              if (type == BookNoteMemoType.photo &&
                  widget.initialMemo == null) {
                unawaited(_pickPhoto());
              }
            },
          ),
          if (isPhoto)
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.manual,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _PhotoPicker(
                      memo: _imageRemoved ? null : widget.initialMemo,
                      pickedImagePath: _pickedImagePath,
                      onPick: _pickPhoto,
                      onRemove: () => setState(() {
                        _pickedImagePath = null;
                        _imageRemoved = true;
                      }),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const Key('book_note_memo_content_field'),
                      controller: _contentController,
                      focusNode: _contentFocusNode,
                      minLines: 5,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      scrollPadding: const EdgeInsets.only(bottom: 120),
                      style: const TextStyle(
                        color: AppColors.textBody,
                        fontSize: 16,
                        height: 1.6,
                      ),
                      decoration: const InputDecoration(
                        hintText: '사진에 대한 설명이나 기억을 남겨보세요.',
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 8,
                        ),
                      ),
                      onChanged: (_) {
                        if (_errorText != null) {
                          setState(() => _errorText = null);
                        }
                      },
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: TextField(
                key: const Key('book_note_memo_content_field'),
                controller: _contentController,
                focusNode: _contentFocusNode,
                autofocus: true,
                expands: true,
                minLines: null,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(
                  color: AppColors.textBody,
                  fontSize: 16,
                  height: 1.6,
                ),
                decoration: const InputDecoration(
                  hintText: '기록할 내용을 입력하세요.',
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.fromLTRB(20, 20, 20, 24),
                ),
                onChanged: (_) {
                  if (_errorText != null) setState(() => _errorText = null);
                },
              ),
            ),
          if (_errorText != null)
            Container(
              width: double.infinity,
              color: AppColors.surface,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                _errorText!,
                style: const TextStyle(color: AppColors.error, fontSize: 12),
              ),
            ),
          AnimatedBuilder(
            animation: _contentController,
            builder: (context, _) {
              final isPhoto = _type == BookNoteMemoType.photo;
              final toggleEnabled =
                  isPhoto || !_contentController.isBlockedAtSelection;
              return _EditorToolbar(
                startPageController: _startPageController,
                endPageController: _endPageController,
                isActive: isPhoto
                    ? _photoImportant
                    : _contentController.isActiveAtSelection,
                toggleEnabled: toggleEnabled,
                onPageChanged: () {
                  if (_errorText != null) setState(() => _errorText = null);
                },
                onToggleHighlight: toggleEnabled
                    ? () {
                        if (isPhoto) {
                          setState(() => _photoImportant = !_photoImportant);
                        } else {
                          _contentController.toggleAtSelection();
                        }
                      }
                    : null,
                onExtract: _type == BookNoteMemoType.quote ? _scanQuote : null,
                onShowHelp: () => _showHighlightHelp(context),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _pickPhoto() async {
    _contentFocusNode.unfocus();
    final capturedPath = await captureMemoPhoto(context);
    if (capturedPath == null || !mounted) return;
    final editedPath = await openSharedImageEditor(
      context,
      imagePath: capturedPath,
      profile: SharedImageEditorProfile.general,
    );
    if (editedPath == null || !mounted) return;
    setState(() {
      _pickedImagePath = editedPath;
      _imageRemoved = false;
      _errorText = null;
    });
  }

  Future<void> _scanQuote() async {
    _contentFocusNode.unfocus();
    final text = await captureMemoQuoteWithOcr(context);
    if (!mounted || text == null || text.trim().isEmpty) return;
    _insertTextAtSelection(_contentController, text);
    setState(() => _errorText = null);
    _contentFocusNode.requestFocus();
  }

  bool get _hasPhoto {
    if (_pickedImagePath != null) return true;
    return !_imageRemoved && (widget.initialMemo?.hasImage ?? false);
  }

  /// 사진 값을 통째로 되돌려 보내는 대신 "무엇을 바꿨는지"만 알린다 —
  /// 그대로 둔 경우 Repository/DAO가 사진 컬럼을 아예 건드리지 않는다.
  MemoImageChange _imageChangeOf(bool isPhoto) {
    // PHOTO가 아닌 타입으로 저장하면(사진 메모를 글 메모로 바꾼 경우 포함)
    // 사진은 남겨 둘 자리가 없다.
    if (!isPhoto || _imageRemoved) return MemoImageChange.cleared;
    if (_pickedImagePath != null) return MemoImageChange.replaced;
    return MemoImageChange.unchanged;
  }

  void _submit() {
    final startPage = _parsePage(_startPageController.text);
    final endPage = _parsePage(_endPageController.text);
    if (startPage == -1 || endPage == -1) {
      setState(() => _errorText = '쪽수는 1 이상의 숫자로 입력해 주세요.');
      return;
    }
    if (startPage != null && endPage != null && startPage > endPage) {
      setState(() => _errorText = '끝 쪽은 시작 쪽보다 작을 수 없습니다.');
      return;
    }
    final isPhoto = _type == BookNoteMemoType.photo;
    final plainText = _contentController.text.trim();
    if (!isPhoto && plainText.isEmpty) {
      setState(() => _errorText = '내용을 입력해 주세요.');
      return;
    }
    if (isPhoto && !_hasPhoto) {
      AppSnackBar.error(context, '사진을 선택해 주세요.');
      return;
    }
    // 평문을 먼저 trim하면 강조 range가 어긋나므로, ::hl[[]] 마크업으로 직렬화한
    // 뒤에 raw 문자열을 trim한다.
    final content = isPhoto ? plainText : _contentController.toRaw().trim();

    Navigator.of(context).pop(
      BookNoteMemoDraft(
        type: _type,
        startPage: startPage,
        endPage: endPage,
        content: content.isEmpty ? null : content,
        pickedImagePath: isPhoto ? _pickedImagePath : null,
        imageChange: _imageChangeOf(isPhoto),
        isImportant: isPhoto
            ? _photoImportant
            : _contentController.hasHighlight,
      ),
    );
  }

  int? _parsePage(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final parsed = int.tryParse(trimmed);
    if (parsed == null || parsed < 1) return -1;
    return parsed;
  }

  void _showHighlightHelp(BuildContext context) {
    AppAlert.show(
      context,
      title: '강조 사용법',
      message:
          '• 강조를 켜고 작성하면 입력하는 내용이 강조됩니다.\n'
          '• 작성된 텍스트를 선택해서 강조하거나 해제할 수 있습니다.\n'
          '• 강조하며 쓰다가 강조 버튼을 다시 누르면 그 지점부터는 강조 없이 이어 쓸 수 있습니다.\n'
          '• 사진은 사진 메모 전체가 강조됩니다.',
    );
  }
}

void _insertTextAtSelection(TextEditingController controller, String text) {
  final value = controller.value;
  final selection = value.selection;
  final hasValidSelection =
      selection.isValid &&
      selection.start <= value.text.length &&
      selection.end <= value.text.length;
  final start = hasValidSelection ? selection.start : value.text.length;
  final end = hasValidSelection ? selection.end : value.text.length;
  final before = value.text.substring(0, start);
  final after = value.text.substring(end);
  var inserted = text.trim();
  if (before.isNotEmpty && !before.endsWith('\n')) inserted = '\n$inserted';
  if (after.isNotEmpty && !after.startsWith('\n')) inserted = '$inserted\n';

  controller.value = value.copyWith(
    text: '$before$inserted$after',
    selection: TextSelection.collapsed(offset: start + inserted.length),
    composing: TextRange.empty,
  );
}

class _EditorToolbar extends StatelessWidget {
  const _EditorToolbar({
    required this.startPageController,
    required this.endPageController,
    required this.isActive,
    required this.toggleEnabled,
    required this.onPageChanged,
    required this.onToggleHighlight,
    required this.onExtract,
    required this.onShowHelp,
  });

  final TextEditingController startPageController;
  final TextEditingController endPageController;
  final bool isActive;
  final bool toggleEnabled;
  final VoidCallback onPageChanged;
  final VoidCallback? onToggleHighlight;
  final VoidCallback? onExtract;
  final VoidCallback onShowHelp;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final actionWidth = onExtract == null ? 108.0 : 200.0;
              final pageWidth = (constraints.maxWidth - actionWidth).clamp(
                92.0,
                148.0,
              );
              return Row(
                children: [
                  SizedBox(
                    width: pageWidth,
                    child: Row(
                      children: [
                        Expanded(
                          child: _PageInput(
                            controller: startPageController,
                            hintText: '시작',
                            textInputAction: TextInputAction.next,
                            onChanged: onPageChanged,
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            '–',
                            style: TextStyle(color: AppColors.textMuted),
                          ),
                        ),
                        Expanded(
                          child: _PageInput(
                            controller: endPageController,
                            hintText: '끝',
                            textInputAction: TextInputAction.done,
                            onChanged: onPageChanged,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 8),
                  if (onExtract != null) ...[
                    SizedBox(
                      width: 78,
                      child: _EditorToolButton(
                        icon: PhosphorIconsRegular.camera,
                        label: '추출',
                        foreground: AppColors.memoQuoteForeground,
                        background: AppColors.memoQuoteSurface,
                        onTap: onExtract,
                      ),
                    ),
                    const SizedBox(width: 14),
                  ],
                  SizedBox(
                    width: 100,
                    height: 48,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 78,
                          child: _EditorToolButton(
                            icon: PhosphorIconsRegular.highlighter,
                            label: '강조',
                            foreground: isActive
                                ? AppColors.highlightGold
                                : AppColors.textMuted,
                            background: isActive
                                ? AppColors.highlightGoldSurface
                                : AppColors.surfaceSubtle,
                            selected: isActive,
                            enabled: toggleEnabled,
                            onTap: onToggleHighlight,
                          ),
                        ),
                        const SizedBox(width: 2),
                        SizedBox(
                          width: 20,
                          child: IconButton(
                            onPressed: onShowHelp,
                            tooltip: '강조 사용법',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 20,
                              height: 48,
                            ),
                            icon: const Icon(
                              PhosphorIconsRegular.info,
                              size: 18,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PageInput extends StatelessWidget {
  const _PageInput({
    required this.controller,
    required this.hintText,
    required this.textInputAction,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final TextInputAction textInputAction;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      textInputAction: textInputAction,
      textAlign: TextAlign.center,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(
        color: AppColors.textBody,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Align(
          alignment: Alignment.centerRight,
          widthFactor: 1,
          heightFactor: 1,
          child: Padding(
            padding: EdgeInsets.only(left: 3),
            child: Text(
              'p.',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 18, minHeight: 0),
        hintStyle: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.normal,
        ),
        filled: true,
        fillColor: AppColors.surfaceSubtle,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.accentForeground),
        ),
      ),
      onChanged: (_) => onChanged(),
    );
  }
}

class _TypeSelector extends StatelessWidget {
  const _TypeSelector({
    required this.selectedType,
    required this.onSelected,
    this.lockToSelectedType = false,
  });

  final BookNoteMemoType selectedType;
  final ValueChanged<BookNoteMemoType> onSelected;
  final bool lockToSelectedType;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final type in BookNoteMemoType.values)
            Builder(
              builder: (context) {
                final style = _NoteMemoTypeChoiceStyle.of(type);
                final selected = selectedType == type;
                final enabled = !lockToSelectedType || selected;
                return Opacity(
                  opacity: enabled ? 1 : 0.38,
                  child: ChoiceChip(
                    avatar: Icon(style.icon, size: 16, color: style.foreground),
                    label: Text(type.label),
                    selected: selected,
                    showCheckmark: false,
                    selectedColor: style.background,
                    backgroundColor: style.background.withValues(alpha: 0.48),
                    disabledColor: style.background.withValues(alpha: 0.32),
                    side: BorderSide(
                      color: selected ? style.foreground : AppColors.border,
                      width: selected ? 1.5 : 1,
                    ),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 7,
                    ),
                    labelStyle: TextStyle(
                      color: style.foreground,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    onSelected: enabled ? (_) => onSelected(type) : null,
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _EditorToolButton extends StatelessWidget {
  const _EditorToolButton({
    required this.icon,
    required this.label,
    required this.foreground,
    required this.background,
    required this.onTap,
    this.selected = false,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final Color foreground;
  final Color background;
  final VoidCallback? onTap;
  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: background,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? foreground : AppColors.border,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: InkWell(
          onTap: enabled ? onTap : null,
          customBorder: const StadiumBorder(),
          // 본문 TextField가 포커스/키보드를 유지한 채로 강조를 토글할 수 있도록,
          // 이 버튼이 포커스를 가져가지 않게 한다.
          canRequestFocus: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: foreground),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoteMemoTypeChoiceStyle {
  const _NoteMemoTypeChoiceStyle({
    required this.icon,
    required this.foreground,
    required this.background,
  });

  final IconData icon;
  final Color foreground;
  final Color background;

  static _NoteMemoTypeChoiceStyle of(BookNoteMemoType type) => switch (type) {
    BookNoteMemoType.summary => const _NoteMemoTypeChoiceStyle(
      icon: PhosphorIconsRegular.notePencil,
      foreground: AppColors.memoSummaryForeground,
      background: AppColors.memoSummarySurface,
    ),
    BookNoteMemoType.quote => const _NoteMemoTypeChoiceStyle(
      icon: PhosphorIconsRegular.quotes,
      foreground: AppColors.memoQuoteForeground,
      background: AppColors.memoQuoteSurface,
    ),
    BookNoteMemoType.thought => const _NoteMemoTypeChoiceStyle(
      icon: PhosphorIconsRegular.lightbulb,
      foreground: AppColors.memoThoughtForeground,
      background: AppColors.memoThoughtSurface,
    ),
    BookNoteMemoType.photo => const _NoteMemoTypeChoiceStyle(
      icon: PhosphorIconsRegular.imageSquare,
      foreground: AppColors.memoPhotoForeground,
      background: AppColors.memoPhotoSurface,
    ),
  };
}

class _PhotoPicker extends StatefulWidget {
  const _PhotoPicker({
    required this.memo,
    required this.pickedImagePath,
    required this.onPick,
    required this.onRemove,
  });

  /// 이미 저장된 사진의 출처(로컬 사본 우선). 사진을 지웠거나 새로 만드는
  /// 메모면 null이다.
  final BookNoteMemo? memo;
  final String? pickedImagePath;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  State<_PhotoPicker> createState() => _PhotoPickerState();
}

class _PhotoPickerState extends State<_PhotoPicker> {
  bool _showActions = false;

  @override
  Widget build(BuildContext context) {
    final hasImage =
        widget.pickedImagePath != null || (widget.memo?.hasImage ?? false);
    if (!hasImage) {
      return SizedBox(
        width: double.infinity,
        height: 76,
        child: OutlinedButton.icon(
          onPressed: widget.onPick,
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            side: const BorderSide(color: AppColors.border),
          ),
          icon: const Icon(PhosphorIconsRegular.camera, size: 22),
          label: const Text(
            '사진 추가',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      label: '선택한 사진',
      hint: '두 번 탭하면 사진 변경과 삭제 버튼이 표시됩니다.',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _showActions = !_showActions),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 240,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: AppColors.mediaBackdrop),
                _MemoImage(
                  memo: widget.memo,
                  pickedImagePath: widget.pickedImagePath,
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: _showActions
                      ? ColoredBox(
                          key: const ValueKey('photo-actions'),
                          color: AppColors.mediaBackdrop.withValues(
                            alpha: 0.52,
                          ),
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _PhotoOverlayAction(
                                  icon: PhosphorIconsRegular.camera,
                                  label: '변경',
                                  foregroundColor: AppColors.textStrong,
                                  onPressed: () {
                                    setState(() => _showActions = false);
                                    widget.onPick();
                                  },
                                ),
                                const SizedBox(width: 28),
                                _PhotoOverlayAction(
                                  icon: PhosphorIconsRegular.trash,
                                  label: '삭제',
                                  foregroundColor: AppColors.error,
                                  onPressed: () async {
                                    final confirmed = await AppConfirm.show(
                                      context,
                                      title: '사진을 삭제할까요?',
                                      message: '선택한 사진이 메모에서 제거됩니다.',
                                      confirmText: '삭제',
                                      destructive: true,
                                    );
                                    if (!mounted || !confirmed) return;
                                    setState(() => _showActions = false);
                                    widget.onRemove();
                                  },
                                ),
                              ],
                            ),
                          ),
                        )
                      : const SizedBox.shrink(
                          key: ValueKey('photo-actions-hidden'),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoOverlayAction extends StatelessWidget {
  const _PhotoOverlayAction({
    required this.icon,
    required this.label,
    required this.foregroundColor,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color foregroundColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filled(
          onPressed: onPressed,
          tooltip: '사진 $label',
          constraints: const BoxConstraints.tightFor(width: 64, height: 64),
          style: IconButton.styleFrom(
            backgroundColor: AppColors.surface,
            foregroundColor: foregroundColor,
          ),
          icon: Icon(icon, size: 28),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.surface,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// 표시 우선순위: 방금 고른 사진 → 로컬 사본 → 서버 URL.
class _MemoImage extends StatelessWidget {
  const _MemoImage({required this.memo, required this.pickedImagePath});

  final BookNoteMemo? memo;
  final String? pickedImagePath;

  @override
  Widget build(BuildContext context) {
    final picked = pickedImagePath;
    if (picked != null) {
      return Image.file(
        File(picked),
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const _ImageError(),
      );
    }
    final localFile = noteMemoImageStore.resolveSync(memo?.localImagePath);
    if (localFile != null) {
      return Image.file(
        localFile,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => _remote(),
      );
    }
    return _remote();
  }

  Widget _remote() {
    final imageUrl = memo?.imageUrl;
    if (imageUrl == null ||
        !(imageUrl.startsWith('http://') || imageUrl.startsWith('https://'))) {
      return const _ImageError();
    }
    return Image.network(
      imageUrl,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => const _ImageError(),
    );
  }
}

class _ImageError extends StatelessWidget {
  const _ImageError();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.surfaceSubtle,
      child: Center(
        child: Icon(
          PhosphorIconsRegular.imageSquare,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}
