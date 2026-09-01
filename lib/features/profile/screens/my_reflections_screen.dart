import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_bar_title.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/community_content.dart';
import '../../auth/providers/auth_notifier.dart';
import '../../book_reflection/providers/book_reflection_providers.dart';
import '../../book_reflection/screens/book_reflection_detail_screen.dart';
import '../models/my_reflection_summary.dart';
import '../providers/my_content_providers.dart';
import 'widgets/my_reflection_card.dart';

/// "내가 작성한 독후감" 목록(`my-content-screens.md` §2).
class MyReflectionsScreen extends ConsumerStatefulWidget {
  const MyReflectionsScreen({super.key});

  @override
  ConsumerState<MyReflectionsScreen> createState() =>
      _MyReflectionsScreenState();
}

class _MyReflectionsScreenState extends ConsumerState<MyReflectionsScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      ref.read(myReflectionListControllerProvider.notifier).loadMore();
    }
  }

  /// 기존 책 기록 상세의 독후감 관리와 동일한 로컬 우선 화면
  /// (`BookReflectionDetailScreen`)으로 연결한다. 서버 목록은 서버
  /// reflectionId만 주는데 이 화면은 로컬 PK가 필요하므로(로컬에서
  /// 직접 작성한 행은 push 뒤에도 로컬 PK를 그대로 유지해 서버 ID와
  /// 다르다), 서버 ID로 로컬 행을 먼저 찾는다.
  Future<void> _openReflection(MyReflectionSummary reflection) async {
    final ownerUserId = ref.read(
      authNotifierProvider.select((auth) => auth.user?.id),
    );
    final local = ownerUserId == null
        ? null
        : await ref
              .read(bookReflectionRepositoryProvider)
              .findByServerId(ownerUserId: ownerUserId, serverId: reflection.id);

    if (!mounted) return;
    if (ownerUserId == null || local == null) {
      AppSnackBar.error(context, '독후감을 불러오지 못했습니다.');
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => BookReflectionDetailScreen(
          ownerUserId: ownerUserId,
          userBookId: local.userBookId,
          bookTitle: reflection.book?.title ?? '',
          reflectionId: local.id,
        ),
      ),
    );
    // 상세에서 수정·삭제가 있었을 수 있으니 돌아오면 목록을 다시 조회한다.
    if (mounted) ref.invalidate(myReflectionListControllerProvider);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(myReflectionListControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitle('내가 작성한 독후감'),
        backgroundColor: AppColors.pageBackground,
        foregroundColor: AppColors.textStrong,
        elevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: switch (state) {
          AsyncData(:final value) => _ReflectionList(
            scrollController: _scrollController,
            items: value.items,
            isLoadingMore: value.isLoadingMore,
            onOpen: _openReflection,
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
  const _ReflectionList({
    required this.scrollController,
    required this.items,
    required this.isLoadingMore,
    required this.onOpen,
  });

  final ScrollController scrollController;
  final List<MyReflectionSummary> items;
  final bool isLoadingMore;
  final void Function(MyReflectionSummary reflection) onOpen;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return ListView(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 80),
          Center(
            child: Text(
              '작성한 독후감이 없습니다',
              style: TextStyle(color: AppColors.textMuted),
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      controller: scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: items.length + (isLoadingMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index >= items.length) {
          return const CommunityContentPageLoader();
        }
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
