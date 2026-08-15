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
    // `value.hasValue`를 먼저 본다(단순 `.when()`이 아님) — 다른 화면(책
    // 기록 상세 등)에서의 수정이 `bookshelfSyncVersionProvider`를 올려
    // 이 목록 provider를 백그라운드에서 다시 조회시킬 때마다, provider가
    // 잠깐 `AsyncLoading`으로 바뀐다. `.when()`으로 그 순간에 로딩 문구를
    // 그리면 그리드가 사라졌다 다시 나타나면서(위젯 트리 종류가 바뀌어
    // 스크롤 상태를 들고 있던 Scrollable도 함께 폐기된다) 스크롤 위치가
    // 맨 위로 리셋된 것처럼 보인다. 이미 받아온 데이터가 있으면(재조회
    // 중이라도) 그대로 계속 보여줘 목록 위젯을 그대로 유지한다 — 로딩
    // 문구는 데이터를 아직 한 번도 못 받은 최초 로딩에서만 보여준다.
    final items = value.valueOrNull;
    if (items != null) {
      if (items.isEmpty) {
        return _ScrollableMessage(text: emptyText);
      }
      return builder(context, items);
    }
    if (value.hasError) {
      return _ScrollableMessage(text: '목록을 불러오지 못했습니다.', onRetry: onRetry);
    }
    return const _ScrollableMessage(text: '불러오는 중');
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
