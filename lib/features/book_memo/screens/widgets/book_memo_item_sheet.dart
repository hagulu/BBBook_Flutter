import 'dart:io';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../../core/theme/app_theme.dart';
import '../../models/book_memo.dart';

Future<BookMemoItemDraft?> showBookMemoItemEditor(
  BuildContext context, {
  BookMemoItem? initialItem,
  BookMemoItemDraft? initialDraft,
}) {
  assert(initialItem == null || initialDraft == null);
  return Navigator.of(context).push<BookMemoItemDraft>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _BookMemoItemEditorScreen(
        initialItem: initialItem,
        initialDraft: initialDraft,
      ),
    ),
  );
}

Future<BookMemoItemDraft?> showBookMemoQuickComposer(BuildContext context) {
  return showModalBottomSheet<BookMemoItemDraft>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => const _BookMemoQuickComposer(),
  );
}

class _BookMemoQuickComposer extends StatefulWidget {
  const _BookMemoQuickComposer();

  @override
  State<_BookMemoQuickComposer> createState() => _BookMemoQuickComposerState();
}

class _BookMemoQuickComposerState extends State<_BookMemoQuickComposer> {
  static const _quickTypes = [
    BookMemoItemType.summary,
    BookMemoItemType.thought,
    BookMemoItemType.quote,
  ];

  final _contentController = TextEditingController();
  BookMemoItemType _type = BookMemoItemType.summary;

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final canSave = _contentController.text.trim().isNotEmpty;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final type in _quickTypes)
                          Builder(
                            builder: (context) {
                              final style = _MemoTypeChoiceStyle.of(type);
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
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                labelStyle: TextStyle(
                                  color: style.foreground,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                                onSelected: (_) => setState(() => _type = type),
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
                      maxLines: 3,
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
                    tooltip: '메모 조각 추가',
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
        ),
      ),
    );
  }

  BookMemoItemDraft get _draft => BookMemoItemDraft(
    type: _type,
    content: _contentController.text.trim().isEmpty
        ? null
        : _contentController.text.trim(),
  );

  void _submit() => Navigator.of(context).pop(_draft);

  Future<void> _expand() async {
    final draft = await showBookMemoItemEditor(context, initialDraft: _draft);
    if (!mounted) return;
    Navigator.of(context).pop<BookMemoItemDraft>(draft);
  }
}

class _BookMemoItemEditorScreen extends StatefulWidget {
  const _BookMemoItemEditorScreen({
    required this.initialItem,
    required this.initialDraft,
  });

  final BookMemoItem? initialItem;
  final BookMemoItemDraft? initialDraft;

  @override
  State<_BookMemoItemEditorScreen> createState() =>
      _BookMemoItemEditorScreenState();
}

