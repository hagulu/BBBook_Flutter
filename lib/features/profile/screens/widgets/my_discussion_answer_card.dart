import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/community_content.dart';
import '../../../discussion/utils/discussion_date.dart';
import '../../models/my_discussion_answer_summary.dart';
import 'my_content_card_layout.dart';

/// "내가 작성한 토론 댓글" 목록 카드(`my-content-screens.md` §5-1).
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
        title: answer.topicTitle != null
            ? Text(
                answer.topicTitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                  color: AppColors.of(context).textStrong,
                ),
              )
            : null,
        content: answer.content != null
            ? Text(
                answer.content!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.of(context).textBody,
                  height: 1.5,
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
