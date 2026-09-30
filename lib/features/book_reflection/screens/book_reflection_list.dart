import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/preview_text.dart';
import '../../../shared/widgets/community_content.dart';
import '../../auth/providers/auth_access_providers.dart';
import '../../discussion/utils/discussion_date.dart';
import '../models/book_reflection.dart';
import '../providers/book_reflection_providers.dart';
import 'book_reflection_detail_screen.dart';
import 'book_reflection_editor_screen.dart';
import 'widgets/book_reflection_refresh_indicator.dart';

/// 책 기록 상세의 독후감 탭. [bookReflectionListProvider]가 로컬 DB만
/// 조회한다. 서버와의 동기화(전체/증분 새로고침)는 당겨서 새로고침
/// ([BookReflectionRefreshIndicator])으로만 일어난다 —
/// [BookNoteList]와 같은 원칙.
///
/// 오른쪽 아래 추가 버튼은 새 에디터로, 각 카드는 리치 텍스트 상세·수정 흐름으로
/// 연결된다.
class BookReflectionList extends ConsumerWidget {
  const BookReflectionList({
    super.key,
    required this.userBookId,
    required this.bookTitle,
  });

  final int userBookId;
  final String bookTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ownerUserId = ref.watch(recordOwnerIdProvider);
    // 공개/비공개 구분은 서버에 올린 독후감에만 의미가 있다 — 계정이 없으면
    // 모두 이 기기에만 있는 글이라 배지를 보여주지 않는다.
    final showVisibility = ref.watch(canUseAccountFeaturesProvider);
    final asyncReflections = ref.watch(bookReflectionListProvider(userBookId));

    return Stack(
      children: [
        BookReflectionRefreshIndicator(
          child: CustomScrollView(
            key: const PageStorageKey('book-reflection-list'),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              switch (asyncReflections) {
                AsyncData(:final value) when value.isEmpty =>
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyReflections(),
                  ),
                AsyncData(:final value) => SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 96),
                  sliver: SliverList.separated(
                    itemCount: value.length,
                    separatorBuilder: (_, _) => const CommunityContentDivider(),
                    itemBuilder: (context, index) {
                      final reflection = value[index];
                      return _ReflectionCard(
                        reflection: reflection,
                        showVisibility: showVisibility,
                        onTap: ownerUserId == null
                            ? null
                            : () => _openReflection(
                                context,
                                ownerUserId: ownerUserId,
                                reflectionId: reflection.id,
                              ),
                      );
                    },
                  ),
                ),
                AsyncError() => SliverFillRemaining(
                  hasScrollBody: false,
                  child: _ReflectionLoadError(
                    onRetry: () =>
                        ref.invalidate(bookReflectionListProvider(userBookId)),
                  ),
                ),
                _ => const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                ),
              },
            ],
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            heroTag: 'book-reflection-add-$userBookId',
            onPressed: ownerUserId == null
                ? null
                : () => _openEditor(context, ownerUserId: ownerUserId),
            tooltip: '독후감 추가',
            shape: const CircleBorder(),
            backgroundColor: AppColors.of(context).accentFill,
            foregroundColor: AppColors.of(context).textStrong,
            elevation: 2,
            child: const Icon(PhosphorIconsRegular.plus),
          ),
        ),
      ],
    );
  }

  Future<void> _openReflection(
    BuildContext context, {
    required int ownerUserId,
    required int reflectionId,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => BookReflectionDetailScreen(
          ownerUserId: ownerUserId,
          userBookId: userBookId,
          bookTitle: bookTitle,
          reflectionId: reflectionId,
        ),
      ),
    );
  }

  Future<void> _openEditor(BuildContext context, {required int ownerUserId}) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => BookReflectionEditorScreen(
          ownerUserId: ownerUserId,
          userBookId: userBookId,
          bookTitle: bookTitle,
        ),
      ),
    );
  }
}

class _ReflectionCard extends StatelessWidget {
  const _ReflectionCard({
    required this.reflection,
    required this.showVisibility,
    required this.onTap,
  });

  final BookReflection reflection;
  final bool showVisibility;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final title = reflection.title?.trim();
    final preview = flattenPreviewText(reflection.contentText);
    return CommunityContentCard(
      onTap: onTap,
      padding: const EdgeInsets.only(top: 24, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            reflection.isHidden
                ? '숨김 처리된 독후감'
                : (title == null || title.isEmpty ? '제목 없음' : title),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.of(context).textStrong,
              fontSize: 16,
              height: 1.4,
              letterSpacing: -0.2,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (!reflection.isHidden &&
              preview != null &&
              preview.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              preview,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.of(context).textBody,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                formatRelativeDiscussionDate(reflection.createdAt),
                style: TextStyle(
                  color: AppColors.of(context).textMuted,
                  fontSize: 11,
                ),
              ),
              if (showVisibility && reflection.isPublic) ...[
                const Spacer(),
                Semantics(
                  label: '공개 독후감',
                  child: Icon(
                    PhosphorIconsRegular.globe,
                    size: 14,
                    color: AppColors.of(context).textMuted,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyReflections extends StatelessWidget {
  const _EmptyReflections();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.fromLTRB(32, 24, 32, 80),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIconsRegular.bookOpenText,
              size: 44,
              color: AppColors.of(context).controlInactive,
            ),
            SizedBox(height: 14),
            Text(
              '아직 독후감이 없습니다.',
              style: TextStyle(
                color: AppColors.of(context).textStrong,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReflectionLoadError extends StatelessWidget {
  const _ReflectionLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '독후감을 불러오지 못했습니다.',
            style: TextStyle(color: AppColors.of(context).textMuted),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    );
  }
}
