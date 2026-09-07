import 'dart:io';

import 'package:path/path.dart' as path;

import '../../../core/storage/local_image_store.dart';
import '../../book_note/data/book_note_dao.dart';
import '../../book_note/models/book_note.dart';
import '../../book_note/services/note_memo_image_store.dart';
import '../../book_reflection/data/book_reflection_dao.dart';
import '../../book_reflection/services/book_reflection_content_adapter.dart';
import '../../book_reflection/services/reflection_image_store.dart';
import '../../bookshelf/data/bookshelf_dao.dart';
import '../../bookshelf/models/book_status.dart';
import '../../tag/data/tag_dao.dart';
import 'record_import_snapshot.dart';
import 'record_import_validation.dart';

/// Import 직전 로컬 DB를 훑어 [RecordImportSnapshot]을 만든다.
///
/// 여기서 하는 일은 세 가지뿐이다.
/// 1. `clientRequestId` 멱등 키 백필(문서 — Import 전에 로컬 DB에 고정
///    저장해야 한다).
/// 2. 서버 400/롤백을 부르는 조합(내용 없는 제목 전용 노트, 숨김 독후감,
///    되찾을 수 없는 이미지 등)을 미리 걸러낸다 — API 문서의 실패 정책상
///    이런 조합 하나가 세션 전체를 죽이므로, 시작 전에 잡는 게 유일하게
///    안전한 방법이다.
/// 3. 독후감 본문의 로컬 이미지를 `local://` placeholder로 바꾼다(§ items
///    문서 "독후감 이미지 처리").
///
/// 필드 길이 등 나머지 서버 제약은 [validateRecordImportSnapshot]이 문서에
/// 명시된, 로컬/과거 데이터에서 실제로 위반될 수 있는 항목만 다룬다(전체
/// 규격을 그대로 재구현하지 않는다).
class RecordImportSnapshotBuilder {
  const RecordImportSnapshotBuilder({
    required this.ownerUserId,
    required this.bookshelfDao,
    required this.noteDao,
    required this.reflectionDao,
    required this.tagDao,
  });

  final int ownerUserId;
  final BookshelfDao bookshelfDao;
  final BookNoteDao noteDao;
  final BookReflectionDao reflectionDao;
  final TagDao tagDao;

  static const _contentAdapter = BookReflectionContentAdapter();

