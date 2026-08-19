enum BookMemoItemType {
  summary('SUMMARY', '요약'),
  quote('QUOTE', '발췌'),
  thought('THOUGHT', '생각'),
  photo('PHOTO', '사진');

  const BookMemoItemType(this.dbValue, this.label);

  final String dbValue;
  final String label;

  static BookMemoItemType fromDb(String value) {
    return BookMemoItemType.values.firstWhere(
      (type) => type.dbValue == value,
      orElse: () => throw FormatException('Unknown memo item type: $value'),
    );
  }
}

class BookMemo {
  const BookMemo({
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

  /// 서버에 반영된 뒤 서버가 내려준 실제 메모 ID. null이면 아직 서버에 한
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

class BookMemoItem {
  const BookMemoItem({
    required this.id,
    required this.serverId,
    required this.clientRequestId,
    required this.memoId,
    required this.type,
    required this.startPage,
    required this.endPage,
    required this.content,
    required this.imageUrl,
    required this.isImportant,
    required this.sortOrder,
    required this.deletedAt,
    required this.createdAt,
    required this.updatedAt,
    required this.isDirty,
  });

  final int id;

  /// 서버 조각 ID. null이면 아직 서버에 반영되지 못한 로컬 전용 조각이다.
  /// [BookMemo.serverId] 참고.
  final int? serverId;

  /// 로컬 CREATE 시 한 번 생성해 저장하는 멱등 UUID. 기존 로컬/서버 동기화
  /// 데이터는 null일 수 있으며 UPDATE에는 새 값을 만들거나 전송하지 않는다.
  final String? clientRequestId;
  final int memoId;
  final BookMemoItemType type;
  final int? startPage;
  final int? endPage;
  final String? content;
  final String? imageUrl;
  final bool isImportant;
  final int sortOrder;
  final DateTime? deletedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDirty;

  String? get pageLabel {
    if (startPage == null && endPage == null) return null;
    if (startPage == null) return 'p.$endPage';
    if (endPage == null || endPage == startPage) return 'p.$startPage';
    return 'p.$startPage–$endPage';
  }
}

class BookMemoSummary {
  const BookMemoSummary({
    required this.memo,
    required this.itemCount,
    required this.firstPage,
    required this.lastPage,
  });

  final BookMemo memo;
  final int itemCount;
  final int? firstPage;
  final int? lastPage;

  String? get pageLabel {
    if (firstPage == null && lastPage == null) return null;
    if (firstPage == null) return 'p.$lastPage';
    if (lastPage == null || lastPage == firstPage) return 'p.$firstPage';
    return 'p.$firstPage–$lastPage';
  }
}

class BookMemoDetail {
  const BookMemoDetail({required this.memo, required this.items});

  const BookMemoDetail.empty() : memo = null, items = const [];

  final BookMemo? memo;
  final List<BookMemoItem> items;

  BookMemoDetail copyWith({BookMemo? memo, List<BookMemoItem>? items}) {
    return BookMemoDetail(memo: memo ?? this.memo, items: items ?? this.items);
  }
}

class BookMemoItemDraft {
  const BookMemoItemDraft({
    required this.type,
    this.startPage,
    this.endPage,
    this.content,
    this.imageUrl,
    this.pickedImagePath,
    this.isImportant = false,
  });

  final BookMemoItemType type;
  final int? startPage;
  final int? endPage;
  final String? content;
  final String? imageUrl;

  /// 새로 선택한 이미지의 임시 경로. Repository가 앱 지원 디렉터리로 복사한
  /// 뒤 영속 경로만 `book_memo_item.image_url`에 저장한다.
  final String? pickedImagePath;
  final bool isImportant;
}

class DeleteMemoItemResult {
  const DeleteMemoItemResult({required this.memoWasDeleted});

  final bool memoWasDeleted;
}
