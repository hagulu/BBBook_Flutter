import '../../book_note/models/book_note.dart';
import '../../bookshelf/models/book_item.dart';
import '../../bookshelf/models/record_patch.dart';
import '../../tag/models/tag_mapping.dart';
import 'record_import_snapshot.dart';

/// [RecordImportSnapshot]의 각 로컬 모델을 `/items` 요청 JSON 항목으로
/// 바꾸는 순수 함수 모음(네트워크·DB 접근 없음 — 그래서 단위 테스트로만
/// 검증한다).

Map<String, dynamic> bookToImportJson(BookItem item) {
  return {
    'localId': item.userBookId,
    'serverId': item.serverId,
    'clientRequestId': item.clientRequestId,
    // 직접 등록한 커스텀 책의 로컬 표지 파일 경로는 서버가 받을 수 있는
    // 형식이 아니다(API는 문자열 URL만 받고 파일 업로드를 지원하지 않는다).
    // 사용자 확인에 따라 표지 없이 Import하고, 표지는 이후 책 정보 수정
    // 화면에서 다시 설정하도록 안내한다.
    'coverImageUrl': _remoteCoverUrlOrNull(item.coverImageUrl),
    'isbn13': item.isbn13,
    'title': item.title,
    'author': item.author,
    'publisher': item.publisher,
    'statsTotalPages': item.statsTotalPages,
    'displayTotalPages': item.displayTotalPages,
    'displayCategoryId': item.displayCategoryId,
    'status': item.status.apiValue,
    'currentPage': item.currentPage,
    'myRating': item.myRating,
    'shortReview': item.shortReview,
    'isMasterpiece': item.isMasterpiece,
    'sourceType': item.sourceType,
    'rereadCount': item.rereadCount,
    'wantToReread': item.wantToReread,
    'difficulty': item.difficulty,
    'startedAt': RecordPatch.formatApiDate(item.startedAt),
    'finishedAt': RecordPatch.formatApiDate(item.finishedAt),
    'libraryId': item.libraryId,
    'libraryDueAt': RecordPatch.formatApiDate(item.libraryDueAt),
    'platformName': item.platformName,
    'discoverySource': item.discoverySource,
  };
}

String? _remoteCoverUrlOrNull(String? coverImageUrl) {
  if (coverImageUrl == null) return null;
  final isRemote =
      coverImageUrl.startsWith('http://') ||
      coverImageUrl.startsWith('https://');
  return isRemote ? coverImageUrl : null;
}

Map<String, dynamic> noteToImportJson(BookNote note) {
  return {
    'localId': note.id,
    'serverId': note.serverId,
    'localUserBookId': note.userBookId,
    'title': note.title,
  };
}

Map<String, dynamic> noteMemoToImportJson(BookNoteMemo memo) {
  return {
    'localId': memo.id,
    'serverId': memo.serverId,
    'clientRequestId': memo.clientRequestId,
    'localNoteId': memo.noteId,
    'memoType': memo.type.dbValue,
    'startPage': memo.startPage,
    'endPage': memo.endPage,
    'content': memo.content,
    // PHOTO 타입은 이 Import가 항상 로컬 사진을 다시 올린다
    // (`RecordImportSnapshotBuilder` — 오래된 서버 URL을 그대로 믿지 않고
    // 항상 로컬 파일을 새로 업로드해 사진이 세션 소유 경로에 확실히
    // 존재하게 한다). 그 외 타입은 서버가 이 필드를 저장하지 않는다.
    'imageUrl': null,
    'isImportant': memo.isImportant,
    'sortOrder': memo.sortOrder,
  };
}

Map<String, dynamic> reflectionToImportJson(ReflectionForImport reflection) {
  final r = reflection.reflection;
  return {
    'localId': r.id,
    'serverId': r.serverId,
    'clientRequestId': r.clientRequestId,
    'localUserBookId': r.userBookId,
    'reflectionType': r.reflectionType,
    'title': r.title,
    'contentJson': reflection.contentJsonForImport,
    'contentText': r.contentText,
    'isPublic': r.isPublic,
  };
}

Map<String, dynamic> tagToImportJson(LocalTag tag) {
  return {'localId': tag.id, 'name': tag.name};
}

