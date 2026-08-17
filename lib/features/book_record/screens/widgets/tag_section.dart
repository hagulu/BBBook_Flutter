import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../bookshelf/models/book_tag.dart';
import '../../providers/book_record_providers.dart';
import 'pill_option.dart';
import 'record_section_card.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// 태그 추가/삭제 섹션(자동완성 제안 포함).
class TagSection extends ConsumerStatefulWidget {
  const TagSection({super.key, required this.userBookId, required this.tags});

  final int userBookId;
  final List<BookTag> tags;

  @override
  ConsumerState<TagSection> createState() => _TagSectionState();
}

class _TagSectionState extends ConsumerState<TagSection> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _suggestionsAreaKey = GlobalKey();
  String? _errorText;
  bool _submitting = false;

  /// 추천 목록이 실제로 렌더링된 뒤 한 번만 스크롤하기 위한 플래그. 포커스가
  /// 다시 잡힐 때(아래 리스너)마다 초기화된다.
  bool _hasScrolledForSuggestions = false;

  /// 화면 진입 시 한 번만 조회하는 내 전체 태그(자동완성 후보) 목록. 태그를
  /// 건드리지 않는 방문에서도 즉시 조회되므로, 실패해도 조용히 빈 목록으로
  /// 처리한다 — 그러지 않으면 [FutureBuilder]가 조립되기 전(입력창을 아직
  /// focus하지 않은 상태)에 에러가 아무도 안 듣는 채로 완료되어 처리되지
  /// 않은 비동기 예외로 보고된다.
  late final Future<List<BookTag>> _suggestionsFuture;

  /// 포커스 상태와 별개로 관리하는 추천 목록 표시 여부. blur 즉시 hasFocus가
  /// false가 되면서 추천 목록이 사라지면, 추천 항목을 탭했을 때 그 tap보다
  /// blur가 먼저 처리되어 탭이 씹힐 수 있다 — blur 시 짧게 지연한 뒤에도
  /// 여전히 포커스가 없을 때만 숨겨서 탭 이벤트를 우선 처리한다.
  bool _suggestionsVisible = false;

  @override
  void initState() {
    super.initState();
    _suggestionsFuture = ref
        .read(tagSuggestionsProvider.future)
        .onError<Object>((_, _) => const <BookTag>[]);
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        setState(() {
          _suggestionsVisible = true;
          _hasScrolledForSuggestions = false;
        });
      } else {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted && !_focusNode.hasFocus) {
            setState(() => _suggestionsVisible = false);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || _submitting) return;
    if (widget.tags.any((t) => t.name == trimmed)) {
      setState(() => _errorText = '이미 추가된 태그입니다.');
      return;
    }
    setState(() {
      _submitting = true;
      _errorText = null;
    });
    try {
      await ref
          .read(bookRecordControllerProvider(widget.userBookId).notifier)
          .addTag(trimmed);
      if (!mounted) return;
      _controller.clear();
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorText = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _remove(BookTag tag) async {
    try {
      await ref
          .read(bookRecordControllerProvider(widget.userBookId).notifier)
          .removeTag(tag.id);
    } on ApiException catch (e) {
      if (mounted) AppSnackBar.error(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim();
    // 입력 전(빈 문자열)에도 포커스만 되면 내가 썼던 태그 전체(이미 추가된
    // 것 제외)를 바로 보여준다 — 타이핑은 그 안에서 좁히는 용도.
    final showSuggestions = _suggestionsVisible;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('태그', icon: PhosphorIconsRegular.tag),
        const SizedBox(height: 8),
        if (widget.tags.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in widget.tags)
                _TagChip(tag: tag, onDeleted: () => _remove(tag)),
            ],
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                maxLength: 50,
                onChanged: (_) => setState(() => _errorText = null),
                onSubmitted: _submit,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '태그 추가',
                  counterText: '',
                  prefixIcon: Icon(PhosphorIconsRegular.tag, size: 18),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _AddTagButton(
              onPressed: _submitting ? null : () => _submit(_controller.text),
            ),
          ],
        ),
        if (_errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _errorText!,
              style: const TextStyle(color: AppColors.error, fontSize: 12),
            ),
          ),
        if (showSuggestions)
          FutureBuilder<List<BookTag>>(
            future: _suggestionsFuture,
            builder: (context, snapshot) {
              final all = snapshot.data;
              if (all == null) return const SizedBox.shrink();
              final existingNames = widget.tags.map((t) => t.name).toSet();
              final queryLower = query.toLowerCase();
              final filtered = all
                  .where(
                    (t) =>
                        !existingNames.contains(t.name) &&
                        t.name.toLowerCase().contains(queryLower),
                  )
                  .toList();
              if (filtered.isEmpty) return const SizedBox.shrink();
              // 추천이 실제로 이 프레임에 렌더링된 뒤(고정 지연 타이머 대신)
              // 한 번만 스크롤한다 — 응답이 늦게 와도 화면에 나타난 직후
              // 스크롤되고, 타이핑으로 목록이 좁혀질 때마다 다시 스크롤되지
              // 않는다(포커스가 새로 잡힐 때만 플래그가 초기화된다).
              if (!_hasScrolledForSuggestions) {
                _hasScrolledForSuggestions = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final ctx = _suggestionsAreaKey.currentContext;
                  if (ctx != null && ctx.mounted && _focusNode.hasFocus) {
                    Scrollable.ensureVisible(
                      ctx,
                      alignment: 1.0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                    );
                  }
                });
              }
              // 태그 입력창과 같은 탭 그룹으로 묶어, 추천 항목을 탭해도
              // TextField의 onTapOutside(blur)가 아예 발생하지 않게 한다
              // (blur 지연 숨김은 이 그룹 밖을 탭했을 때를 위한 보조 수단).
              // 스크롤 대상도 섹션 전체가 아니라 이 추천 영역으로 좁혀,
              // 위쪽에 이미 추가된 태그 칩이 많아도 입력창이 화면 밖으로
              // 밀려나지 않게 한다. 높이도 최대 160으로 제한해 누적 태그가
              // 많은 계정에서 스크롤 이동량이 태그 수에 비례해 커지지 않게
              // 하고, 그 안은 자체 스크롤로 전체 후보를 다 볼 수 있게 한다.
              return TextFieldTapRegion(
                child: Padding(
                  key: _suggestionsAreaKey,
                  padding: const EdgeInsets.only(top: 8),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 160),
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final tag in filtered)
                            PillOption(
                              label: tag.name,
                              icon: PhosphorIconsRegular.plus,
                              selected: false,
                              onTap: () => _submit(tag.name),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.tag, required this.onDeleted});

  final BookTag tag;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 12, right: 4, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '#${tag.name}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textBody,
            ),
          ),
          Semantics(
            button: true,
            label: '${tag.name} 태그 삭제',
            child: InkWell(
              onTap: onDeleted,
              borderRadius: BorderRadius.circular(999),
              child: const SizedBox(
                width: 36,
                height: 36,
                child: Center(
                  child: Icon(
                    PhosphorIconsRegular.x,
                    size: 14,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddTagButton extends StatelessWidget {
  const _AddTagButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: onPressed == null ? AppColors.border : AppColors.accentFill,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            PhosphorIconsRegular.plus,
            color: onPressed == null ? Colors.white : AppColors.textStrong,
            size: 18,
          ),
        ),
      ),
    );
  }
}
