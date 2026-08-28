import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../../core/theme/app_theme.dart';
import '../../models/discussion_topic.dart';
import '../../utils/discussion_date.dart';

/// 닫힘/스포일러 등 상태 배지(pill).
class DiscussionBadge extends StatelessWidget {
  const DiscussionBadge({
    super.key,
    required this.icon,
    required this.label,
    required this.foreground,
    required this.background,
  });

  /// 마감된 토론임을 알리는 배지.
  const DiscussionBadge.closed({Key? key})
    : this(
        key: key,
        icon: PhosphorIconsRegular.lock,
        label: '마감',
        foreground: AppColors.textMuted,
        background: AppColors.surfaceSubtle,
      );

  /// 스포일러가 포함된 글임을 알리는 배지.
  const DiscussionBadge.spoiler({Key? key})
    : this(
        key: key,
        icon: PhosphorIconsRegular.eyeSlash,
        label: '스포일러',
        foreground: AppColors.memoThoughtForeground,
        background: AppColors.highlightGoldSurface,
      );

  final IconData icon;
  final String label;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: foreground),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

/// 작성자 아바타 + 닉네임 + 작성일. 상세/답변 카드에서 공유한다.
///
/// 웹의 작성자 팝오버(다른 사용자 완독 책장으로 이동)는 해당 기능이 아직
/// 이관되지 않아 제외한다.
class DiscussionAuthorRow extends StatelessWidget {
  const DiscussionAuthorRow({
    super.key,
    required this.user,
    required this.createdAt,
    this.avatarRadius = 14,
    this.trailing,
    this.showTime = true,
  });

  final DiscussionAuthor user;
  final DateTime createdAt;
  final double avatarRadius;
  final Widget? trailing;

  /// false면 시각 없이 날짜만 보여준다(목록 카드).
  final bool showTime;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        DiscussionAvatar(user: user, radius: avatarRadius),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user.nickname ?? '알 수 없음',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textStrong,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                showTime
                    ? formatDiscussionDateTime(createdAt)
                    : formatDiscussionDate(createdAt),
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class DiscussionAvatar extends StatelessWidget {
  const DiscussionAvatar({super.key, required this.user, this.radius = 14});

  final DiscussionAuthor user;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final url = user.profileImageUrl;
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.accentSurface,
      backgroundImage: url == null || url.isEmpty ? null : NetworkImage(url),
      child: url == null || url.isEmpty
          ? Icon(
              PhosphorIconsRegular.user,
              size: radius,
              color: AppColors.accentForeground,
            )
          : null,
    );
  }
}

/// 공감(하트) 버튼 + 공감 수. 주제/답변이 같은 모양을 공유한다.
class DiscussionLikeButton extends StatelessWidget {
  const DiscussionLikeButton({
    super.key,
    required this.isLiked,
    required this.likeCount,
    required this.onTap,
  });

  final bool isLiked;
  final int likeCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.surfaceSubtle,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isLiked ? PhosphorIconsFill.heart : PhosphorIconsRegular.heart,
              size: 15,
              color: isLiked ? AppColors.error : AppColors.controlInactive,
            ),
            const SizedBox(width: 6),
            Text(
              '공감 $likeCount',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "답변 N개"처럼 섹션을 구분하는 좌측 바 + 라벨.
class DiscussionSectionLabel extends StatelessWidget {
  const DiscussionSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: AppColors.accentFill,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppColors.textStrong,
          ),
        ),
      ],
    );
  }
}
