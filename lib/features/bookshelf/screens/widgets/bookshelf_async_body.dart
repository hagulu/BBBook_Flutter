import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';

/// 탭 공통 로딩/오류/빈 상태 처리(`bookshelf.md` 화면 상태 규칙).
///
/// 빈 상태/오류 상태도 스크롤 가능하게 만들어 [RefreshIndicator]의 Pull to
/// Refresh가 항상 동작하도록 한다.
class BookshelfAsyncBody<T> extends StatelessWidget {
  const BookshelfAsyncBody({
    super.key,
    required this.value,
    required this.builder,
    required this.emptyText,
    this.onRetry,
  });

  final AsyncValue<List<T>> value;
  final Widget Function(BuildContext context, List<T> items) builder;
  final String emptyText;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: (items) {
        if (items.isEmpty) {
          return _ScrollableMessage(text: emptyText);
        }
        return builder(context, items);
      },
      loading: () => const _ScrollableMessage(text: '불러오는 중'),
      error: (error, stackTrace) =>
          _ScrollableMessage(text: '목록을 불러오지 못했습니다.', onRetry: onRetry),
    );
  }
}

class _ScrollableMessage extends StatelessWidget {
  const _ScrollableMessage({required this.text, this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    text,
                    style: const TextStyle(color: AppColors.tertiaryText),
                  ),
                  if (onRetry != null) ...[
                    const SizedBox(height: 8),
                    TextButton(onPressed: onRetry, child: const Text('다시 시도')),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
