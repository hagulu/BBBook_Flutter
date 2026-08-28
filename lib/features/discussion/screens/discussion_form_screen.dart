import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../models/discussion_topic.dart';
import '../providers/discussion_providers.dart';
import '../utils/discussion_poll.dart';
import 'widgets/discussion_options_editor.dart';

/// 토론 주제 작성/수정 화면(웹의 `DiscussionFormPage` 대응).
///
/// 작성 시 마감일 입력은 없다 — 항상 마감일 없이 생성되고, 마감일은 상세
/// 화면의 "마감일 설정/수정" 메뉴에서만 설정한다.
///
/// 작성 성공 시 생성된 주제 ID를, 수정 성공 시 true를 pop 결과로 돌려준다.
class DiscussionFormScreen extends ConsumerStatefulWidget {
  const DiscussionFormScreen._({required this.isbn13, this.topic});

  /// 새 토론 작성.
  factory DiscussionFormScreen.create({required String isbn13}) {
    return DiscussionFormScreen._(isbn13: isbn13);
  }

  /// 기존 토론 수정. 저장된 선택지는 잠기고 새 선택지만 뒤에 추가할 수 있다.
  factory DiscussionFormScreen.edit({required DiscussionTopicDetail topic}) {
    return DiscussionFormScreen._(isbn13: topic.isbn13, topic: topic);
  }

  final String isbn13;
  final DiscussionTopicDetail? topic;

  @override
  ConsumerState<DiscussionFormScreen> createState() =>
      _DiscussionFormScreenState();
}

