enum BookNoteMemoType {
  summary('SUMMARY', '요약'),
  quote('QUOTE', '발췌'),
  thought('THOUGHT', '생각'),
  photo('PHOTO', '사진');

  const BookNoteMemoType(this.dbValue, this.label);

  final String dbValue;
  final String label;

  static BookNoteMemoType fromDb(String value) {
    return BookNoteMemoType.values.firstWhere(
      (type) => type.dbValue == value,
      orElse: () => throw FormatException('Unknown note memo type: $value'),
    );
  }
}

class BookNote {
  const BookNote({
    required this.id,
    required this.serverId,
    required this.userBookId,
    required this.title,
    required this.deletedAt,
    required this.createdAt,
    required this.updatedAt,
    required this.isDirty,
  });

  final int id;

  /// 서버에 반영된 뒤 서버가 내려준 실제 노트 ID. null이면 아직 서버에 한
  /// 번도 반영되지 못한 로컬 전용 행이라는 뜻이다(`id`는 오프라인 임시
  /// 음수값). PATCH/DELETE 등 서버 호출은 반드시 이 값을 써야 한다.
  /// `id`와 다른 별도 컬럼인 이유는 `BookshelfDatabase._createRecordTables`
  /// 참고.
  final int? serverId;
  final int userBookId;
  final String? title;
  final DateTime? deletedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDirty;
}

class BookNoteMemo {
  const BookNoteMemo({
    required this.id,
    required this.serverId,
    required this.clientRequestId,
    required this.noteId,
    required this.type,
    required this.startPage,
    required this.endPage,
    required this.content,
    required this.imageUrl,
    required this.localImagePath,
    required this.isImportant,
    required this.sortOrder,
    required this.deletedAt,
    required this.createdAt,
    required this.updatedAt,
    required this.isDirty,
  });

  final int id;

  /// 서버 메모 ID. null이면 아직 서버에 반영되지 못한 로컬 전용 메모다.
  /// [BookNote.serverId] 참고.
  final int? serverId;

  /// 로컬 CREATE 시 한 번 생성해 저장하는 멱등 UUID. 기존 로컬/서버 동기화
  /// 데이터는 null일 수 있으며 UPDATE에는 새 값을 만들거나 전송하지 않는다.
  final String? clientRequestId;
  final int noteId;
  final BookNoteMemoType type;
  final int? startPage;
  final int? endPage;
  final String? content;

  /// 서버가 내려준 사진 전체 URL. PHOTO 메모인데 null이면 "아직 서버에
  /// 올리지 못한 로컬 사진"이라는 뜻이라, dirty push가 업로드 대상을
  /// 판별하는 기준이 된다.
  final String? imageUrl;

  /// 로컬에 보관 중인 사진의 상대 경로(`memo_images/<파일명>`). 서버에는
  /// 존재하지 않는 로컬 전용 값이며, 실제 파일은 `noteMemoImageStore`로
  /// 열어야 한다(절대 경로는 iOS에서 앱 업데이트마다 바뀐다).
  final String? localImagePath;
  final bool isImportant;
  final int sortOrder;
  final DateTime? deletedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDirty;

  /// 로컬 사본이든 서버 URL이든 보여줄 사진이 있는지 여부.
  bool get hasImage => localImagePath != null || imageUrl != null;

  String? get pageLabel {
    if (startPage == null && endPage == null) return null;
    if (startPage == null) return 'p.$endPage';
    if (endPage == null || endPage == startPage) return 'p.$startPage';
    return 'p.$startPage–$endPage';
  }
}

class BookNoteSummary {
  const BookNoteSummary({
    required this.note,
    required this.memoCount,
    required this.firstPage,
    required this.lastPage,
  });

  final BookNote note;
  final int memoCount;
  final int? firstPage;
  final int? lastPage;

  String? get pageLabel {
    if (firstPage == null && lastPage == null) return null;
    if (firstPage == null) return 'p.$lastPage';
    if (lastPage == null || lastPage == firstPage) return 'p.$firstPage';
    return 'p.$firstPage–$lastPage';
  }
}

class BookNoteDetail {
  const BookNoteDetail({required this.note, required this.memos});

  const BookNoteDetail.empty() : note = null, memos = const [];

  final BookNote? note;
  final List<BookNoteMemo> memos;

  BookNoteDetail copyWith({BookNote? note, List<BookNoteMemo>? memos}) {
    return BookNoteDetail(note: note ?? this.note, memos: memos ?? this.memos);
  }
}

/// 메모 수정 시 사진을 어떻게 다룰지. 사진은 편집 폼의 다른 필드와 달리
/// "값을 그대로 되돌려 보내는" 방식이 위험하다 — draft를 만드는 경로가
/// 여러 곳이라(전체 편집 화면·퀵 작성 시트) 한 곳이라도 기존 경로를
/// 옮겨 담는 걸 빠뜨리면 사진이 조용히 사라진다. 그래서 값 대신 "그대로
/// 둠 / 새 사진으로 교체 / 제거" 의사만 전달하고, 실제 컬럼은 Repository와
/// DAO가 그 의사에 따라서만 건드린다.
enum MemoImageChange { unchanged, replaced, cleared }

class BookNoteMemoDraft {
  const BookNoteMemoDraft({
    required this.type,
    this.startPage,
    this.endPage,
    this.content,
    this.pickedImagePath,
    this.imageChange = MemoImageChange.unchanged,
    this.isImportant = false,
  });

  final BookNoteMemoType type;
  final int? startPage;
  final int? endPage;
  final String? content;

  /// 새로 선택한 사진의 임시 경로([imageChange]가 [MemoImageChange.replaced]
  /// 일 때만 채운다). Repository가 `noteMemoImageStore`로 복사한 뒤 그
  /// 상대 경로만 `book_note_memo.local_image_path`에 저장한다.
  final String? pickedImagePath;
  final MemoImageChange imageChange;
  final bool isImportant;
}

class DeleteNoteMemoResult {
  const DeleteNoteMemoResult({required this.noteWasDeleted});

  final bool noteWasDeleted;
}
