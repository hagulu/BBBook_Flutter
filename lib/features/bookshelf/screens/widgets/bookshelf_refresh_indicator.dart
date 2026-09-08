import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/app_snackbar.dart';
import '../../../tag/providers/tag_providers.dart';
import '../../providers/bookshelf_providers.dart';

/// `MainShell`의 56dp FAB와 기본 여백을 피해 마지막 책까지 온전히 스크롤할
/// 수 있도록 책장 목록 아래에 확보하는 공통 여백.
const bookshelfFabBottomPadding = 88.0;

/// 책장 탭 공통 Pull to Refresh(동기화: 최초엔 전체, 이후엔 증분). 실패 시 SnackBar로 안내한다.
class BookshelfRefreshIndicator extends ConsumerWidget {
  const BookshelfRefreshIndicator({super.key, required this.child});

  final Widget child;

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