class _DiscussionFormScreenState extends ConsumerState<DiscussionFormScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  final List<TextEditingController> _optionControllers = [];

  /// 수정 화면에서 잠기는(=이미 저장된) 선택지 내용. append-only 검증 기준이다.
  late final List<String> _initialOptions;

  late bool _isSpoiler;
  late bool _useOptions;
  bool _isSaving = false;

  bool get _isEdit => widget.topic != null;

  /// 닫힌 토론은 본문 수정이 불가능하다(마감일만 상세 화면에서 바꿀 수 있다).
  bool get _isLocked => widget.topic?.isClosed ?? false;

  @override
  void initState() {
    super.initState();
    final topic = widget.topic;
    _titleController = TextEditingController(text: topic?.title ?? '');
    _contentController = TextEditingController(text: topic?.content ?? '');
    _isSpoiler = topic?.isSpoiler ?? false;
    _initialOptions = topic?.options.map((o) => o.content).toList() ?? const [];
    _useOptions = _initialOptions.isNotEmpty;
    for (final content in _initialOptions) {
      _optionControllers.add(TextEditingController(text: content));
    }

    _titleController.addListener(_onFormChanged);
    _contentController.addListener(_onFormChanged);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    for (final controller in _optionControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _onFormChanged() => setState(() {});

  void _toggleMode(bool useOptions) {
    if (_isLocked || useOptions == _useOptions) return;
    setState(() {
      _useOptions = useOptions;
      // 선택지 토론으로 처음 전환하면 빈 선택지 1개를 미리 만들어 준다.
      if (useOptions && _optionControllers.isEmpty) {
        _addOptionController();
      }
    });
  }

  void _addOptionController() {
    final controller = TextEditingController();
    controller.addListener(_onFormChanged);
    _optionControllers.add(controller);
  }

  void _addOption() {
    if (_optionControllers.length >= kMaxDiscussionOptions) return;
    setState(_addOptionController);
  }

  void _removeOption(int index) {
    if (index < _initialOptions.length) return;
    setState(() {
      _optionControllers.removeAt(index).dispose();
    });
  }

  void _moveOption(int index, int delta) {
    final target = index + delta;
    // 잠긴 선택지 영역으로는 옮길 수 없다.
    if (target < _initialOptions.length || target >= _optionControllers.length) {
      return;
    }
    setState(() {
      final controller = _optionControllers.removeAt(index);
      _optionControllers.insert(target, controller);
    });
  }

  List<String> get _currentOptions =>
      _optionControllers.map((c) => c.text.trim()).toList();

  /// 등록/수정 버튼 활성 조건. 제목·본문이 공백이 아니고, 선택지 토론이면 모든
  /// 선택지가 채워져 있고 append-only 제약도 지켜져야 한다.
  bool get _canSubmit {
    if (_isLocked || _isSaving) return false;
    if (_titleController.text.trim().isEmpty) return false;
    if (_contentController.text.trim().isEmpty) return false;
    if (!_useOptions) return true;

    final options = _currentOptions;
    if (options.isEmpty || options.any((o) => o.isEmpty)) return false;
    if (options.length > kMaxDiscussionOptions) return false;
    return isDiscussionOptionsAppendOnly(_initialOptions, options);
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;

    setState(() => _isSaving = true);
    final api = ref.read(discussionApiProvider);
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    final options = _useOptions ? _currentOptions : null;

    try {
      if (_isEdit) {
        final topic = widget.topic!;
        // 새로 추가된 선택지가 있을 때만 options를 함께 보낸다(변경이 없으면
        // 필드를 빼서 기존 선택지를 그대로 유지한다).
        final hasNewOptions =
            options != null && options.length > _initialOptions.length;
        await api.patchTopic(
          topicId: topic.id,
          title: title,
          content: content,
          isSpoiler: _isSpoiler,
          options: hasNewOptions ? options : null,
        );
        if (!mounted) return;
        Navigator.of(context).pop(true);
      } else {
        final createdId = await api.createTopic(
          isbn13: widget.isbn13,
          title: title,
          content: content,
          isSpoiler: _isSpoiler,
          options: options,
        );
        if (!mounted) return;
        Navigator.of(context).pop(createdId);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      AppSnackBar.error(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '토론 수정' : '토론 작성'),
        backgroundColor: AppColors.pageBackground,
        foregroundColor: AppColors.textStrong,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _canSubmit ? _submit : null,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textStrong,
              disabledForegroundColor: AppColors.controlInactive,
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            child: Text(
              _isSaving ? '저장 중' : (_isEdit ? '수정' : '등록'),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isLocked) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.highlightGoldSurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '마감된 토론은 내용을 수정할 수 없습니다.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.memoThoughtForeground,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _titleController,
                      enabled: !_isLocked,
                      maxLength: kMaxDiscussionTitleLength,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(
                          kMaxDiscussionTitleLength,
                        ),
                      ],
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textStrong,
                      ),
                      decoration: const InputDecoration(
                        counterText: '',
                        hintText: '토론 주제 제목을 입력하세요',
                        hintStyle: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _SpoilerToggle(
                    isSpoiler: _isSpoiler,
                    onTap: _isLocked
                        ? null
                        : () => setState(() => _isSpoiler = !_isSpoiler),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _contentController,
                enabled: !_isLocked,
                minLines: 8,
                maxLines: 16,
                style: const TextStyle(fontSize: 14, color: AppColors.textBody),
                decoration: const InputDecoration(
                  hintText: '토론 주제를 자세히 작성해보세요...',
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                '토론 방식',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textStrong,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '자유롭게 의견을 나누거나 최대 $kMaxDiscussionOptions개의 선택지를 함께 제시할 수 있습니다.',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 12),
              _ModeToggle(
                useOptions: _useOptions,
                // 이미 저장된 선택지가 있으면 자유 토론으로 되돌릴 수 없다
                // (선택지 삭제에 해당하므로 서버가 400을 반환한다).
                canChooseFree: !_isLocked && _initialOptions.isEmpty,
                canChooseOptions: !_isLocked,
                onChanged: _toggleMode,
              ),
              if (_useOptions) ...[
                const SizedBox(height: 14),
                DiscussionOptionsEditor(
                  controllers: _optionControllers,
                  lockedCount: _initialOptions.length,
                  enabled: !_isLocked,
                  onAdd: _addOption,
                  onRemove: _removeOption,
                  onMove: _moveOption,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SpoilerToggle extends StatelessWidget {
  const _SpoilerToggle({required this.isSpoiler, required this.onTap});

  final bool isSpoiler;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSpoiler
              ? AppColors.highlightGoldSurface
              : AppColors.surfaceSubtle,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIconsRegular.eyeSlash,
              size: 14,
              color: isSpoiler
                  ? AppColors.memoThoughtForeground
                  : AppColors.textMuted,
            ),
            const SizedBox(width: 5),
            Text(
              '스포일러',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isSpoiler
                    ? AppColors.memoThoughtForeground
                    : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({
    required this.useOptions,
    required this.canChooseFree,
    required this.canChooseOptions,
    required this.onChanged,
  });

  final bool useOptions;
  final bool canChooseFree;
  final bool canChooseOptions;
  final void Function(bool useOptions) onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModeButton(
              label: '자유 토론',
              isSelected: !useOptions,
              onTap: canChooseFree ? () => onChanged(false) : null,
            ),
          ),
          Expanded(
            child: _ModeButton(
              label: '선택지 토론',
              isSelected: useOptions,
              onTap: canChooseOptions ? () => onChanged(true) : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? const [
                  BoxShadow(
                    color: AppColors.shadowSoft,
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: onTap == null
                ? AppColors.controlInactive
                : (isSelected ? AppColors.textStrong : AppColors.textMuted),
          ),
        ),
      ),
    );
  }
}
