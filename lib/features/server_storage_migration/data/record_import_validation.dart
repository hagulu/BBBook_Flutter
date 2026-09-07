import '../../book_note/models/book_note.dart';
import '../../bookshelf/models/book_item.dart';
import '../../tag/models/tag_mapping.dart';
import 'record_import_snapshot.dart';

/// 문서에 명시된 서버 400/롤백 조건 중, 로컬 우선 편집 데이터에서 실제로
/// 발생할 수 있는 항목만 미리 확인하는 순수 함수(네트워크·DB 접근 없음 —
/// 그래서 단위 테스트로만 검증한다). 위반이 있으면 사용자에게 그대로 보여줄
/// 간결한 메시지를, 없으면 null을 반환한다.
///
/// 이미지 파일 자체(용량·형식)는 실제 파일을 열어야 하는 검사라 여기 대신
/// [RecordImportSnapshotBuilder]가 처리한다.
String? validateRecordImportSnapshot({
  required List<BookItem> books,
  required List<BookNote> notes,
  required List<BookNoteMemo> memos,
  required List<ReflectionForImport> reflections,
  required List<LocalTag> tags,
  required List<TagMapping> tagMaps,
}) {
  for (final book in books) {
    if (book.title.length > 255 ||
        (book.author?.length ?? 0) > 255 ||
        (book.publisher?.length ?? 0) > 255 ||
        (book.isbn13?.length ?? 0) > 13 ||
        (book.shortReview?.length ?? 0) > 150 ||
        (book.sourceType?.length ?? 0) > 30 ||
        (book.difficulty?.length ?? 0) > 30 ||
        (book.platformName?.length ?? 0) > 50 ||
        (book.discoverySource?.length ?? 0) > 50) {
      return '일부 책 기록의 글자 수가 서버 제한을 넘어 가져올 수 없습니다.';
    }
    if (book.myRating != null && (book.myRating! < 0 || book.myRating! > 5)) {
      return '일부 책의 별점 값이 올바르지 않아 가져올 수 없습니다.';
    }
    final upperBound = book.isAudioBook ? 100 : book.effectiveTotalPages;
    if (upperBound != null && book.currentPage > upperBound) {
      return '일부 책의 진행 상태가 총 쪽수를 넘어 가져올 수 없습니다.';
    }
  }
  if (_hasDuplicate(books.map((b) => b.clientRequestId))) {
    return '책 기록 데이터에 중복된 식별자가 있어 가져올 수 없습니다.';
  }

  for (final note in notes) {
    if ((note.title?.length ?? 0) > 255) {
      return '일부 노트의 제목이 너무 길어 가져올 수 없습니다.';
    }
    final hasMemo = memos.any((m) => m.noteId == note.id);
    if (!hasMemo && note.serverId == null) {
      final title = note.title?.trim();
      if (title == null || title.isEmpty) {
        return '내용 없는 노트가 있어 가져올 수 없습니다.';
      }
    }
  }

  for (final memo in memos) {
    if (memo.sortOrder < 0) return '일부 메모의 정렬 값이 올바르지 않습니다.';
    if (memo.startPage != null && memo.startPage! < 1) {
      return '일부 메모의 쪽수 값이 올바르지 않습니다.';
    }
    if (memo.endPage != null && memo.endPage! < 1) {
      return '일부 메모의 쪽수 값이 올바르지 않습니다.';
    }
    if (memo.startPage != null &&
        memo.endPage != null &&
        memo.startPage! > memo.endPage!) {
      return '일부 메모의 쪽수 범위가 올바르지 않습니다.';
    }
  }
  if (_hasDuplicate(memos.map((m) => m.clientRequestId))) {
    return '메모 데이터에 중복된 식별자가 있어 가져올 수 없습니다.';
  }

  for (final reflection in reflections) {
    final r = reflection.reflection;
    final title = r.title?.trim();
    if (title == null || title.isEmpty || r.contentText == null) {
      return '내용 없는 독후감이 있어 가져올 수 없습니다.';
    }
  }
  if (_hasDuplicate(reflections.map((r) => r.reflection.clientRequestId))) {
    return '독후감 데이터에 중복된 식별자가 있어 가져올 수 없습니다.';
  }

  for (final tag in tags) {
    if (tag.name.length > 15) return '일부 태그의 이름이 너무 길어 가져올 수 없습니다.';
  }
  // 같은 이름의 활성 태그가 둘 이상이면 서버는 `(userId, name)` findOrCreate로
  // 같은 서버 태그에 두 로컬 localId를 매핑하게 되어 "로컬-서버 1:1 규칙
  // 위반"으로 400을 반환한다(§ items 문서 tags[n] 규격).
  if (_hasDuplicate(tags.map((t) => t.name))) {
    return '이름이 같은 태그가 있어 가져올 수 없습니다.';
  }

  final tagCountByBook = <int, int>{};
  final tagMapPairs = <String>{};
  for (final map in tagMaps) {
    tagCountByBook[map.userBookId] = (tagCountByBook[map.userBookId] ?? 0) + 1;
    // (userBookId, tagId) 중복도 같은 이유(findOrCreate 1:1 규칙)로 400이다.
    if (!tagMapPairs.add('${map.userBookId}:${map.tagId}')) {
      return '같은 책-태그 연결이 중복돼 있어 가져올 수 없습니다.';
    }
  }
  if (tagCountByBook.values.any((count) => count > 10)) {
    return '한 책에 태그가 10개를 넘어 가져올 수 없습니다. 태그를 정리한 뒤 다시 시도해 주세요.';
  }

  return null;
}

bool _hasDuplicate(Iterable<String?> values) {
  final seen = <String>{};
  for (final value in values) {
    if (value == null) continue;
    if (!seen.add(value)) return true;
  }
  return false;
}