  Future<RecordImportPreflightOutcome> build() async {
    await bookshelfDao.ensureClientRequestIds();
    await noteDao.ensureMemoClientRequestIds();
    await reflectionDao.ensureClientRequestIds();

    final books = await bookshelfDao.getByStatuses(BookStatus.values);
    final notes = await noteDao.getAllActiveNotes(ownerUserId: ownerUserId);
    final memos = await noteDao.getAllActiveMemos(ownerUserId: ownerUserId);
    final reflectionsRaw = await reflectionDao.getAllActiveForImport(
      ownerUserId: ownerUserId,
    );
    final tags = await tagDao.getAllActiveTags();
    final tagMaps = await tagDao.getAllActiveMappings();

    final memosByNote = <int, List<BookNoteMemo>>{};
    for (final memo in memos) {
      (memosByNote[memo.noteId] ??= []).add(memo);
    }
    // 메모 없고 serverId도 없는 제목 없는 노트는 서버가 400으로 거부한다
    // (§ items 문서 notes[n] 규격). 이 앱의 정상 작성 흐름에서는 생기지
    // 않아야 하는 유령 행이라, 존재해도 그냥 빼고 진행한다.
    final filteredNotes = notes.where((note) {
      final hasMemo = memosByNote[note.id]?.isNotEmpty ?? false;
      if (hasMemo || note.serverId != null) return true;
      return note.title != null && note.title!.trim().isNotEmpty;
    }).toList(growable: false);

    final missingImageReasons = <String>[];
    final pendingMemoImages = <int, File>{};
    final fallbackMemoImages = <int, File>{};
    for (final memo in memos) {
      if (memo.type != BookNoteMemoType.photo) continue;
      // `imageUrl`이 이미 있으면 "Import 이전부터 이미지가 연결돼 있던
      // 메모"다(서버 → 로컬 이전으로 내려받았거나, 다른 세션이 이미 붙인
      // 경우). 이런 메모는 보통 items 요청에서 `imageUrl`을 보내지 않으면
      // (§ noteMemos[n] 규격) 기존 연결이 그대로 유지되므로 다시 올릴
      // 필요가 없다 — 오히려 무조건 다시 올리면 attachments 문서가
      // "Import 이전부터 이미지가 연결된 메모에는 첨부를 거부한다(400)"고
      // 명시해 세션 전체가 정리된다. 로컬 사진 편집(`MemoImageChange.replaced`)은
      // 항상 `image_url`을 즉시 null로 되돌리므로(`BookNoteDao`), null이
      // 아니라는 것은 아직 로컬에서 교체되지 않은 원래 사진이라는 뜻이다.
      //
      // 다만 이 "기존 연결 유지" 가정은 그 서버 행이 여전히 존재할 때만
      // 맞다 — 로컬 저장 모드가 길어져 그 사이 서버가 소프트 삭제된 옛
      // 행을 물리 정리했다면, 이번 Import는 그 메모를 "복원"이 아니라
      // "신규 생성"으로 처리하고 `created: true`를 돌려준다. 그 경우
      // 새 행에는 사진이 전혀 없으므로, 로컬 파일을 찾을 수 있으면 예비로
      // 들고 있다가 실제 `created` 값을 본 뒤([ServerStorageMigrationService])
      // 필요할 때만 올린다. 로컬 파일이 없으면(기기에서 지워짐 등) 예비도
      // 못 만들지만, 이 경우는 무시한다 — 서버 행이 실제로 살아 있다면
      // 문제 없고, 정말 물리 정리됐다면 `/complete`의 이미지 연결 검증이
      // 실패해 세션이 정리되며 다시 시도해도 같은 결과라 사전에 막을 수
      // 없는 조합이다.
      if (memo.imageUrl != null) {
        final file = await noteMemoImageStore.resolve(memo.localImagePath);
        if (file != null && await _isUploadableImage(file)) {
          fallbackMemoImages[memo.id] = file;
        }
        continue;
      }
      final file = await noteMemoImageStore.resolve(memo.localImagePath);
      if (file == null || !await _isUploadableImage(file)) {
        missingImageReasons.add('메모 사진');
        continue;
      }
      pendingMemoImages[memo.id] = file;
    }

    final reflectionsForImport = <ReflectionForImport>[];
    final pendingReflectionImages = <int, List<ReflectionImagePlaceholder>>{};
    for (final reflection in reflectionsRaw) {
      final contentJson = reflection.contentJson;
      if (contentJson == null) continue;
      final sources = _contentAdapter.imageSources(contentJson).toSet();
      if (sources.isEmpty) {
        reflectionsForImport.add(
          ReflectionForImport(
            reflection: reflection,
            contentJsonForImport: contentJson,
          ),
        );
        continue;
      }

      final localPathsByRemote = await reflectionDao.findLocalImagePaths(
        reflection.id,
      );
      final replacements = <String, String>{};
      final placeholders = <ReflectionImagePlaceholder>[];
      var index = 0;
      for (final source in sources) {
        // 서버 URL이든 로컬 상대 경로든, 이 세션은 항상 로컬 사본을 새로
        // 올린다 — 예전 서버 URL은 이 계정이 한 번 로컬 저장 모드로
        // 전환하며 소프트 삭제됐던 옛 독후감의 경로일 수 있어, 파일이
        // 실제로 아직 살아 있는지 클라이언트가 보장할 수 없다.
        final relativePath = LocalImageStore.isRemote(source)
            ? localPathsByRemote[source]
            : source;
        final file = await reflectionImageStore.resolve(relativePath);
        if (file == null || !await _isUploadableImage(file)) {
          missingImageReasons.add('독후감 이미지');
          continue;
        }
        // 같은 로컬 이미지가 본문에 두 번 이상 들어 있으면(값이 같은
        // source) 하나의 placeholder로 합쳐 한 번만 올린다 —
        // `replaceImageSources`가 값이 일치하는 모든 노드를 함께 치환하므로
        // 로컬 재구성은 항상 일관되지만, 서버가 "정확히 일치하는 첫 번째
        // 노드만" 치환하는 구현이라면 두 번째 노드에는 여전히 local://가
        // 남아 `/complete`가 실패할 수 있다(문서는 "노드 중 일치하는 것을
        // 치환"이라고만 적어 개수를 명시하지 않는다). 실제로 그런 사례가
        // 보고되면 소스별이 아니라 노드별 placeholder로 바꿔야 한다.
        final placeholder = 'local://reflection/${reflection.id}/${index++}';
        replacements[source] = placeholder;
        placeholders.add(
          ReflectionImagePlaceholder(
            placeholder: placeholder,
            file: file,
            localImagePath: relativePath!,
          ),
        );
      }
      final contentForImport = _contentAdapter.replaceImageSources(
        contentJson,
        replacements,
      );
      reflectionsForImport.add(
        ReflectionForImport(
          reflection: reflection,
          contentJsonForImport: contentForImport,
        ),
      );
      if (placeholders.isNotEmpty) {
        pendingReflectionImages[reflection.id] = placeholders;
      }
    }

    if (missingImageReasons.isNotEmpty) {
      return RecordImportPreflightOutcome.failure(
        '이미지 ${missingImageReasons.length}개를 가져올 수 없어(사라졌거나 형식·용량이 '
        '맞지 않음) 가져오기를 시작할 수 없습니다. 사진을 확인한 뒤 다시 시도해 주세요.',
      );
    }

    final violation = validateRecordImportSnapshot(
      books: books,
      notes: filteredNotes,
      memos: memos,
      reflections: reflectionsForImport,
      tags: tags,
      tagMaps: tagMaps,
    );
    if (violation != null) {
      return RecordImportPreflightOutcome.failure(violation);
    }

    return RecordImportPreflightOutcome.success(
      RecordImportSnapshot(
        books: books,
        tags: tags,
        notes: filteredNotes,
        noteMemos: memos,
        reflections: reflectionsForImport,
        tagMaps: tagMaps,
        pendingMemoImages: pendingMemoImages,
        fallbackMemoImages: fallbackMemoImages,
        pendingReflectionImages: pendingReflectionImages,
      ),
    );
  }

  /// 서버가 이미지 업로드를 받아 줄 수 있는 파일인지(§ attachments 문서 —
  /// jpeg/png/webp, 5MB 이하). [LocalImageStore.saveSelected]가 사용자가
  /// 방금 고른 사진에는 이미 같은 제약을 걸어 두지만, `ensureDownloaded`로
  /// 받은 사본(서버 → 로컬 이전 등)은 이 검사를 거치지 않았을 수 있어
  /// 여기서 다시 확인한다 — 하나라도 걸리면 `/attachments`가 400을 반환해
  /// 세션 전체가 정리되기 때문이다.
  Future<bool> _isUploadableImage(File file) async {
    if (!await file.exists()) return false;
    final extension = path.extension(file.path).toLowerCase();
    if (!LocalImageStore.allowedExtensions.contains(extension)) return false;
    final length = await file.length();
    // 문서(attachments) 400 사유에 "빈 파일"이 명시돼 있다 — 0바이트도
    // 5MB 이하 조건은 통과하므로 별도로 걸러야 한다.
    return length > 0 && length <= LocalImageStore.maxBytes;
  }
}
