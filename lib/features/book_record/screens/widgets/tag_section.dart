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

  late Future<List<BookTag>> _suggestionsFuture;

  @override
  void initState() {
    super.initState();
    _suggestionsFuture = _loadSuggestions();
  }

  Future<List<BookTag>> _loadSuggestions() => ref
      .read(tagSuggestionsProvider.future)
      .onError<Object>((_, _) => const <BookTag>[]);

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
      setState(() => _suggestionsFuture = _loadSuggestions());
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
      if (mounted) setState(() => _suggestionsFuture = _loadSuggestions());
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
                    tag: tag,
                    onDeleted: _submitting ? null : () => _remove(tag),
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
          FutureBuilder<List<BookTag>>(
            future: _suggestionsFuture,
            builder: (context, snapshot) {
              final all = snapshot.data;
              if (all == null) return const SizedBox.shrink();
              if (all.isEmpty) return const SizedBox.shrink();
              final existingNames = existingTags.map((t) => t.name).toSet();
              final queryLower = query.toLowerCase();
              final filtered = all
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
  const _TagChip({required this.tag, this.onDeleted});

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
