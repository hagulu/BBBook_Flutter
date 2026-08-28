import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_bar_title.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/record_dialog_shell.dart';
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
  bool _isSaving = false;

  bool get _isEdit => widget.topic != null;

  /// 닫힌 토론은 본문 수정이 불가능하다(마감일만 상세 화면에서 바꿀 수 있다).
  bool get _isLocked => widget.topic?.isClosed ?? false;

  /// 선택지 토론 여부. 별도 모드 스위치 없이, 값이 채워진 선택지가 하나라도
  /// 있으면 선택지 토론으로 취급한다(툴바의 "선택지 추가"/"선택지 관리"에서
  /// 추가·삭제). 빈 텍스트인 선택지는 없는 것으로 본다 — 빈 채로 남겨두고
  /// 시트를 닫아도 자유 토론 등록을 막지 않는다.
  bool get _useOptions =>
      _optionControllers.any((c) => c.text.trim().isNotEmpty);

  @override
  void initState() {
    super.initState();
    final topic = widget.topic;
    _titleController = TextEditingController(text: topic?.title ?? '');
    _contentController = TextEditingController(text: topic?.content ?? '');
    _isSpoiler = topic?.isSpoiler ?? false;
    _initialOptions = topic?.options.map((o) => o.content).toList() ?? const [];
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
        title: AppBarTitle(_isEdit ? '토론 수정' : '토론 작성'),
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
            child: Text(_isSaving ? '저장 중' : (_isEdit ? '수정' : '등록')),
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
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
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
                      TextField(
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
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          hintText: '토론 주제 제목을 입력하세요',
                          hintStyle: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _contentController,
                        enabled: !_isLocked,
                        minLines: 8,
                        maxLines: 16,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textBody,
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          hintText: '토론 주제를 자세히 작성해보세요...',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _buildKeyboardToolbar(),
          ],
        ),
      ),
    );
  }

  /// 선택지 관리 바텀시트. 원본 상태(`_optionControllers`)를 바로 바꾸지
  /// 않고, 임시(draft) 컨트롤러 목록을 따로 만들어 시트 안에서만 편집한다.
  /// "저장"을 눌러야 원본에 반영되고, 뒤로가기·드래그로 그냥 닫으면 편집한
  /// 내용이 버려진다(잠긴 항목은 draft에도 보이지만 원본 그대로 유지된다).
  /// 시트를 열 때는 항목을 자동으로 추가하지 않는다 — 추가는 항상 제목
  /// 오른쪽의 "+" 버튼으로만 한다(최대 개수 제한도 그 버튼 하나에서만
  /// 지키면 된다). 빈 선택지는 저장 시 자동으로 걸러진다(빈 선택지는
  /// "없는 것"으로 취급 — `_useOptions`).
  Future<void> _openOptionsSheet() async {
    final lockedCount = _initialOptions.length;
    final draftControllers = [
      for (final c in _optionControllers) TextEditingController(text: c.text),
    ];
    final newOptionFocusNode = FocusNode();
    int? autofocusIndex;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final canAdd =
              !_isLocked && draftControllers.length < kMaxDiscussionOptions;
          return RecordDialogShell(
            title: '선택지 관리',
            titleTrailing: IconButton(
              onPressed: canAdd
                  ? () {
                      draftControllers.add(TextEditingController());
                      autofocusIndex = draftControllers.length - 1;
                      setSheetState(() {});
                      // autofocus는 시트 안에 이미 포커스를 가진 입력창이
                      // 있으면 동작하지 않는다(Flutter 기본 동작) — 새 행이
                      // 그려진 다음 프레임에 명시적으로 포커스를 옮긴다.
                      // 이전 입력창에 커서가 남는 문제를 막기 위해 먼저
                      // 명시적으로 포커스를 내린 뒤 새 입력창으로 옮긴다.
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        FocusManager.instance.primaryFocus?.unfocus();
                        if (newOptionFocusNode.canRequestFocus) {
                          newOptionFocusNode.requestFocus();
                        }
                      });
                    }
                  : null,
              tooltip: '선택지 추가',
              visualDensity: VisualDensity.compact,
              icon: const Icon(PhosphorIconsRegular.plus, size: 20),
            ),
            content: DiscussionOptionsEditor(
              controllers: draftControllers,
              lockedCount: lockedCount,
              enabled: !_isLocked,
              autofocusIndex: autofocusIndex,
              autofocusNode: newOptionFocusNode,
              onRemove: (index) {
                if (index < lockedCount) return;
                draftControllers.removeAt(index).dispose();
                setSheetState(() {});
              },
            ),
            buttons: [
              RecordDialogButton(
                label: '저장',
                onPressed: () => Navigator.pop(sheetContext, true),
              ),
            ],
          );
        },
      ),
    );
    newOptionFocusNode.dispose();

    if (saved != true) {
      for (final c in draftControllers) {
        c.dispose();
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      for (final c in _optionControllers.skip(lockedCount)) {
        c.dispose();
      }
      _optionControllers.removeRange(lockedCount, _optionControllers.length);
      for (final c in draftControllers.skip(lockedCount)) {
        if (c.text.trim().isEmpty) {
          c.dispose();
          continue;
        }
        c.addListener(_onFormChanged);
        _optionControllers.add(c);
      }
    });
    // 잠긴 항목의 draft 사본은 원본을 그대로 쓰므로 저장 후엔 필요 없다.
    for (final c in draftControllers.take(lockedCount)) {
      c.dispose();
    }
  }

  /// 스포일러 토글 + 선택지 관리 진입 버튼을 담는 바. 스크롤 영역 밖, `Scaffold`
  /// 하단에 둬서 키보드가 올라오면 그 바로 위에 붙는 입력 보조 툴바처럼
  /// 동작한다(키보드가 닫혀 있으면 화면 맨 아래에 고정).
  Widget _buildKeyboardToolbar() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            _SpoilerToggle(
              isSpoiler: _isSpoiler,
              onTap: _isLocked
                  ? null
                  : () => setState(() => _isSpoiler = !_isSpoiler),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _isLocked ? null : _openOptionsSheet,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accentForeground,
                disabledForegroundColor: AppColors.controlInactive,
              ),
              icon: const Icon(PhosphorIconsRegular.listBullets, size: 16),
              label: Text(
                _useOptions
                    ? '선택지 관리 (${_optionControllers.length}/$kMaxDiscussionOptions)'
                    : '선택지 추가',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
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
