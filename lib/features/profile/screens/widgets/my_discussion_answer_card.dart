import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/community_content.dart';
import '../../../discussion/utils/discussion_date.dart';
import '../../models/my_discussion_answer_summary.dart';
import 'my_content_card_layout.dart';

/// "내가 작성한 토론 댓글" 목록 카드(`my-content-screens.md` §5-1).
///
/// 다른 3개 화면과 달리 `isHidden`이어도 카드 전체가 항상 탭 가능하다(§5-2).
class MyDiscussionAnswerCard extends StatelessWidget {
  const MyDiscussionAnswerCard({super.key, required this.answer, this.onTap});

  final MyDiscussionAnswerSummary answer;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return CommunityContentCard(
      onTap: onTap,
      child: MyContentCardLayout(
        book: answer.book,
        dateLabel: formatRelativeDiscussionDateTime(answer.createdAt),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (answer.topicTitle != null) ...[
              Text(
                answer.topicTitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textStrong,
                ),
              ),
              const SizedBox(height: 4),
            ],
            if (answer.isHidden)
              const Text(
                '숨김 처리된 댓글입니다.',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
              )
            else if (answer.content != null)
              Text(
                answer.content!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textBody,
                  height: 1.4,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
