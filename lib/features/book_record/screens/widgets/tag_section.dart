import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../../shared/widgets/record_dialog_shell.dart';
import '../../../bookshelf/models/book_tag.dart';
import '../../providers/book_record_providers.dart';
import 'pill_option.dart';
import 'record_section_card.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// 태그 목록(삭제 포함) + 라벨 오른쪽 위의 추가 아이콘 버튼. 실제 입력(자동
/// 완성 포함)은 화면에 바로 두지 않고 [_TagInputSheet] 바텀시트에서 받는다
/// — 사용자 확인 사항.
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
            children: [
              for (final tag in tags)
                _TagChip(
                  tag: tag,
                  onDeleted: () => _remove(context, ref, tag),
                ),
            ],
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

  Future<void> _remove(BuildContext context, WidgetRef ref, BookTag tag) async {
    try {
      await ref
          .read(bookRecordControllerProvider(userBookId).notifier)
          .removeTag(tag.id);
    } on ApiException catch (e) {
      if (context.mounted) AppSnackBar.error(context, e.message);
    }
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

/// 태그 추가 바텀시트. 입력창(자동완성 제안 포함)을 키보드 위에 띄워, 태그를
/// 여러 개 이어서 추가할 수 있도록 시트를 닫지 않고 입력창만 비운다.
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

  late final Future<List<BookTag>> _suggestionsFuture = ref
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
      setState(() {});
      _focusNode.requestFocus();
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorText = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final existingTags =
        ref.watch(bookRecordControllerProvider(widget.userBookId)).valueOrNull?.tags ??
        const <BookTag>[];
    final query = _controller.text.trim();

    return RecordDialogShell(
      title: '태그 추가',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            autofocus: true,
            maxLength: 50,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() => _errorText = null),
            onSubmitted: (name) => _submit(name, existingTags),
            decoration: const InputDecoration(
              isDense: true,
              hintText: '태그 추가',
              counterText: '',
              prefixIcon: Icon(PhosphorIconsRegular.tag, size: 18),
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
              final existingNames = existingTags.map((t) => t.name).toSet();
              final queryLower = query.toLowerCase();
              final filtered = all
                  .where(
                    (t) =>
                        !existingNames.contains(t.name) &&
                        t.name.toLowerCase().contains(queryLower),
                  )
                  .toList();
              if (filtered.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 12),
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
                            onTap: () => _submit(tag.name, existingTags),
                          ),
                      ],
                    ),
                  ),
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