class _BookMemoItemEditorScreenState extends State<_BookMemoItemEditorScreen> {
  late BookMemoItemType _type;
  late final TextEditingController _contentController;
  late final TextEditingController _startPageController;
  late final TextEditingController _endPageController;
  late final FocusNode _contentFocusNode;
  late bool _isImportant;
  String? _imageUrl;
  String? _pickedImagePath;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final item = widget.initialItem;
    final draft = widget.initialDraft;
    _type = item?.type ?? draft?.type ?? BookMemoItemType.summary;
    _contentController = TextEditingController(
      text: item?.content ?? draft?.content ?? '',
    );
    _startPageController = TextEditingController(
      text: (item?.startPage ?? draft?.startPage)?.toString() ?? '',
    );
    _endPageController = TextEditingController(
      text: (item?.endPage ?? draft?.endPage)?.toString() ?? '',
    );
    _contentFocusNode = FocusNode();
    _isImportant = item?.isImportant ?? draft?.isImportant ?? false;
    _imageUrl = item?.imageUrl ?? draft?.imageUrl;
    _pickedImagePath = draft?.pickedImagePath;
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
    final isPhoto = _type == BookMemoItemType.photo;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          tooltip: '닫기',
          icon: const Icon(PhosphorIconsRegular.x),
        ),
        title: Text(
          widget.initialItem == null ? '메모 작성' : '메모 수정',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.pageBackground,
        foregroundColor: AppColors.textStrong,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _submit,
            style: TextButton.styleFrom(
              backgroundColor: AppColors.accentFill,
              foregroundColor: AppColors.textStrong,
              minimumSize: const Size(58, 36),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: const StadiumBorder(),
              textStyle: const TextStyle(
                fontSize: 14,
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
            onSelected: (type) => setState(() {
              _type = type;
              _errorText = null;
            }),
          ),
          if (isPhoto)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _PhotoPicker(
                imageUrl: _imageUrl,
                pickedImagePath: _pickedImagePath,
                onPick: _pickPhoto,
                onRemove: () => setState(() {
                  _imageUrl = null;
                  _pickedImagePath = null;
                }),
              ),
            ),
          Expanded(
            child: TextField(
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
              decoration: InputDecoration(
                hintText: isPhoto ? '사진에 대한 설명을 남겨보세요.' : '기록할 내용을 입력하세요.',
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
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
          _EditorToolbar(
            startPageController: _startPageController,
            endPageController: _endPageController,
            isImportant: _isImportant,
            onPageChanged: () {
              if (_errorText != null) setState(() => _errorText = null);
            },
            onTapImportant: () => setState(() => _isImportant = !_isImportant),
          ),
        ],
      ),
    );
  }

  Future<void> _pickPhoto() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (file == null || !mounted) return;
      developer.log('[메모 사진 선택] result=SUCCESS');
      setState(() {
        _pickedImagePath = file.path;
        _errorText = null;
      });
    } catch (_) {
      developer.log('[메모 사진 선택] result=FAIL reason=image_picker_error');
      if (mounted) {
        setState(() => _errorText = '사진을 불러오지 못했습니다.');
      }
    }
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
    final content = _contentController.text.trim();
    if (_type != BookMemoItemType.photo && content.isEmpty) {
      setState(() => _errorText = '내용을 입력해 주세요.');
      return;
    }
    if (_type == BookMemoItemType.photo &&
        _pickedImagePath == null &&
        (_imageUrl == null || _imageUrl!.isEmpty)) {
      setState(() => _errorText = '사진을 선택해 주세요.');
      return;
    }

    Navigator.of(context).pop(
      BookMemoItemDraft(
        type: _type,
        startPage: startPage,
        endPage: endPage,
        content: content.isEmpty ? null : content,
        imageUrl: _type == BookMemoItemType.photo ? _imageUrl : null,
        pickedImagePath: _type == BookMemoItemType.photo
            ? _pickedImagePath
            : null,
        isImportant: _isImportant,
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
}

class _EditorToolbar extends StatelessWidget {
  const _EditorToolbar({
    required this.startPageController,
    required this.endPageController,
    required this.isImportant,
    required this.onPageChanged,
    required this.onTapImportant,
  });

  final TextEditingController startPageController;
  final TextEditingController endPageController;
  final bool isImportant;
  final VoidCallback onPageChanged;
  final VoidCallback onTapImportant;

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
          child: Row(
            children: [
              SizedBox(
                width: 76,
                child: _PageInput(
                  controller: startPageController,
                  hintText: '시작',
                  textInputAction: TextInputAction.next,
                  onChanged: onPageChanged,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 5),
                child: Text('–', style: TextStyle(color: AppColors.textMuted)),
              ),
              SizedBox(
                width: 76,
                child: _PageInput(
                  controller: endPageController,
                  hintText: '끝',
                  textInputAction: TextInputAction.done,
                  onChanged: onPageChanged,
                ),
              ),
              const Spacer(),
              const SizedBox(width: 12),
              SizedBox(
                width: 92,
                child: _EditorToolButton(
                  icon: PhosphorIconsRegular.highlighter,
                  label: '중요',
                  foreground: isImportant
                      ? AppColors.memoThoughtForeground
                      : AppColors.textMuted,
                  background: isImportant
                      ? AppColors.memoThoughtSurface
                      : AppColors.surfaceSubtle,
                  selected: isImportant,
                  onTap: onTapImportant,
                ),
              ),
            ],
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
        prefixText: 'p.',
        prefixStyle: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.normal,
        ),
        filled: true,
        fillColor: AppColors.surfaceSubtle,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
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
  const _TypeSelector({required this.selectedType, required this.onSelected});

  final BookMemoItemType selectedType;
  final ValueChanged<BookMemoItemType> onSelected;

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
          for (final type in BookMemoItemType.values)
            Builder(
              builder: (context) {
                final style = _MemoTypeChoiceStyle.of(type);
                final selected = selectedType == type;
                return ChoiceChip(
                  avatar: Icon(style.icon, size: 16, color: style.foreground),
                  label: Text(type.label),
                  selected: selected,
                  showCheckmark: false,
                  selectedColor: style.background,
                  backgroundColor: style.background.withValues(alpha: 0.48),
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
                  onSelected: (_) => onSelected(type),
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
  });

  final IconData icon;
  final String label;
  final Color foreground;
  final Color background;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? foreground : AppColors.border,
          width: selected ? 1.4 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
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
    );
  }
}

