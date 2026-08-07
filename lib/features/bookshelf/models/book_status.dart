/// 독서 상태. 서버 값(`WANT_TO_READ` 등)과 1:1 매핑된다.
enum BookStatus {
  wantToRead,
  reading,
  finished,
  paused,
  stopped;

  static BookStatus fromApiValue(String value) => switch (value) {
    'WANT_TO_READ' => BookStatus.wantToRead,
    'READING' => BookStatus.reading,
    'FINISHED' => BookStatus.finished,
    'PAUSED' => BookStatus.paused,
    'STOPPED' => BookStatus.stopped,
    _ => throw ArgumentError('알 수 없는 독서 상태: $value'),
  };

  String get apiValue => switch (this) {
    BookStatus.wantToRead => 'WANT_TO_READ',
    BookStatus.reading => 'READING',
    BookStatus.finished => 'FINISHED',
    BookStatus.paused => 'PAUSED',
    BookStatus.stopped => 'STOPPED',
  };
}
