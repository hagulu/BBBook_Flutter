import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_bar_title.dart';
import '../../../shared/widgets/community_content.dart';
import '../../auth/providers/auth_access_providers.dart';
import '../../book_reflection/screens/book_reflection_detail_screen.dart';
import '../models/my_reflection_summary.dart';
import '../providers/my_content_providers.dart';
import 'widgets/my_reflection_card.dart';

/// "내가 작성한 독후감" 목록(`my-content-screens.md` §2).
///
/// 로컬 DB에서 바로 읽으므로(§`myReflectionListControllerProvider`) 목록의
/// id가 곧 상세 화면이 쓰는 로컬 PK다 — 서버 ID로 로컬 행을 다시 찾는
/// 절차·동기화 타이밍 문제가 없다.
class MyReflectionsScreen extends ConsumerWidget {
  const MyReflectionsScreen({super.key});

  void _openReflection(
    BuildContext context,
    WidgetRef ref,
    MyReflectionSummary reflection,
  ) {
    final ownerUserId = ref.read(recordOwnerIdProvider);
    if (ownerUserId == null) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => BookReflectionDetailScreen(
          ownerUserId: ownerUserId,
          userBookId: reflection.userBookId,
          bookTitle: reflection.book?.title ?? '',
          reflectionId: reflection.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(myReflectionListControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitle('내가 작성한 독후감'),
        backgroundColor: AppColors.of(context).pageBackground,
        foregroundColor: AppColors.of(context).textStrong,
        elevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: switch (state) {
          AsyncData(:final value) => _ReflectionList(
            items: value,
            onOpen: (reflection) => _openReflection(context, ref, reflection),
          ),
          AsyncError() => CommunityContentErrorState(
            message: '불러오기에 실패했습니다',
            onRetry: () => ref.invalidate(myReflectionListControllerProvider),
          ),
          _ => const CommunityContentLoadingState(),
        },
      ),
    );
  }
}

class _ReflectionList extends StatelessWidget {
  const _ReflectionList({required this.items, required this.onOpen});

  final List<MyReflectionSummary> items;
  final void Function(MyReflectionSummary reflection) onOpen;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: 80),
          Center(
            child: Text(
              '작성한 독후감이 없습니다',
              style: TextStyle(color: AppColors.of(context).textMuted),
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
      itemCount: items.length,
      separatorBuilder: (_, _) => const CommunityContentDivider(),
      itemBuilder: (context, index) {
        final reflection = items[index];
        return MyReflectionCard(
          key: ValueKey(reflection.id),
          reflection: reflection,
          onTap: reflection.isHidden ? null : () => onOpen(reflection),
        );
      },
    );
  }
}
