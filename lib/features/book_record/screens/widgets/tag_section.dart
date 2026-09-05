import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/record_dialog_shell.dart';
import '../../../bookshelf/models/book_tag.dart';
import '../../providers/book_record_providers.dart';
import 'pill_option.dart';
import 'record_section_card.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// 책 상세에는 태그명만 간결히 보여주고, 선택/삭제/검색은 태그 관리 시트에서
/// 한 번에 처리한다.
class TagSection extends ConsumerWidget {
  const TagSection({super.key, required this.userBookId, required this.tags});

  final int userBookId;
  final List<BookTag> tags;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: SectionLabel('태그', icon: PhosphorIconsRegular.tag),
            ),
            _AddTagIconButton(onTap: () => _openTagInputSheet(context)),
          ],
        ),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final tag in tags) _TagChip(tag: tag)],
          ),
        ],
      ],
    );
  }

  void _openTagInputSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TagInputSheet(userBookId: userBookId),
    );
  }
}

class _AddTagIconButton extends StatelessWidget {
  const _AddTagIconButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '태그 추가',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          // 시각적 원(28dp)은 그대로 두되, 손 떨림이 있거나 화면이 작은
          // 사용자도 정확히 누를 수 있도록 실제 탭 영역은 권장 최소인
          // 48×48dp로 넓힌다.
          child: const SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surfaceSubtle,
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(
                    PhosphorIconsRegular.plus,
                    size: 16,
                    color: AppColors.accentForeground,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 현재 태그의 삭제, 기존 태그 재사용/검색, 새 태그 생성을 한곳에서 처리한다.
class _TagInputSheet extends ConsumerStatefulWidget {
  const _TagInputSheet({required this.userBookId});

  final int userBookId;

  @override
  ConsumerState<_TagInputSheet> createState() => _TagInputSheetState();
}

class _TagInputSheetState extends ConsumerState<_TagInputSheet> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String? _errorText;
  bool _submitting = false;
  bool _keyboardWasVisible = false;
  // 저장 중에 키보드 인셋이 잠깐 0으로 찍히는 걸 봤다는 표시. 저장이 끝난
  // 뒤에도 키보드가 아직 다시 올라오지 않은 프레임이 있을 수 있어,
  // `_submitting`만으로는 그 프레임에 종료 감지가 다시 걸리는 걸 막지
  // 못한다 — 키보드가 실제로 다시 보일 때까지 억제한다.
  bool _suppressKeyboardClose = false;

  // 추천 태그는 시트를 여는 시점에 한 번만 불러온다. 태그를 추가·삭제할
  // 때마다 서버에서 다시 불러오면 FutureBuilder가 매번 데이터 없는 상태로
  // 리셋되면서 추천 영역이 통째로 사라졌다 다시 채워지는 덜컹거림이
  // 생긴다. 이미 받아둔 목록에서 현재 태그명만 걸러내면 충분하다.
  List<BookTag> _allSuggestions = const [];
  bool _suggestionsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  Future<void> _loadSuggestions() async {
    List<BookTag> result;
    try {
      result = await ref.read(tagSuggestionsProvider.future);
    } catch (_) {
      result = const [];
    }
    if (!mounted) return;
    setState(() {
      _allSuggestions = result;
      _suggestionsLoaded = true;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit(String name, List<BookTag> existingTags) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || _submitting) return;
    if (existingTags.length >= 10) {
      setState(() => _errorText = '태그는 책당 최대 10개까지 추가할 수 있습니다.');
      return;
    }
    if (existingTags.any((t) => t.name == trimmed)) {
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
      _focusNode.requestFocus();
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorText = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _remove(BookTag tag) async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _errorText = null;
    });
    try {
      await ref
          .read(bookRecordControllerProvider(widget.userBookId).notifier)
          .removeTag(tag.id);
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorText = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final existingTags =
        ref
            .watch(bookRecordControllerProvider(widget.userBookId))
            .valueOrNull
            ?.tags ??
        const <BookTag>[];
    final query = _controller.text.trim();
    final atLimit = existingTags.length >= 10;

    // 키보드가 내려가면(사용자가 스와이프나 뒤로가기로 직접 닫은 경우)
    // 시트도 함께 닫는다. 태그 추가 직후 포커스를 다시 잡아 키보드를 유지할
    // 때는 인셋이 0으로 떨어지지 않으므로 여기서 걸리지 않는다.
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    if (bottomInset > 0) {
      // 키보드가 실제로 다시 보였다 — 이제부터는 다음에 내려갈 때 정상
      // 종료 감지를 다시 적용한다.
      _keyboardWasVisible = true;
      _suppressKeyboardClose = false;
    } else if (_keyboardWasVisible) {
      _keyboardWasVisible = false;
      if (_submitting) {
        // 태그 추가 직후 iOS는 완료(done) 액션으로 키보드를 먼저 내렸다가
        // _focusNode.requestFocus()로 다시 올린다. 그 사이에 낀 이 프레임을
        // "사용자가 직접 닫았다"로 오인하지 않도록 표시만 해두고, 저장이
        // 끝난 뒤에도 키보드가 다시 뜨기 전까지는 계속 억제한다.
        _suppressKeyboardClose = true;
      } else if (!_suppressKeyboardClose) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _submitting) return;
          // 바깥(배리어)을 탭해 시트가 이미 스스로 닫히는 중일 때도 포커스가
          // 풀리며 키보드가 내려가 이 콜백이 걸린다. 그때 다시 한번 pop하면
          // 시트 아래의 화면까지 닫혀버리므로, 이 시트 라우트가 여전히
          // 최상단(current)일 때만 닫는다.
          final route = ModalRoute.of(context);
          if (route != null && route.isCurrent) {
            Navigator.of(context).maybePop();
          }
        });
      }
    }

    return RecordDialogShell(
      title: '태그 관리',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '현재 태그',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppColors.textStrong,
            ),
          ),
          const SizedBox(height: 8),
          if (existingTags.isEmpty)
            const Text(
              '적용된 태그가 없습니다.',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in existingTags)
                  _TagChip(
                    key: ValueKey('current-${tag.id}'),
                    tag: tag,
                    onDeleted: () => _remove(tag),
                  ),
              ],
            ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Divider(height: 1, color: AppColors.border),
          ),
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            autofocus: true,
            enabled: !atLimit,
            maxLength: 15,
            buildCounter:
                (
                  context, {
                  required currentLength,
                  required isFocused,
                  maxLength,
                }) => Text(
                  '$currentLength / ${maxLength ?? 15}자',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() => _errorText = null),
            onSubmitted: (name) => _submit(name, existingTags),
            decoration: InputDecoration(
              isDense: true,
              hintText: atLimit ? '태그는 최대 10개까지 추가할 수 있습니다.' : '태그 입력',
              prefixIcon: const Icon(PhosphorIconsRegular.tag, size: 18),
            ),
          ),
          if (_errorText != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _errorText!,
                style: const TextStyle(color: AppColors.error, fontSize: 12),
              ),
            ),
          Builder(
            builder: (context) {
              if (!_suggestionsLoaded || _allSuggestions.isEmpty) {
                return const SizedBox.shrink();
              }
              final existingNames = existingTags.map((t) => t.name).toSet();
              final queryLower = query.toLowerCase();
              final filtered = _allSuggestions
                  .where(
                    (t) =>
                        !existingNames.contains(t.name) &&
                        t.name.toLowerCase().contains(queryLower),
                  )
                  .toList();
              final visible = atLimit
                  ? <BookTag>[]
                  : query.isEmpty
                  ? filtered.take(5).toList()
                  : filtered;
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '추천 태그',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textStrong,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 160),
                      child: SingleChildScrollView(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final tag in visible)
                              PillOption(
                                key: ValueKey('suggestion-${tag.id}'),
                                label: tag.name,
                                icon: PhosphorIconsRegular.plus,
                                selected: false,
                                onTap: () => _submit(tag.name, existingTags),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({super.key, required this.tag, this.onDeleted});

  final BookTag tag;
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: onDeleted == null ? 12 : 4,
        top: 4,
        bottom: 4,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tag.name,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textBody,
            ),
          ),
          if (onDeleted != null)
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
