import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../core/theme/app_theme.dart';
import 'record_dialog_shell.dart';

/// 책 기반 커뮤니티 목록의 섹션 제목과 우측 제어 영역.
class CommunityContentListHeader extends StatelessWidget {
  const CommunityContentListHeader({
    super.key,
    required this.title,
    this.trailing,
  });

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppColors.textStrong,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// 토론과 공개 독후감의 목록·상세 카드가 공유하는 표면과 터치 피드백.
class CommunityContentCard extends StatelessWidget {
  const CommunityContentCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 16,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(borderRadius),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(borderRadius),
              child: content,
            ),
    );
  }
}

enum CommunityAuthorLayout { inline, stacked }

/// 커뮤니티 콘텐츠의 작성자 아바타·닉네임·작성일 규격.
class CommunityAuthorRow extends StatelessWidget {
  const CommunityAuthorRow({
    super.key,
    required this.nickname,
    required this.profileImageUrl,
    required this.dateLabel,
    this.avatarRadius = 12,
    this.layout = CommunityAuthorLayout.inline,
    this.trailing,
  });

  final String? nickname;
  final String? profileImageUrl;
  final String dateLabel;
  final double avatarRadius;
  final CommunityAuthorLayout layout;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final normalizedNickname = nickname?.trim();
    final nicknameText = Text(
      normalizedNickname?.isNotEmpty == true ? normalizedNickname! : '알 수 없음',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textStrong,
      ),
    );
    final dateText = Text(
      dateLabel,
      style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
    );

    return Row(
      children: [
        _CommunityAvatar(imageUrl: profileImageUrl, radius: avatarRadius),
        const SizedBox(width: 8),
        Expanded(
          child: layout == CommunityAuthorLayout.inline
              ? Row(
                  children: [
                    Flexible(child: nicknameText),
                    const SizedBox(width: 6),
                    const Text(
                      '·',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(width: 6),
                    dateText,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [nicknameText, const SizedBox(height: 2), dateText],
                ),
        ),
        ?trailing,
      ],
    );
  }
}

/// 커뮤니티 상세의 상태 배지·제목·작성자·액션·메타 정보 헤더.
///
/// 본문 렌더러는 기능별로 유지하고, 본문 위 정보 구조만 같은 규격으로 맞춘다.
class CommunityContentHeader extends StatelessWidget {
  const CommunityContentHeader({
    super.key,
    required this.title,
    required this.nickname,
    required this.profileImageUrl,
    required this.dateLabel,
    this.badges = const [],
    this.trailing,
    this.metadata,
  });

  final String title;
  final String? nickname;
  final String? profileImageUrl;
  final String dateLabel;
  final List<Widget> badges;

  /// 헤더 맨 아래 줄(마감일 등 [metadata]가 있으면 그 오른쪽, 없으면 작성자
  /// 행 오른쪽) 붙는 메뉴/신고 버튼 등.
  final Widget? trailing;
  final Widget? metadata;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (badges.isNotEmpty) ...[
          Wrap(spacing: 6, runSpacing: 6, children: badges),
          const SizedBox(height: 8),
        ],
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Text(
            title,
            style: const TextStyle(
              color: AppColors.textStrong,
              fontSize: 19,
              height: 1.35,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 8),
        CommunityAuthorRow(
          nickname: nickname,
          profileImageUrl: profileImageUrl,
          dateLabel: dateLabel,
          avatarRadius: 14,
          layout: CommunityAuthorLayout.stacked,
          trailing: metadata == null ? trailing : null,
        ),
        if (metadata != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: metadata!),
              ?trailing,
            ],
          ),
        ],
      ],
    );
  }
}

class _CommunityAvatar extends StatelessWidget {
  const _CommunityAvatar({required this.imageUrl, required this.radius});

  final String? imageUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final normalizedUrl = imageUrl?.trim();
    final hasImage = normalizedUrl?.isNotEmpty == true;
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.accentSurface,
      backgroundImage: hasImage ? NetworkImage(normalizedUrl!) : null,
      child: hasImage
          ? null
          : Icon(
              PhosphorIconsRegular.user,
              size: radius,
              color: AppColors.accentForeground,
            ),
    );
  }
}

