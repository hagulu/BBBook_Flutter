import 'package:bbbook/features/bookshelf/models/book_item.dart';
import 'package:bbbook/features/bookshelf/models/book_status.dart';
import 'package:flutter_test/flutter_test.dart';

/// 책 형태(종이책/전자책/오디오북)별 진행률 계산 규칙 테스트.
///
/// 실제 진행률 계산 기준은 `displayTotalPages ?? statsTotalPages`이고,
/// 오디오북은 `currentPage` 자체를 0~100 진행률 값으로 쓴다
/// (api-me-books-userBookId-patch.md 기준).
void main() {
  BookItem book({
    required int currentPage,
    int? statsTotalPages,
    int? displayTotalPages,
    String? sourceType,
  }) {
    final now = DateTime.utc(2026, 8, 24);
    return BookItem(
      userBookId: 1,
      title: '테스트 책',
      statsTotalPages: statsTotalPages,
      displayTotalPages: displayTotalPages,
      status: BookStatus.reading,
      currentPage: currentPage,
      isMasterpiece: false,
      sourceType: sourceType,
      rereadCount: 0,
      tags: const [],
      createdAt: now,
      updatedAt: now,
    );
  }

  group('종이책', () {
    test('statsTotalPages 기준으로 진행률을 계산한다', () {
      final b = book(currentPage: 120, statsTotalPages: 360);
      expect(b.effectiveTotalPages, 360);
      expect(b.progressUpperBound, 360);
      expect(b.progressRatio, closeTo(1 / 3, 0.0001));
    });

    test('총쪽수를 모르면 진행률이 null이다', () {
      final b = book(currentPage: 50);
      expect(b.effectiveTotalPages, isNull);
      expect(b.progressRatio, isNull);
    });
  });

  group('전자책', () {
    test('displayTotalPages가 있으면 그 값을 기준으로 계산한다', () {
      final b = book(
        currentPage: 120,
        statsTotalPages: 300,
        displayTotalPages: 360,
        sourceType: 'EBOOK',
      );
      expect(b.effectiveTotalPages, 360);
      expect(b.progressRatio, closeTo(1 / 3, 0.0001));
    });

    test('displayTotalPages가 없으면 statsTotalPages로 fallback한다', () {
      final b = book(
        currentPage: 90,
        statsTotalPages: 360,
        sourceType: 'EBOOK',
      );
      expect(b.effectiveTotalPages, 360);
      expect(b.progressRatio, closeTo(0.25, 0.0001));
    });
  });

  group('오디오북', () {
    test('currentPage를 그대로 0~100 퍼센트로 취급하고 통계용 쪽수는 무시한다', () {
      final b = book(
        currentPage: 35,
        statsTotalPages: 300,
        sourceType: 'AUDIO_BOOK',
      );
      expect(b.isAudioBook, isTrue);
      expect(b.progressUpperBound, 100);
      expect(b.progressRatio, closeTo(0.35, 0.0001));
    });

    test('0~100 범위를 벗어나는 값은 clamp한다', () {
      final over = book(currentPage: 150, sourceType: 'AUDIO_BOOK');
      expect(over.progressRatio, 1.0);
    });
  });

  group('normalizedCurrentPageForSourceChange', () {
    test('출처가 실제로 바뀌고 진행 기록이 있으면 0으로 초기화한다', () {
      final b = book(currentPage: 90, statsTotalPages: 360);
      final normalized = b.normalizedCurrentPageForSourceChange(
        newSourceType: 'AUDIO_BOOK',
      );
      expect(normalized, 0);
    });

    test('오디오북에서 페이지 기반으로 바꿔도 진행 기록이 있으면 0으로 초기화한다', () {
      final b = book(currentPage: 80, sourceType: 'AUDIO_BOOK');
      final normalized = b.normalizedCurrentPageForSourceChange(
        newSourceType: 'EBOOK',
      );
      expect(normalized, 0);
    });

    test('출처가 그대로면 값을 그대로 유지한다', () {
      final b = book(currentPage: 90, statsTotalPages: 360, sourceType: 'EBOOK');
      final normalized = b.normalizedCurrentPageForSourceChange(
        newSourceType: 'EBOOK',
      );
      expect(normalized, 90);
    });

    test('출처가 바뀌어도 진행 기록이 없으면(0) 그대로 0이다', () {
      final b = book(currentPage: 0, statsTotalPages: 360);
      final normalized = b.normalizedCurrentPageForSourceChange(
        newSourceType: 'AUDIO_BOOK',
      );
      expect(normalized, 0);
    });
  });

  test('BookItem.fromDetailJson이 statsTotalPages/displayTotalPages를 파싱한다', () {
    final json = {
      'userBookId': 1,
      'title': '테스트 책',
      'statsTotalPages': 300,
      'displayTotalPages': 360,
      'status': 'READING',
      'currentPage': 100,
      'isMasterpiece': false,
      'rereadCount': 0,
      'updatedAt': '2026-08-24T00:00:00Z',
    };
    final parsed = BookItem.fromDetailJson(
      json,
      createdAt: DateTime.utc(2026, 8, 1),
    );
    expect(parsed.statsTotalPages, 300);
    expect(parsed.displayTotalPages, 360);
    expect(parsed.effectiveTotalPages, 360);
  });

  test('BookItem.fromSyncJson이 statsTotalPages/displayTotalPages를 파싱한다', () {
    final json = {
      'userBookId': 1,
      'title': '테스트 책',
      'statsTotalPages': 300,
      'displayTotalPages': null,
      'status': 'READING',
      'currentPage': 100,
      'isMasterpiece': false,
      'rereadCount': 0,
      'createdAt': '2026-08-01T00:00:00Z',
      'updatedAt': '2026-08-24T00:00:00Z',
    };
    final parsed = BookItem.fromSyncJson(json);
    expect(parsed.statsTotalPages, 300);
    expect(parsed.displayTotalPages, isNull);
    expect(parsed.effectiveTotalPages, 300);
  });
}
