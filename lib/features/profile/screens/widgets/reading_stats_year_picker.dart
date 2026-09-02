import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/record_dialog_shell.dart';

/// [ReadingStatsYearPicker]의 바텀시트 결과. "전체"도 명시적으로 고른
/// 선택이므로 [year]가 null이어도 non-null 래퍼로 감싸, 뒤로 가기·바깥
/// 탭으로 시트만 닫힌 경우(콜백의 `result`가 진짜 `null`)와 구분한다 —
/// `book_category_field.dart`의 `CategorySelection`과 같은 관례.
class _YearSelection {
  const _YearSelection(this.year);

  final int? year;
}

/// 연도 선택 알약 드롭다운(`stats-screen.md` §1-2). 탭하면 바텀시트로
/// "전체" + [years] 중 하나를 고른다.
class ReadingStatsYearPicker extends StatelessWidget {
  const ReadingStatsYearPicker({
    super.key,
    required this.years,
    required this.selectedYear,
    required this.onChanged,
  });

  final List<int> years;
  final int? selectedYear;
  final ValueChanged<int?> onChanged;

  Future<void> _pick(BuildContext context) async {
    final result = await showModalBottomSheet<_YearSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => RecordDialogShell(
        title: '연도',
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _YearChip(
              label: '전체',
              selected: selectedYear == null,
              onTap: () =>
                  Navigator.of(context).pop(const _YearSelection(null)),
            ),
            for (final year in years)
              _YearChip(
                label: '$year년',
                selected: selectedYear == year,
                onTap: () => Navigator.of(context).pop(_YearSelection(year)),
              ),
          ],
        ),
      ),
    );
    // result == null은 선택 없이 시트가 닫힌 경우(뒤로 가기·바깥 탭)라
    // 아무 것도 바꾸지 않는다. "전체"를 고르면 result.year가 null이다.
    if (result != null && result.year != selectedYear) {
      onChanged(result.year);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentLabel = selectedYear == null ? '전체' : '$selectedYear년';
    return Semantics(
      button: true,
      label: '연도 선택, 현재 $currentLabel',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => _pick(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.accentSurface,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                currentLabel,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accentForeground,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                PhosphorIconsRegular.caretDown,
                size: 14,
                color: AppColors.accentForeground,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _YearChip extends StatelessWidget {
  const _YearChip({
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
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? AppColors.accentFill : AppColors.surfaceSubtle,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? AppColors.textStrong : AppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