Map<String, dynamic> tagMapToImportJson(TagMapping mapping) {
  return {
    'localId': mapping.id,
    'localUserBookId': mapping.userBookId,
    'localTagId': mapping.tagId,
  };
}

/// `/items` 요청 한 번(청크)에 실릴 6개 배열.
class RecordImportChunk {
  const RecordImportChunk({
    this.books = const [],
    this.tags = const [],
    this.notes = const [],
    this.noteMemos = const [],
    this.reflections = const [],
    this.tagMaps = const [],
  });

  final List<Map<String, dynamic>> books;
  final List<Map<String, dynamic>> tags;
  final List<Map<String, dynamic>> notes;
  final List<Map<String, dynamic>> noteMemos;
  final List<Map<String, dynamic>> reflections;
  final List<Map<String, dynamic>> tagMaps;

  int get itemCount =>
      books.length +
      tags.length +
      notes.length +
      noteMemos.length +
      reflections.length +
      tagMaps.length;

  Map<String, dynamic> toJson() => {
    'books': books,
    'tags': tags,
    'notes': notes,
    'noteMemos': noteMemos,
    'reflections': reflections,
    'tagMaps': tagMaps,
  };
}

/// 6개 배열을 `maxChunkItemCount`(문서 — `/start` 응답 값, 하드코딩 금지)
/// 이하로 묶어 청크 목록을 만든다.
///
/// books → tags → notes → noteMemos → reflections → tagMaps 순서를 절대
/// 흩트리지 않는다(카테고리 내부·경계 모두) — 이 순서를 지키면 어떤 항목이
/// 자신의 부모(`localUserBookId`/`localNoteId`/`localTagId`)보다 앞서
/// 등장하는 청크가 생길 수 없다. 문서는 "같은 청크 안에서 완결되지 않아도
/// 되며 이전 청크에서 이미 매핑된 부모를 참조할 수 있다"고 허용하므로,
/// 여러 카테고리를 한 청크에 채워 넣는 것도 안전하다.
List<RecordImportChunk> buildRecordImportChunks({
  required List<Map<String, dynamic>> books,
  required List<Map<String, dynamic>> tags,
  required List<Map<String, dynamic>> notes,
  required List<Map<String, dynamic>> noteMemos,
  required List<Map<String, dynamic>> reflections,
  required List<Map<String, dynamic>> tagMaps,
  required int maxChunkItemCount,
}) {
  assert(maxChunkItemCount > 0);
  final chunks = <RecordImportChunk>[];
  var currentBooks = <Map<String, dynamic>>[];
  var currentTags = <Map<String, dynamic>>[];
  var currentNotes = <Map<String, dynamic>>[];
  var currentMemos = <Map<String, dynamic>>[];
  var currentReflections = <Map<String, dynamic>>[];
  var currentTagMaps = <Map<String, dynamic>>[];
  var currentCount = 0;

  void flush() {
    if (currentCount == 0) return;
    chunks.add(
      RecordImportChunk(
        books: currentBooks,
        tags: currentTags,
        notes: currentNotes,
        noteMemos: currentMemos,
        reflections: currentReflections,
        tagMaps: currentTagMaps,
      ),
    );
    currentBooks = [];
    currentTags = [];
    currentNotes = [];
    currentMemos = [];
    currentReflections = [];
    currentTagMaps = [];
    currentCount = 0;
  }

  void addAll(
    List<Map<String, dynamic>> items,
    void Function(Map<String, dynamic> item) add,
  ) {
    for (final item in items) {
      if (currentCount >= maxChunkItemCount) flush();
      add(item);
      currentCount++;
    }
  }

  // `currentBooks.add`처럼 메서드를 미리 떼어 넘기면 안 된다 — [flush]가
  // `currentBooks = []`로 변수를 재할당해도, 이미 떼어낸 tear-off는 재할당
  // 전의 옛 리스트 인스턴스에 계속 붙는다. 호출 시점마다 현재 변수 값을
  // 다시 읽도록 클로저로 감싼다.
  addAll(books, (item) => currentBooks.add(item));
  addAll(tags, (item) => currentTags.add(item));
  addAll(notes, (item) => currentNotes.add(item));
  addAll(noteMemos, (item) => currentMemos.add(item));
  addAll(reflections, (item) => currentReflections.add(item));
  addAll(tagMaps, (item) => currentTagMaps.add(item));
  flush();
  return chunks;
}
