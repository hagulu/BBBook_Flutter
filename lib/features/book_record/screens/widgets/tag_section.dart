import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../bookshelf/models/book_tag.dart';
import '../../providers/book_record_providers.dart';
import 'pill_option.dart';
import 'record_section_card.dart';

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
  String? _errorText;
  bool _submitting = false;

  /// 태그 입력창에 처음 포커스가 갈 때만 자동완성 제안을 조회한다(불필요한
  /// 서버 호출 방지 — 태그를 건드리지 않는 방문에서는 `GET /api/me/tags`를
  /// 아예 쏘지 않는다).
  Future<List<BookTag>>? _suggestionsFuture;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        _suggestionsFuture ??= ref.read(tagSuggestionsProvider.future);
      }
      setState(() {});
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
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim();
    final showSuggestions = _focusNode.hasFocus && query.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('태그', icon: Icons.sell_outlined),
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
                  prefixIcon: Icon(Icons.sell_outlined, size: 18),
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
        if (showSuggestions && _suggestionsFuture != null)
          FutureBuilder<List<BookTag>>(
            future: _suggestionsFuture,
            builder: (context, snapshot) {
              final all = snapshot.data;
              if (all == null) return const SizedBox.shrink();
              final existingNames = widget.tags.map((t) => t.name).toSet();
              final filtered = all
                  .where(
                    (t) =>
                        !existingNames.contains(t.name) &&
                        t.name.contains(query),
                  )
                  .take(8)
                  .toList();
              if (filtered.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final tag in filtered)
                      PillOption(
                        label: tag.name,
                        icon: Icons.add,
                        selected: false,
                        onTap: () => _submit(tag.name),
                      ),
                  ],
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
        color: AppColors.inputBackground,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.sell_outlined,
            size: 13,
            color: AppColors.tertiaryText,
          ),
          const SizedBox(width: 4),
          Text(
            tag.name,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.bodyText,
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
                    Icons.close,
                    size: 14,
                    color: AppColors.tertiaryText,
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
      color: onPressed == null ? AppColors.border : AppColors.primary,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: const Padding(
          padding: EdgeInsets.all(10),
          child: Icon(Icons.add, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}
