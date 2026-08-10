import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../bookshelf/models/book_status.dart';
import '../../models/record_labels.dart';

/// 독서 상태 5종 선택 UI. 아이콘 없이 텍스트만으로 구성한 세그먼트 형태 —
/// 선택된 항목은 primary 배경 + 흰 굵은 글씨로, 나머지는 옅은 배경으로 대비를 준다.
class ReadingStatusSelector extends StatelessWidget {
  const ReadingStatusSelector({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final BookStatus selected;
  final ValueChanged<BookStatus> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final status in BookStatus.values) ...[
          if (status != BookStatus.values.first) const SizedBox(width: 6),
          Expanded(
            child: _StatusSegment(
              label: status.label,
              selected: status == selected,
              onTap: () => onSelected(status),
            ),
          ),
        ],
      ],
    );
  }
}

class _StatusSegment extends StatelessWidget {
  const _StatusSegment({
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
      child: Material(
        color: selected ? AppColors.primary : AppColors.inputBackground,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: Center(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                    color: selected ? Colors.white : AppColors.tertiaryText,
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
