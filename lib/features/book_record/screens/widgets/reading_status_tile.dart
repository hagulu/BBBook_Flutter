import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../bookshelf/models/book_status.dart';
import '../../models/record_labels.dart';

/// 독서 상태 요약 타일. 다른 요약 필드(`RecordFieldTile`)보다 아이콘·글자를
/// 크게 둬서 강조한다 — 책 기록에서 가장 먼저 봐야 하는 정보라서다. 탭하면
/// 상태 선택 팝업을 띄운다.
class ReadingStatusTile extends StatelessWidget {
  const ReadingStatusTile({
    super.key,
    required this.status,
    required this.summary,
    required this.onTap,
  });

  final BookStatus status;
  final String summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.accentLight.withValues(alpha: 0.35),
            child: Icon(status.icon, color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '독서 상태',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.tertiaryText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  summary,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.titleText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
