import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/community_content.dart';
import '../../../book_detail/screens/book_review_list_screen.dart';
import '../../../book_record/screens/widgets/entry_button.dart';
import '../../../book_record/screens/widgets/star_rating.dart';
import '../../../book_reflection/providers/book_reflection_providers.dart';
import '../../../discussion/screens/discussion_list_screen.dart';
import '../../../discussion/utils/discussion_date.dart';
import '../../../public_reflection/screens/public_reflection_list_screen.dart';
import '../../models/book_community.dart';
import '../../providers/book_community_providers.dart';

/// 책 검색 상세·책 기록 상세(생각나눔 탭)가 공유하는 커뮤니티 미리보기 영역.
///
/// 독후감/토론 개수는 항상 community-preview 응답에서 얻는다(그 응답의
/// `reflections.count`/`discussions.count`가 community-counts의 값과
/// 정의가 같다). 독자평 전체 개수(`reviewCount`)만 community-preview에
/// 없어서, 그 값이 실제로 필요한 화면([showReviewButton] true)에서만
/// community-counts를 추가로 부른다 — 두 요청은 서로 독립된 provider라 한쪽이
/// 실패해도 다른 쪽 데이터는 그대로 표시된다.
///
/// 독후감/토론은 세로로 쌓은 큼직한 진입 버튼으로, 독자평은 평균 별점·최근
/// 3건을 화면에 직접 보여주고 하단 "더보기"로 전체 목록에 진입한다.
///
/// 책 검색 상세([showReviewButton] 기본값 false)에서는 독후감·토론 둘 다
/// 0건이면 진입 버튼 자체를 접고, 최근 독자평이 없으면 미리보기 섹션도
/// 통째로 숨겨 어색한 빈 공간을 만들지 않는다.
///
/// 책 기록 상세의 생각나눔 탭([showReviewButton] true)에서는 이미 내 책장에
/// 있는 책이라 세 진입 버튼(독자평 포함)을 개수와 무관하게 항상 보여준다
/// (사용자 확인 사항).
///
/// [userBookId]를 넘기면(두 화면 모두 가능 — 검색 상세도 이미 서재에 있는
/// 책이면 넘긴다) 독후감 배지에서 내가 이미 쓴 공개 독후감 수를 뺀다.
/// 공개 독후감 목록 API(`GET .../reflections`)는 로그인한 본인 글을
/// 제외하고 내려주므로, 빼지 않으면 배지 숫자와 그 목록으로 진입했을 때
/// 실제로 보이는 글 수가 어긋난다(생각나눔 탭은 그 책의 독후감 탭에 자기
/// 글이 따로 보이므로 "다른 사람이 쓴 개수"만 의미가 있다는 점도 같다).
/// 서버에 아직 반영되지 않은 글(로컬 저장 모드, 또는 push 대기 중인 dirty
/// 행)은 community 응답의 개수에 포함돼 있지 않으므로 빼지 않는다.
class BookCommunityPreviewSection extends ConsumerWidget {
  const BookCommunityPreviewSection({
    super.key,
    required this.isbn13,
    required this.bookTitle,
    this.userBookId,
    this.showReviewButton = false,
  });

  final String isbn13;
  final String bookTitle;
  final int? userBookId;
  final bool showReviewButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final previewProvider = bookCommunityPreviewProvider(isbn13);
    final previewState = ref.watch(previewProvider);
    final preview = previewState.valueOrNull;

    final reviewCount = showReviewButton
        ? ref
              .watch(bookCommunityCountsProvider(isbn13))
              .valueOrNull
              ?.reviewCount
        : null;

    final myPublicReflectionCount = userBookId == null
        ? 0
        : (ref.watch(bookReflectionListProvider(userBookId!)).valueOrNull ??
                  const [])
              .where(
                (r) =>
                    r.isPublic &&
                    !r.isHidden &&
                    r.serverId != null &&
                    !r.isDirty,
              )
              .length;
    final reflectionCount = preview == null
        ? null
        : math.max(0, preview.reflectionCount - myPublicReflectionCount);

