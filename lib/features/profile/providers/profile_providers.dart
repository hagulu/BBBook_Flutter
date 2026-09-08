import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import '../../auth/providers/auth_notifier.dart';
import '../../bookshelf/models/book_status.dart';
import '../../bookshelf/providers/bookshelf_providers.dart';
import '../data/profile_api.dart';
import '../models/profile_me.dart';
import '../models/profile_stats_summary.dart';

final profileApiProvider = Provider<ProfileApi>((ref) {
  return ProfileApi(apiClient: ref.watch(apiClientProvider));
});

/// 프로필 카드(닉네임·이메일·프로필 이미지) 조회.
///
/// 실패하면 화면 전체가 에러 상태로 전환된다(§2-2, profile_screen.dart 참고).
final profileMeProvider = FutureProvider.autoDispose<ProfileMe>((ref) {
  ref.watch(
    authNotifierProvider.select((auth) => (auth.user?.id, auth.isLoggedIn)),
  );
  return ref.watch(profileApiProvider).getMyProfile();
});

/// 독서 통계 카드(완독 권수·읽은 쪽수·많이 읽은 분야) 요약.
///
/// 서버 API 대신 로컬 서재 데이터(완독 탭)로 직접 계산한다 — 완독 기준은
/// `status = FINISHED`, 전체 기간 집계로 서버 API 문서와 동일하다.
/// - 읽은 쪽수는 종이책 기준 쪽수([BookItem.statsTotalPages])만 합산한다.
/// - 많이 읽은 분야는 완독 책 중 카테고리(`displayCategoryId`)가 있는
///   것만으로 빈도를 세어 가장 많은 카테고리를 고른다(동률이면 먼저 집계된
///   카테고리를 우선한다).
final profileStatsSummaryProvider =
    FutureProvider.autoDispose<ProfileStatsSummary>((ref) async {
      // 완독 처리·쪽수/카테고리 수정 등 로컬 DB 변경 후 재계산되도록
      // bookshelfSyncVersionProvider를 구독한다(다른 서재 파생 provider와 동일한
      // 패턴, bookshelf_providers.dart 참고). 프로필 탭은 IndexedStack에 계속
      // 마운트돼 있어 이 구독 없이는 최초 계산 값이 세션 내내 캐시된다.
      ref.watch(bookshelfSyncVersionProvider);
      final repository = ref.watch(bookshelfRepositoryProvider);
      final finished = await repository.getGridTab(BookStatus.finished);

      final totalPages = finished.fold<int>(
        0,
        (sum, item) => sum + (item.statsTotalPages ?? 0),
      );

      final categoryCounts = <int, int>{};
      for (final item in finished) {
        final categoryId = item.displayCategoryId;
        if (categoryId == null) continue;
        categoryCounts[categoryId] = (categoryCounts[categoryId] ?? 0) + 1;
      }

      ProfileMostReadCategory? mostReadCategory;
      if (categoryCounts.isNotEmpty) {
        var bestId = categoryCounts.keys.first;
        var bestCount = categoryCounts[bestId]!;
        for (final entry in categoryCounts.entries) {
          if (entry.value > bestCount) {
            bestId = entry.key;
            bestCount = entry.value;
          }
        }
        final categories = await repository.getCachedCategories();
        for (final category in categories) {
          if (category.id == bestId) {
            mostReadCategory = ProfileMostReadCategory(
              categoryId: category.id,
              categoryName: category.name,
              colorHex: category.colorHex,
            );
            break;
          }
        }
      }

      return ProfileStatsSummary(
        finishedCount: finished.length,
        totalPages: totalPages,
        mostReadCategory: mostReadCategory,
      );
    });
