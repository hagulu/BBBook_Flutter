import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../bookshelf/models/book_category.dart';
import 'record_dialog_shell.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// 카테고리 선택 팝업 결과. 취소/바깥 탭으로 닫히면 `pop()`이 null을 반환해
/// 값이 그대로 유지되고, "미지정"을 명시적으로 고른 경우와 구분하기 위해
/// [categoryId]가 null이어도 결과 자체는 non-null 래퍼로 감싼다.
class CategorySelection {
  const CategorySelection(this.categoryId);

  final int? categoryId;
}

/// `book_info_edit_dialog.dart`(책 정보 수정)와 `custom_book_dialog.dart`
/// (직접 등록)가 공유하는 카테고리 선택 팝업.
Future<CategorySelection?> showBookCategoryPickerDialog(
  BuildContext context, {
  required List<BookCategory> categories,
  required int? initialCategoryId,
}) {
  return showDialog<CategorySelection>(
    context: context,
    builder: (context) => RecordDialogShell(
      icon: PhosphorIconsRegular.tag,
      title: '카테고리',
      content: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _CategoryChip(
            label: '미지정',
            dotColor: AppColors.mutedIcon,
            selected: initialCategoryId == null,
            onTap: () =>
                Navigator.of(context).pop(const CategorySelection(null)),
          ),
          for (final category in categories)
            _CategoryChip(
              label: category.name,
              dotColor: category.color,
              selected: initialCategoryId == category.id,
              onTap: () => Navigator.of(
                context,
              ).pop(CategorySelection(category.id)),
            ),
        ],
      ),
      buttons: [
        RecordDialogButton(
          label: '취소',
          style: RecordDialogButtonStyle.neutral,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );
}

/// 카테고리 선택 필드 행(라벨 + 현재 값 + 화살표). [categories]가 null이면
/// (목록 로딩 중) 탭을 비활성화한다.
class BookCategoryField extends StatelessWidget {
  const BookCategoryField({
    super.key,
    required this.categories,
    required this.selectedCategoryId,
    required this.onChanged,
  });

  final List<BookCategory>? categories;
  final int? selectedCategoryId;
  final ValueChanged<int?> onChanged;

  Future<void> _pickCategory(BuildContext context) async {
    final result = await showBookCategoryPickerDialog(
      context,
      categories: categories!,
      initialCategoryId: selectedCategoryId,
    );
    if (result != null) onChanged(result.categoryId);
  }

  @override
  Widget build(BuildContext context) {
    BookCategory? selected;
    final list = categories;
    if (list != null) {
      for (final category in list) {
        if (category.id == selectedCategoryId) {
          selected = category;
          break;
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '카테고리',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.tertiaryText,
          ),
        ),
        const SizedBox(height: 4),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: list == null ? null : () => _pickCategory(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            decoration: BoxDecoration(
              color: AppColors.inputBackground,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: selected?.color ?? AppColors.mutedIcon,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    selected?.name ?? '미지정',
                    style: const TextStyle(fontSize: 13, color: AppColors.bodyText),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(
                  PhosphorIconsRegular.caretDown,
                  size: 14,
                  color: AppColors.mutedIcon,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.dotColor,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color dotColor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? dotColor.withValues(alpha: 0.16)
                : AppColors.inputBackground,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? dotColor : Colors.transparent,
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppColors.bodyText : AppColors.tertiaryText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