    // 생각나눔 탭은 항상 세 버튼을 보여준다. 검색 상세는 독후감·토론 둘 다
    // 0건이면 진입 버튼 자체를 접는다(사용자 확인 사항).
    final showEntryButtons =
        showReviewButton ||
        (preview != null &&
            (preview.reflectionCount > 0 || preview.discussionCount > 0));
    // 최근 독자평이 없으면 미리보기 섹션을 통째로 숨긴다(안내 문구도 없음).
    final showReviews = preview != null && preview.reviewItems.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showEntryButtons)
          _EntryButtons(
            reviewCount: reviewCount,
            reflectionCount: reflectionCount,
            discussionCount: preview?.discussionCount,
            showReviewButton: showReviewButton,
            onOpenReviews: () => _openReviews(context, ref),
            onOpenReflections: () => _openReflections(context, ref),
            onOpenDiscussions: () => _openDiscussions(context, ref),
          ),
        if (showEntryButtons && showReviews) const SizedBox(height: 20),
        if (showReviews)
          _ReviewsPreview(
            preview: preview,
            onOpenReviews: () => _openReviews(context, ref),
          ),
        if (!showEntryButtons && !showReviews) ...[
          if (previewState.hasError)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Column(
                  children: [
                    const Text(
                      '커뮤니티 정보를 불러오지 못했습니다.',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: () => ref.invalidate(previewProvider),
                      child: const Text('다시 시도'),
                    ),
                  ],
                ),
              ),
            )
          else if (preview == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  '불러오는 중',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ),
            ),
        ],
      ],
    );
  }

  /// 진입 화면에서 돌아오면 새 리뷰 작성 등으로 개수가 바뀌었을 수 있어
  /// 커뮤니티 정보를 다시 불러온다.
  Future<void> _openReviews(BuildContext context, WidgetRef ref) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            BookReviewListScreen(isbn13: isbn13, bookTitle: bookTitle),
      ),
    );
    if (!context.mounted) return;
    _invalidate(ref);
  }

  Future<void> _openReflections(BuildContext context, WidgetRef ref) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            PublicReflectionListScreen(isbn13: isbn13, bookTitle: bookTitle),
      ),
    );
    if (!context.mounted) return;
    _invalidate(ref);
  }

  Future<void> _openDiscussions(BuildContext context, WidgetRef ref) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            DiscussionListScreen(isbn13: isbn13, bookTitle: bookTitle),
      ),
    );
    if (!context.mounted) return;
    _invalidate(ref);
  }

  void _invalidate(WidgetRef ref) {
    ref.invalidate(bookCommunityPreviewProvider(isbn13));
    ref.invalidate(bookCommunityCountsProvider(isbn13));
  }
}

/// 독자평(생각나눔 탭만)/독후감/토론 진입 버튼(세로로 쌓은 큼직한 터치
/// 영역). 각 개수가 아직 로딩 전(null)이면 배지 없이 버튼만 먼저 보여준다.
class _EntryButtons extends StatelessWidget {
  const _EntryButtons({
    required this.reviewCount,
    required this.reflectionCount,
    required this.discussionCount,
    required this.showReviewButton,
    required this.onOpenReviews,
    required this.onOpenReflections,
    required this.onOpenDiscussions,
  });

  final int? reviewCount;

  /// 독후감 배지에 표시할 값. 생각나눔 탭에서는 내가 이미 쓴 공개 독후감
  /// 수를 뺀 값이 들어온다.
  final int? reflectionCount;
  final int? discussionCount;
  final bool showReviewButton;
  final VoidCallback onOpenReviews;
  final VoidCallback onOpenReflections;
  final VoidCallback onOpenDiscussions;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (showReviewButton) ...[
          EntryButton(
            icon: PhosphorIconsRegular.star,
            label: '독자평',
            count: reviewCount,
            onTap: onOpenReviews,
          ),
          const SizedBox(height: 12),
        ],
        EntryButton(
          icon: PhosphorIconsRegular.notebook,
          label: '독후감',
          count: reflectionCount,
          onTap: onOpenReflections,
        ),
        const SizedBox(height: 12),
        EntryButton(
          icon: PhosphorIconsRegular.chatsCircle,
          label: '토론',
          count: discussionCount,
          onTap: onOpenDiscussions,
        ),
      ],
    );
  }
}

/// 독자평 미리보기: 평균 별점(전체 기준) + 최근 3건 + 전체 목록 진입.
///
/// 호출부가 이미 `reviewItems.isNotEmpty`일 때만 이 위젯을 렌더링한다(최근
/// 독자평이 없으면 안내 문구도 없이 섹션 전체를 숨긴다 — 사용자 확인 사항).
class _ReviewsPreview extends StatelessWidget {
  const _ReviewsPreview({required this.preview, required this.onOpenReviews});

  final BookCommunityPreview preview;
  final VoidCallback onOpenReviews;

  @override
  Widget build(BuildContext context) {
    final items = preview.reviewItems;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '독자평',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textStrong,
                ),
              ),
            ),
            if (preview.averageRating != null) ...[
              StarRatingDisplay(
                rating: preview.averageRating!,
                size: 14,
                filledColor: AppColors.accentGraphic,
              ),
              const SizedBox(width: 6),
              Text(
                preview.averageRating!.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textStrong,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < items.length; i++) ...[
          _ReviewPreviewCard(item: items[i], onTap: onOpenReviews),
          if (i != items.length - 1) const SizedBox(height: 10),
        ],
        const SizedBox(height: 8),
        Center(
          child: TextButton(onPressed: onOpenReviews, child: const Text('더보기')),
        ),
      ],
    );
  }
}

class _ReviewPreviewCard extends StatelessWidget {
  const _ReviewPreviewCard({required this.item, required this.onTap});

  final BookCommunityReviewPreview item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CommunityContentCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CommunityAuthorRow(
            nickname: item.user.nickname,
            profileImageUrl: item.user.profileImageUrl,
            dateLabel: formatDiscussionDate(item.createdAt),
            avatarRadius: 12,
            trailing: item.rating != null
                ? StarRatingDisplay(
                    rating: item.rating!,
                    size: 12,
                    filledColor: AppColors.accentGraphic,
                  )
                : null,
          ),
          const SizedBox(height: 8),
          Text(
            item.content,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textBody,
              height: 1.4,
            ),
          ),
          if (item.likeCount > 0) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  PhosphorIconsRegular.heart,
                  size: 13,
                  color: AppColors.controlInactive,
                ),
                const SizedBox(width: 4),
                Text(
                  '공감 ${item.likeCount}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
