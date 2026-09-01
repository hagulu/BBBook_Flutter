import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../bookshelf/models/book_status.dart';
import '../../models/record_labels.dart';

/// 독서 상태 요약 타일. 다른 요약 필드(`RecordFieldTile`)보다 아이콘·글자를
/// 크게 둬서 강조한다 — 책 기록에서 가장 먼저 봐야 하는 정보라서다. 탭하면
/// 상태 선택 팝업을 띄운다.
///
/// 완독 상태([BookStatus.finished])이고 [wantToReread]가 true면 기본
/// 체크 아이콘 대신 채워진 빨강 하트로 "또 볼래요"를 표시한다(공감/좋아요
/// 하트와 같은 아이콘·[AppColors.error] 색 재사용 — 목록/카드나 다른
/// 사용자의 공개 책장에는 노출하지 않고 이 화면 전용).
class ReadingStatusTile extends StatelessWidget {
  const ReadingStatusTile({
    super.key,
    required this.status,
    required this.summary,
    required this.onTap,
    this.wantToReread = false,
  });

  final BookStatus status;
  final String summary;
  final VoidCallback onTap;
  final bool wantToReread;

  @override
  Widget build(BuildContext context) {
    final showWantToRereadHeart = status == BookStatus.finished && wantToReread;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.accentSurface.withValues(alpha: 0.35),
            child: Icon(
              showWantToRereadHeart ? PhosphorIconsFill.heart : status.icon,
              color: showWantToRereadHeart
                  ? AppColors.error
                  : AppColors.accentForeground,
              size: 24,
            ),
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
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  summary,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textStrong,
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
