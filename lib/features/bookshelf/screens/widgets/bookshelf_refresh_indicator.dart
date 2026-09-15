import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/app_snackbar.dart';
import '../../../tag/providers/tag_providers.dart';
import '../../models/book_status.dart';
import '../../providers/bookshelf_providers.dart';

/// `MainShell`의 56dp FAB와 기본 여백을 피해 마지막 책까지 온전히 스크롤할
/// 수 있도록 책장 목록 아래에 확보하는 공통 여백.
const bookshelfFabBottomPadding = 88.0;

/// 책장 탭 공통 Pull to Refresh(동기화: 최초엔 전체, 이후엔 증분). 실패 시 SnackBar로 안내한다.
class BookshelfRefreshIndicator extends ConsumerWidget {
  const BookshelfRefreshIndicator({
    super.key,
    required this.child,
    this.recommendationStatus,
  });

  final Widget child;

  /// 이 탭이 추천 도서를 노출하는 탭(읽는 중/읽을 책)이면 그 상태를 넘긴다.
  /// 당겨서 새로고침 시 그 탭의 추천만 다시 조회한다 — 완독/읽기 중단
  /// 탭이나, 보고 있지 않은 다른 탭의 추천까지 함께 새로고침하지 않는다.
  final BookStatus? recommendationStatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([
          ref
              .read(bookshelfSyncControllerProvider.notifier)
              .syncNow(userInitiated: true),
          ref.read(tagSyncControllerProvider.notifier).syncNow(),
        ]);
        // 책장 동기화 자체는 로컬 DB가 실제로 바뀔 때만
        // bookshelfSyncVersionProvider를 올리므로, 추천 API만 실패했다가
        // 복구된 경우(로컬 변경 없음)는 그 신호를 못 받는다. 당겨서
        // 새로고침을 "재시도" 동작으로도 취급해 이 탭의 추천 provider만
        // 직접 invalidate한다 — 실패가 앱 재시작 전까지 영구 캐시되지
        // 않게 한다.
        if (recommendationStatus case final status?) {
          ref.invalidate(bookRecommendationsProvider(status));
        }
        final bookshelfResult = ref.read(bookshelfSyncControllerProvider);
        final tagResult = ref.read(tagSyncControllerProvider);
        if ((bookshelfResult.hasError || tagResult.hasError) &&
            context.mounted) {
          AppSnackBar.error(context, '동기화에 실패했습니다. 잠시 후 다시 시도해 주세요.');
        } else if (await ref
                .read(bookshelfRepositoryProvider)
                .hasSyncFailures() &&
            context.mounted) {
          AppSnackBar.error(
            context,
            '일부 기록은 서버에 반영되지 않았습니다. 로컬 기록은 유지되며, 내용 수정 후 또는 새로고침으로 재시도할 수 있습니다.',
          );
        }
      },
      child: child,
    );
  }
}