/// 새로고침 동작을 유지하는 커뮤니티 빈 목록 화면.
class CommunityContentEmptyList extends StatelessWidget {
  const CommunityContentEmptyList({
    super.key,
    required this.message,
    required this.scrollController,
    required this.onRefresh,
  });

  final String message;
  final ScrollController scrollController;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Center(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.textMuted),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class CommunityContentErrorState extends StatelessWidget {
  const CommunityContentErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              style: const TextStyle(color: AppColors.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: const Text('다시 시도')),
          ],
        ),
      ),
    );
  }
}

class CommunityContentLoadingState extends StatelessWidget {
  const CommunityContentLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class CommunityContentPageLoader extends StatelessWidget {
  const CommunityContentPageLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Text(
          '불러오는 중...',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      ),
    );
  }
}

/// 상세 콘텐츠를 넓은 화면에서도 읽기 좋은 폭으로 제한한다.
class CommunityContentWidth extends StatelessWidget {
  const CommunityContentWidth({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 40),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: child,
        ),
      ),
    );
  }
}

/// 커뮤니티 콘텐츠와 의견에서 공유하는 공감 버튼.
class CommunityLikeButton extends StatelessWidget {
  const CommunityLikeButton({
    super.key,
    required this.isLiked,
    required this.likeCount,
    required this.onTap,
  });

  final bool isLiked;
  final int likeCount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onTap != null;
    return Semantics(
      button: true,
      enabled: isEnabled,
      toggled: isLiked,
      label: '공감 $likeCount개',
      child: ExcludeSemantics(
        child: Opacity(
          opacity: isEnabled ? 1 : 0.65,
          child: Material(
            color: AppColors.surfaceSubtle,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(999),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isLiked
                            ? PhosphorIconsFill.heart
                            : PhosphorIconsRegular.heart,
                        size: 15,
                        color: isLiked
                            ? AppColors.error
                            : AppColors.controlInactive,
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
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 목록 카드 하단에 붙는 가벼운 공감 표시(하트 아이콘 + 개수). 상세 화면의
/// 독립된 공감 버튼([CommunityLikeButton])과 달리 배경 필 없이 목록 행에
/// 자연스럽게 붙는 작은 규격이다.
class CommunityLikeInline extends StatelessWidget {
  const CommunityLikeInline({
    super.key,
    required this.isLiked,
    required this.likeCount,
    required this.onTap,
  });

  final bool isLiked;
  final int likeCount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onTap != null;
    return Semantics(
      button: true,
      enabled: isEnabled,
      toggled: isLiked,
      label: '공감 $likeCount개',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isLiked
                        ? PhosphorIconsFill.heart
                        : PhosphorIconsRegular.heart,
                    size: 18,
                    color: isLiked
                        ? AppColors.error
                        : AppColors.controlInactive,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '$likeCount',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 목록 카드의 작성자 행에서 공감 수를 읽기 전용으로 보여주는 하트+숫자.
/// 탭해서 토글하는 [CommunityLikeButton]/[CommunityLikeInline]과 달리
/// 목록에서는 누를 수 없는 정보 표시용이다.
class CommunityLikeCount extends StatelessWidget {
  const CommunityLikeCount({super.key, required this.likeCount});

  final int likeCount;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '공감 $likeCount개',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              PhosphorIconsRegular.heart,
              size: 16,
              color: AppColors.controlInactive,
            ),
            const SizedBox(width: 4),
            Text(
              '$likeCount',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// 커뮤니티 콘텐츠의 더보기 버튼. 44px 터치 영역을 보장한다.
class CommunityMoreButton extends StatelessWidget {
  const CommunityMoreButton({
    super.key,
    required this.onTap,
    required this.tooltip,
    this.iconSize = 20,
  });

  final VoidCallback onTap;
  final String tooltip;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      icon: Icon(
        PhosphorIconsRegular.dotsThree,
        size: iconSize,
        color: AppColors.textMuted,
      ),
    );
  }
}

/// 커뮤니티 콘텐츠 관리 바텀시트의 메뉴 한 줄.
class CommunityMenuTile extends StatelessWidget {
  const CommunityMenuTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = AppColors.textBody,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: RecordDialogMetrics.itemSpacing),
      child: RecordDialogActionTile(
        icon: icon,
        label: label,
        destructive: color == AppColors.error,
        onTap: onTap,
      ),
    );
  }
}
