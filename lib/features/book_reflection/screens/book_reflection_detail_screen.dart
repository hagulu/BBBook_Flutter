import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../core/theme/app_theme.dart';
import '../models/book_reflection.dart';
import '../providers/book_reflection_providers.dart';

/// 독후감 상세(읽기 전용 흐름만 우선 구현).
///
/// `content_json`(Tiptap/ProseMirror JSON)을 리치 텍스트로 렌더링하는 기능은
/// 아직 붙이지 않았다 — 웹과 손실 없이 호환되는 에디터/렌더러 구현 방식은
/// 별도로 결정하기로 했다(reflection-editor.md 참고). 그때까지는 미리보기용
/// 순수 텍스트인 [BookReflection.contentText]만 보여준다. 수정/삭제/공개
/// 전환/좋아요 등도 에디터와 함께 붙일 예정이라 이 화면에는 아직 없다.
class BookReflectionDetailScreen extends ConsumerWidget {
  const BookReflectionDetailScreen({
    super.key,
    required this.ownerUserId,
    required this.userBookId,
    required this.bookTitle,
    required this.reflectionId,
  });

  final int ownerUserId;
  final int userBookId;
  final String bookTitle;
  final int reflectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = BookReflectionDetailArgs(
      ownerUserId: ownerUserId,
      userBookId: userBookId,
      reflectionId: reflectionId,
    );
    final asyncReflection = ref.watch(bookReflectionDetailProvider(args));

    return Scaffold(
      appBar: AppBar(
        title: Text(bookTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        backgroundColor: AppColors.pageBackground,
        foregroundColor: AppColors.textStrong,
        elevation: 0,
      ),
      body: switch (asyncReflection) {
        AsyncData(:final value) => value == null
            ? const _ReflectionNotFound()
            : _ReflectionBody(reflection: value),
        AsyncError() => _ReflectionLoadError(
          onRetry: () => ref.invalidate(bookReflectionDetailProvider(args)),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _ReflectionBody extends StatelessWidget {
  const _ReflectionBody({required this.reflection});

  final BookReflection reflection;

  @override
  Widget build(BuildContext context) {
    if (reflection.isHidden) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            '숨김 처리된 독후감입니다.',
            style: TextStyle(color: AppColors.textMuted),
          ),
        ),
      );
    }

    final title = reflection.title?.trim();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title == null || title.isEmpty ? '제목 없음' : title,
                  style: const TextStyle(
                    color: AppColors.textStrong,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
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
                  size: 18,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _formatDate(reflection.updatedAt),
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 20),
          Text(
            reflection.contentText?.trim().isNotEmpty == true
                ? reflection.contentText!.trim()
                : '내용이 없습니다.',
            style: const TextStyle(
              color: AppColors.textBody,
              fontSize: 15,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    return '${local.year}.${local.month}.${local.day}';
  }
}

class _ReflectionNotFound extends StatelessWidget {
  const _ReflectionNotFound();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        '독후감을 찾을 수 없습니다.',
        style: TextStyle(color: AppColors.textMuted),
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
