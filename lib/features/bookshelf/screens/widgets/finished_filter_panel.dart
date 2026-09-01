import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../book_record/models/record_labels.dart';
import '../../providers/bookshelf_providers.dart';

/// 완독 탭 필터 패널(명작/카테고리/태그/난이도). 명작은 항상 맨 위, 난이도는
/// [DifficultyLevel] 3종 고정 노출이고, 카테고리/태그는 로컬 DB의 완독 책에서
/// 실제 사용 중인 값만 distinct로 추출한다(서버 카테고리/태그 API는 사용 안 함).
///
/// `RecordDialogShell`의 바텀시트 콘텐츠로 쓰이므로 자체 표면(배경·모서리)은
/// 갖지 않는다.
class FinishedFilterPanel extends ConsumerWidget {
  const FinishedFilterPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(finishedFilterProvider);
    final notifier = ref.read(finishedFilterProvider.notifier);
    final categories =
        ref.watch(finishedCategoryOptionsProvider).valueOrNull ?? const [];
    final tags = ref.watch(finishedTagOptionsProvider).valueOrNull ?? const [];
    final categoryColors = {
      for (final category
          in ref.watch(bookCategoriesProvider).valueOrNull ?? const [])
        category.name: category.color,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _FilterChip(
              label: '명작',
              selected: filter.masterpieceOnly,
              selectedColor: AppColors.highlightGold,
              selectedTextColor: AppColors.textStrong,
              selectedBorderColor: null,
              leading: Icon(
                filter.masterpieceOnly
                    ? PhosphorIconsFill.crown
                    : PhosphorIconsRegular.crown,
                size: 14,
                color: filter.masterpieceOnly
                    ? AppColors.textStrong
                    : AppColors.textMuted,
              ),
              onTap: () => notifier.setMasterpieceOnly(!filter.masterpieceOnly),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (categories.isNotEmpty) ...[
          const _SectionLabel('카테고리'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _FilterChip(
                label: '전체',
                selected: filter.categories.isEmpty,
                onTap: notifier.clearCategories,
              ),
              for (final category in categories)
                _FilterChip(
                  label: category,
                  selected: filter.categories.contains(category),
                  leading: _CategoryColorDot(
                    color:
                        categoryColors[category] ?? AppColors.controlInactive,
                  ),
                  onTap: () => notifier.toggleCategory(category),
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
        const _SectionLabel('난이도'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _FilterChip(
              label: '전체',
              selected: filter.difficulty == null,
              onTap: () => notifier.setDifficulty(null),
            ),
            for (final level in DifficultyLevel.values)
              _FilterChip(
                label: level.label,
                selected: filter.difficulty == level.apiValue,
                onTap: () => notifier.setDifficulty(level.apiValue),
              ),
          ],
        ),
      ],
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
        color: AppColors.textMuted,
      ),
    );
  }
}

class _CategoryColorDot extends StatelessWidget {
  const _CategoryColorDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.leading,
    this.selectedColor = AppColors.accentFill,
    this.selectedTextColor = AppColors.textStrong,
    this.selectedBorderColor = AppColors.accentForeground,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? leading;
  final Color selectedColor;
  final Color selectedTextColor;
  final Color? selectedBorderColor;

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
            color: selected ? selectedColor : AppColors.surfaceSubtle,
            borderRadius: BorderRadius.circular(999),
            // 밝은 선택 배경은 보더를 함께 써서 상태를 명확히 구분한다.
            border: selected && selectedBorderColor != null
                ? Border.all(color: selectedBorderColor!, width: 1.2)
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 6)],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? selectedTextColor : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
