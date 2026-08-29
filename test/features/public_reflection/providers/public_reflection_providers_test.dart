import 'dart:async';

import 'package:bbbook/features/public_reflection/data/public_reflection_source.dart';
import 'package:bbbook/features/public_reflection/models/public_reflection.dart';
import 'package:bbbook/features/public_reflection/providers/public_reflection_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('공감 요청 중 연속 토글은 추가 요청을 만들지 않는다', () async {
    final source = _DeferredLikeSource(detail: _detail());
    final container = ProviderContainer(
      overrides: [publicReflectionSourceProvider.overrideWithValue(source)],
    );
    addTearDown(container.dispose);

    const args = (isbn13: '9781234567890', reflectionId: 7);
    final subscription = container.listen(
      publicReflectionDetailProvider(args),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await container.read(publicReflectionDetailProvider(args).future);

    final controller = container.read(
      publicReflectionDetailProvider(args).notifier,
    );
    final firstToggle = controller.toggleLike();
    await source.postStarted.future;
    await controller.toggleLike();

    expect(source.postLikeCalls, 1);
    expect(source.deleteLikeCalls, 0);
    expect(
      container.read(publicReflectionDetailProvider(args)).requireValue,
      isA<PublicReflectionDetail>()
          .having((detail) => detail.likedByMe, 'likedByMe', isTrue)
          .having((detail) => detail.likeCount, 'likeCount', 1),
    );

    source.postResult.complete(1);
    await firstToggle;

    expect(source.postLikeCalls, 1);
    expect(
      container.read(publicReflectionDetailProvider(args)).requireValue,
      isA<PublicReflectionDetail>()
          .having((detail) => detail.likedByMe, 'likedByMe', isTrue)
          .having((detail) => detail.likeCount, 'likeCount', 1),
    );
  });
}

PublicReflectionDetail _detail() {
  return PublicReflectionDetail(
    id: 7,
    isbn13: '9781234567890',
    book: const PublicReflectionBook(title: '책'),
    title: '독후감',
    contentJson: const {
      'ops': [
        {'insert': '본문\n'},
      ],
    },
    contentText: '본문',
    isPublic: true,
    status: 'PUBLISHED',
    user: const PublicReflectionAuthor(id: 10, nickname: '독자'),
    createdAt: DateTime.utc(2026, 8, 28),
    updatedAt: DateTime.utc(2026, 8, 28),
  );
}

class _DeferredLikeSource implements PublicReflectionSource {
  _DeferredLikeSource({required this.detail});

  final PublicReflectionDetail detail;
  final postStarted = Completer<void>();
  final postResult = Completer<int>();
  var postLikeCalls = 0;
  var deleteLikeCalls = 0;

  @override
  Future<int> deleteLike(int reflectionId) async {
    deleteLikeCalls += 1;
    return 0;
  }

  @override
  Future<PublicReflectionDetail> fetchDetail(int reflectionId) async => detail;

  @override
  Future<PublicReflectionsPage> fetchPage({
    required String isbn13,
    int? cursor,
    required int size,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<int> postLike(int reflectionId) {
    postLikeCalls += 1;
    if (!postStarted.isCompleted) postStarted.complete();
    return postResult.future;
  }
}
