import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../book_record/models/record_labels.dart';
import '../../providers/bookshelf_providers.dart';

/// 완독 탭 필터 패널(카테고리/태그/걸작/난이도). 옵션은 모두 로컬 DB의
/// 완독 책에서 실제 사용 중인 값만 distinct로 추출한다(서버 카테고리/태그
/// API는 사용하지 않음).
class FinishedFilterPanel extends ConsumerWidget {
  const FinishedFilterPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(finishedFilterProvider);
    final notifier = ref.read(finishedFilterProvider.notifier);
    final categories =
        ref.watch(finishedCategoryOptionsProvider).valueOrNull ?? const [];
    final tags = ref.watch(finishedTagOptionsProvider).valueOrNull ?? const [];
    final difficulties =
        ref.watch(finishedDifficultyOptionsProvider).valueOrNull ?? const [];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (categories.isNotEmpty) ...[
            const _SectionLabel('카테고리'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _FilterChip(
                  label: '전체',
                  selected: filter.category == null,
                  onTap: () => notifier.setCategory(null),
                ),
                for (final category in categories)
                  _FilterChip(
                    label: category,
                    selected: filter.category == category,
                    onTap: () => notifier.setCategory(
                      filter.category == category ? null : category,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          if (tags.isNotEmpty) ...[
            const _SectionLabel('태그'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in tags)
                  _FilterChip(
                    label: '#${tag.name}',
                    selected: filter.tagIds.contains(tag.id),
                    onTap: () => notifier.toggleTag(tag.id),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _FilterChip(
                label: '걸작만 보기',
                selected: filter.masterpieceOnly,
                onTap: () =>
                    notifier.setMasterpieceOnly(!filter.masterpieceOnly),
              ),
              for (final difficulty in difficulties)
                _FilterChip(
                  // 필터 비교/전송에는 저장값(EASY 등)을 그대로 쓰고,
                  // 라벨만 한글로 바꿔 보여준다(저장값에 한글이 섞이지 않도록).
                  label:
                      DifficultyLevel.fromApiValue(difficulty)?.label ??
                      difficulty,
                  selected: filter.difficulty == difficulty,
                  onTap: () => notifier.setDifficulty(
                    filter.difficulty == difficulty ? null : difficulty,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.tertiaryText,
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : AppColors.inputBackground,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : AppColors.tertiaryText,
            ),
          ),
        ),
      ),
    );
  }
}
