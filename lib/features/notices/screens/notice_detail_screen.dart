import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_bar_title.dart';
import '../../../shared/widgets/community_content.dart';
import '../../discussion/utils/discussion_date.dart';
import '../models/notice_detail.dart';
import '../providers/notices_providers.dart';

/// 공지사항 상세(`notices-screens.md` §2).
class NoticeDetailScreen extends ConsumerWidget {
  const NoticeDetailScreen({super.key, required this.noticeId});

  final int noticeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(noticeDetailProvider(noticeId));

    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitle('공지사항'),
        backgroundColor: AppColors.pageBackground,
        foregroundColor: AppColors.textStrong,
        elevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: switch (state) {
          AsyncData(:final value) => _NoticeDetailBody(detail: value),
          AsyncError(:final error)
              when error is ApiException && error.statusCode == 404 =>
            const Center(
              child: Text(
                '공지사항을 찾을 수 없습니다',
                style: TextStyle(color: AppColors.textMuted),
              ),
            ),
          AsyncError() => CommunityContentErrorState(
            message: '공지사항을 불러오지 못했습니다',
            onRetry: () => ref.invalidate(noticeDetailProvider(noticeId)),
          ),
          _ => const CommunityContentLoadingState(),
        },
      ),
    );
  }
}

class _NoticeDetailBody extends StatelessWidget {
  const _NoticeDetailBody({required this.detail});

  final NoticeDetail detail;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              detail.title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textStrong,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              formatDiscussionDate(detail.createdAt),
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 14),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 14),
            Text(
              detail.content,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textBody,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