class _MemoTypeChoiceStyle {
  const _MemoTypeChoiceStyle({
    required this.icon,
    required this.foreground,
    required this.background,
  });

  final IconData icon;
  final Color foreground;
  final Color background;

  static _MemoTypeChoiceStyle of(BookMemoItemType type) => switch (type) {
    BookMemoItemType.summary => const _MemoTypeChoiceStyle(
      icon: PhosphorIconsRegular.notePencil,
      foreground: AppColors.memoSummaryForeground,
      background: AppColors.memoSummarySurface,
    ),
    BookMemoItemType.quote => const _MemoTypeChoiceStyle(
      icon: PhosphorIconsRegular.quotes,
      foreground: AppColors.memoQuoteForeground,
      background: AppColors.memoQuoteSurface,
    ),
    BookMemoItemType.thought => const _MemoTypeChoiceStyle(
      icon: PhosphorIconsRegular.lightbulb,
      foreground: AppColors.memoThoughtForeground,
      background: AppColors.memoThoughtSurface,
    ),
    BookMemoItemType.photo => const _MemoTypeChoiceStyle(
      icon: PhosphorIconsRegular.imageSquare,
      foreground: AppColors.memoPhotoForeground,
      background: AppColors.memoPhotoSurface,
    ),
  };
}

class _PhotoPicker extends StatelessWidget {
  const _PhotoPicker({
    required this.imageUrl,
    required this.pickedImagePath,
    required this.onPick,
    required this.onRemove,
  });

  final String? imageUrl;
  final String? pickedImagePath;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final hasImage =
        pickedImagePath != null || (imageUrl != null && imageUrl!.isNotEmpty);
    if (!hasImage) {
      return OutlinedButton.icon(
        onPressed: onPick,
        icon: const Icon(PhosphorIconsRegular.imageSquare, size: 19),
        label: const Text('사진 선택'),
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.memoPhotoSurface.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.memoPhotoForeground.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 72,
              height: 72,
              child: _MemoImage(
                imageUrl: imageUrl,
                pickedImagePath: pickedImagePath,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: onPick,
                    icon: const Icon(
                      PhosphorIconsRegular.imageSquare,
                      size: 16,
                    ),
                    label: const Text('변경'),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: onRemove,
                    icon: const Icon(PhosphorIconsRegular.trash, size: 16),
                    label: const Text('제거'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoImage extends StatelessWidget {
  const _MemoImage({required this.imageUrl, required this.pickedImagePath});

  final String? imageUrl;
  final String? pickedImagePath;

  @override
  Widget build(BuildContext context) {
    final localPath =
        pickedImagePath ??
        ((imageUrl != null && !_isRemote(imageUrl!)) ? imageUrl : null);
    if (localPath != null) {
      return Image.file(
        File(_asFilePath(localPath)),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const _ImageError(),
      );
    }
    return Image.network(
      imageUrl!,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const _ImageError(),
    );
  }

  static bool _isRemote(String value) =>
      value.startsWith('http://') || value.startsWith('https://');

  static String _asFilePath(String value) =>
      value.startsWith('file://') ? Uri.parse(value).toFilePath() : value;
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
