import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/app_snackbar.dart';
import '../../providers/bookshelf_providers.dart';

/// 책장 탭 공통 Pull to Refresh(동기화: 최초엔 전체, 이후엔 증분). 실패 시 SnackBar로 안내한다.
class BookshelfRefreshIndicator extends ConsumerWidget {
  const BookshelfRefreshIndicator({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(bookshelfSyncControllerProvider.notifier).syncNow();
        final result = ref.read(bookshelfSyncControllerProvider);
        if (result.hasError && context.mounted) {
          AppSnackBar.error(context, '동기화에 실패했습니다. 잠시 후 다시 시도해 주세요.');
        }
      },
      child: child,
    );
  }
}
