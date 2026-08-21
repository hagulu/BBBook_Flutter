import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_notifier.dart';
import '../models/book_reflection.dart';
import '../providers/book_reflection_providers.dart';
import 'book_reflection_detail_screen.dart';
import 'widgets/book_reflection_refresh_indicator.dart';

/// 책 기록 상세의 독후감 탭. [bookReflectionListProvider]가 로컬 DB만
/// 조회한다. 서버와의 동기화(전체/증분 새로고침)는 당겨서 새로고침
/// ([BookReflectionRefreshIndicator])으로만 일어난다 —
/// [BookNoteList]와 같은 원칙.
///
/// 작성/수정/삭제(에디터)는 아직 붙이지 않아 목록에 추가 버튼이 없다 —
/// 웹의 "독후감 추가" 버튼에 대응하는 진입점은 에디터 구현 시 추가한다.
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
    final ownerUserId = ref.watch(
      authNotifierProvider.select((auth) => auth.user?.id),
    );
    final asyncReflections = ref.watch(bookReflectionListProvider(userBookId));

    return BookReflectionRefreshIndicator(
      child: CustomScrollView(
        key: const PageStorageKey('book-reflection-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const SliverPadding(
            padding: EdgeInsets.fromLTRB(16, 18, 16, 12),
            sliver: SliverToBoxAdapter(
              child: Text(
                '독후감',
                style: TextStyle(
                  color: AppColors.textStrong,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          switch (asyncReflections) {
            AsyncData(:final value) when value.isEmpty =>
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyReflections(),
              ),
            AsyncData(:final value) => SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: SliverList.separated(
                itemCount: value.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final reflection = value[index];
                  return _ReflectionCard(
                    reflection: reflection,
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
}

class _ReflectionCard extends StatelessWidget {
  const _ReflectionCard({required this.reflection, required this.onTap});

  final BookReflection reflection;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final title = reflection.title?.trim();
    final preview = reflection.contentText?.trim();
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
            boxShadow: const [
              BoxShadow(
                color: AppColors.shadowSoft,
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            reflection.isHidden
                                ? '숨김 처리된 독후감'
                                : (title == null || title.isEmpty
                                      ? '제목 없음'
                                      : title),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textStrong,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Semantics(
                          label: reflection.isPublic ? '공개 독후감' : '비공개 독후감',
                          child: Icon(
                            reflection.isPublic
                                ? PhosphorIconsRegular.globe
                                : PhosphorIconsRegular.lock,
                            size: 14,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    if (!reflection.isHidden &&
                        preview != null &&
                        preview.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textBody,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 7),
                    Text(
                      _formatDate(reflection.updatedAt),
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                PhosphorIconsRegular.caretRight,
                color: AppColors.controlInactive,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    return '${local.year}.${local.month}.${local.day}';
  }
}

class _EmptyReflections extends StatelessWidget {
  const _EmptyReflections();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.fromLTRB(32, 24, 32, 80),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIconsRegular.bookOpenText,
              size: 44,
              color: AppColors.controlInactive,
            ),
            SizedBox(height: 14),
            Text(
              '아직 독후감이 없습니다.',
              style: TextStyle(
                color: AppColors.textStrong,
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
          const Text(
            '독후감을 불러오지 못했습니다.',
            style: TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    );
  }
}
