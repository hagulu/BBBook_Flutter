import 'dart:io';

import '../../book_note/models/book_note.dart';
import '../../book_reflection/models/book_reflection.dart';
import '../../bookshelf/models/book_item.dart';
import '../../tag/models/tag_mapping.dart';
import '../models/record_import_models.dart';

/// 본문에 넣을 `local://` placeholder 하나와 그 실제 파일.
class ReflectionImagePlaceholder {
  const ReflectionImagePlaceholder({
    required this.placeholder,
    required this.file,
    required this.localImagePath,
  });

  final String placeholder;
  final File file;

  /// `reflection_images/<파일명>` 상대 경로. attachments 업로드가 끝난 뒤
  /// `reflection_image_local` 매칭을 새로 남길 때 그대로 쓴다.
  final String localImagePath;
}

/// 독후감 한 건과, items 요청에 실제로 실어 보낼(placeholder 치환이 끝난)
/// `contentJson`.
class ReflectionForImport {
  const ReflectionForImport({
    required this.reflection,
    required this.contentJsonForImport,
  });

  final BookReflection reflection;
  final Map<String, dynamic> contentJsonForImport;
}

/// Import 전 로컬 DB를 한 번 훑어 만든, 서버로 보낼 전체 스냅샷.
///
/// 6개 배열은 이미 "보낼 것만" 걸러진 상태다(삭제된 행 제외, 내용 없는
/// 제목 전용 유령 노트 제외, 숨김 처리된 독후감 제외 등 —
/// [RecordImportSnapshotBuilder] 참고).
class RecordImportSnapshot {
  const RecordImportSnapshot({
    required this.books,
    required this.tags,
    required this.notes,
    required this.noteMemos,
    required this.reflections,
    required this.tagMaps,
    required this.pendingMemoImages,
    this.fallbackMemoImages = const {},
    required this.pendingReflectionImages,
  });

  final List<BookItem> books;
  final List<LocalTag> tags;
  final List<BookNote> notes;
  final List<BookNoteMemo> noteMemos;
  final List<ReflectionForImport> reflections;
  final List<TagMapping> tagMaps;

  /// PHOTO 메모 localId → 다시 올릴 로컬 사진 파일. 로컬 `imageUrl`이 없어
  /// 무조건 새로 올려야 하는 메모만 담는다.
  final Map<int, File> pendingMemoImages;

  /// PHOTO 메모 localId → 로컬 사진 파일(있을 때만). 로컬 `imageUrl`이 이미
  /// 있어 평소에는 기존 연결이 그대로 유지될 것으로 보고 올리지 않지만,
  /// `/items` 응답이 실제로는 `created: true`(완전히 새 행)로 알려주면 —
  /// 예를 들어 서버가 이 계정의 오래된 소프트 삭제 행을 이미 물리 정리해
  /// "복원"이 아니라 "신규 생성"이 된 경우 — 새 행에는 사진이 전혀 연결돼
  /// 있지 않으므로 여기서 예비로 들고 있던 파일을 올려야 한다
  /// ([ServerStorageMigrationService]가 `created` 값을 보고 결정한다).
  final Map<int, File> fallbackMemoImages;

  /// 독후감 localId → 본문에 심은 placeholder들.
  final Map<int, List<ReflectionImagePlaceholder>> pendingReflectionImages;

  /// `/complete` 요청 건수(6개 배열 길이 그대로 — 청크 응답이 아니라 우리가
  /// 실제로 보낸 로컬 배열 기준이라야 재전송 등으로 부풀려지지 않는다).
  RecordImportCounts get counts => RecordImportCounts(
    bookCount: books.length,
    noteCount: notes.length,
    noteMemoCount: noteMemos.length,
    reflectionCount: reflections.length,
    tagCount: tags.length,
    tagMapCount: tagMaps.length,
  );
}

/// [RecordImportSnapshotBuilder.build]의 결과. 성공이면 [snapshot]을,
/// 실패면 사용자에게 그대로 보여줄 수 있는 간결한 [failureMessage]를 담는다.
class RecordImportPreflightOutcome {
  const RecordImportPreflightOutcome._({this.snapshot, this.failureMessage});

  factory RecordImportPreflightOutcome.success(RecordImportSnapshot snapshot) {
    return RecordImportPreflightOutcome._(snapshot: snapshot);
  }

  factory RecordImportPreflightOutcome.failure(String message) {
    return RecordImportPreflightOutcome._(failureMessage: message);
  }

  final RecordImportSnapshot? snapshot;
  final String? failureMessage;

  bool get isSuccess => snapshot != null;
}
