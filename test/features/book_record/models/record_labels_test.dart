import 'package:bbbook/features/book_record/models/record_labels.dart';
import 'package:flutter_test/flutter_test.dart';

/// `GET /api/books/options`의 `platforms` 맵 키(api-books-options-get.md:
/// `EBOOK`/`AUDIO_BOOK`)와 [BookSourceType.platformOptionsKey]가 정확히
/// 일치하는지 확인한다 — 어긋나면 플랫폼 목록 조회 결과에서 해당 출처의
/// 옵션을 절대 찾지 못한다(항상 빈 목록).
void main() {
  test('platformOptionsKey는 서버 platforms 맵 키와 정확히 일치한다', () {
    expect(BookSourceType.ebook.platformOptionsKey, 'EBOOK');
    expect(BookSourceType.audioBook.platformOptionsKey, 'AUDIO_BOOK');
    expect(BookSourceType.paperBook.platformOptionsKey, isNull);
  });

  test('apiValue와 fromApiValue는 서로 왕복 변환된다', () {
    for (final source in BookSourceType.values) {
      expect(BookSourceType.fromApiValue(source.apiValue), source);
    }
  });
}
