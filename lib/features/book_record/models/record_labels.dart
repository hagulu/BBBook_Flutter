import 'package:flutter/material.dart';

import '../../bookshelf/models/book_status.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// 책 기록 화면에서 쓰는 상태/출처/난이도 표시용 한글 라벨 + 아이콘.
/// `book-record.md` 기준 문구(읽고 싶음/읽는 중/완독/멈춤/중단). 출처 라벨은
/// api-doc의 "종이책 기준 쪽수"(statsTotalPages) 표현과 맞춰 종이책/전자책/
/// 오디오북으로 통일한다.
extension BookStatusLabel on BookStatus {
  String get label => switch (this) {
    BookStatus.wantToRead => '읽고 싶음',
    BookStatus.reading => '읽는 중',
    BookStatus.finished => '완독',
    BookStatus.paused => '멈춤',
    BookStatus.stopped => '중단',
  };

  IconData get icon => switch (this) {
    BookStatus.wantToRead => PhosphorIconsRegular.bookmarkSimple,
    BookStatus.reading => PhosphorIconsRegular.bookOpen,
    BookStatus.finished => PhosphorIconsRegular.checkCircle,
    BookStatus.paused => PhosphorIconsRegular.pauseCircle,
    BookStatus.stopped => PhosphorIconsRegular.xCircle,
  };
}

/// 서버 값(PAPER_BOOK 등)과 1:1 매핑되는 출처. book-record.md에는 종이책/전자책/
/// 오디오북 3종만 명시되어 있어(LIBRARY 미노출), 이 화면에서도 3종만 다룬다.
enum BookSourceType {
  paperBook,
  ebook,
  audioBook;

  static BookSourceType? fromApiValue(String? value) => switch (value) {
    'PAPER_BOOK' => BookSourceType.paperBook,
    'EBOOK' => BookSourceType.ebook,
    'AUDIO_BOOK' => BookSourceType.audioBook,
    _ => null,
  };

  String get apiValue => switch (this) {
    BookSourceType.paperBook => 'PAPER_BOOK',
    BookSourceType.ebook => 'EBOOK',
    BookSourceType.audioBook => 'AUDIO_BOOK',
  };

  String get label => switch (this) {
    BookSourceType.paperBook => '종이책',
    BookSourceType.ebook => '전자책',
    BookSourceType.audioBook => '오디오북',
  };

  IconData get icon => switch (this) {
    BookSourceType.paperBook => PhosphorIconsRegular.bookOpen,
    BookSourceType.ebook => PhosphorIconsRegular.deviceTablet,
    BookSourceType.audioBook => PhosphorIconsRegular.headphones,
  };

  /// `GET /api/books/options`의 `platforms` 맵 키(api-books-options-get.md
  /// 기준 `EBOOK`/`AUDIO_BOOK` — sourceType 값과 동일한 문자열이다).
  String? get platformOptionsKey => switch (this) {
    BookSourceType.ebook => 'EBOOK',
    BookSourceType.audioBook => 'AUDIO_BOOK',
    BookSourceType.paperBook => null,
  };
}

/// 난이도 3단계. 실제 웹 클라이언트(`front/bbbook/.../BookRecordPage.tsx`의
/// `DIFFICULTY_OPTIONS`)는 `EASY`/`MODERATE`/`HARD`를 API 저장값으로 쓰고
/// 한글은 표시할 때만 매핑한다 — `api-doc`에는 "자유 텍스트"로만 적혀 있지만,
/// 실제 저장값 규격은 이 3개 상수와 맞춰야 다른 클라이언트(웹)와 데이터가
/// 호환된다.
enum DifficultyLevel {
  easy,
  moderate,
  hard;

  static DifficultyLevel? fromApiValue(String? value) => switch (value) {
    'EASY' => DifficultyLevel.easy,
    'MODERATE' => DifficultyLevel.moderate,
    'HARD' => DifficultyLevel.hard,
    _ => null,
  };

  String get apiValue => switch (this) {
    DifficultyLevel.easy => 'EASY',
    DifficultyLevel.moderate => 'MODERATE',
    DifficultyLevel.hard => 'HARD',
  };

  String get label => switch (this) {
    DifficultyLevel.easy => '쉬움',
    DifficultyLevel.moderate => '보통',
    DifficultyLevel.hard => '어려움',
  };

  IconData get icon => switch (this) {
    DifficultyLevel.easy => PhosphorIconsRegular.smiley,
    DifficultyLevel.moderate => PhosphorIconsRegular.smileyMeh,
    DifficultyLevel.hard => PhosphorIconsRegular.smileyMelting,
  };
}
