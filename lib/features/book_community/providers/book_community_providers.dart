import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import '../data/book_community_api.dart';
import '../models/book_community.dart';

final bookCommunityApiProvider = Provider<BookCommunityApi>((ref) {
  return BookCommunityApi(apiClient: ref.watch(apiClientProvider));
});

/// isbn13 기준 커뮤니티 미리보기(최근 독자평·평균 별점·독후감/토론 개수).
/// 두 화면 모두 필요해 항상 조회한다.
final bookCommunityPreviewProvider = FutureProvider.autoDispose
    .family<BookCommunityPreview, String>((ref, isbn13) {
      return ref.watch(bookCommunityApiProvider).getPreview(isbn13);
    });

/// isbn13 기준 독자평 전체 개수(`reviewCount`, community-preview엔 없는
/// 값). 독자평 개수 배지가 필요한 화면(생각나눔 탭)만 이 provider를 watch해
/// 호출한다 — 검색 상세는 독자평을 미리보기 카드로만 보여줘 이 요청이
/// 필요 없다. [bookCommunityPreviewProvider]와 독립된 요청이라 한쪽이
/// 실패해도 다른 쪽 데이터는 그대로 표시된다.
final bookCommunityCountsProvider = FutureProvider.autoDispose
    .family<BookCommunityCounts, String>((ref, isbn13) {
      return ref.watch(bookCommunityApiProvider).getCounts(isbn13);
    });
