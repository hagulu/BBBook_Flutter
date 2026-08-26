import '../../../core/network/patch_field.dart';
import 'book_item.dart';
import 'book_status.dart';

/// `PATCH /api/me/books/{userBookId}` 요청 한 건의 수정 의도.
///
/// 문서: ../../../../../../api-doc/api-me-books-userBookId-patch.md
///
/// 이 화면(책 기록 상세)의 수정은 로컬 우선이라, 사용자의 편집을 바로
/// 요청으로 보내는 대신 [changedFields]로 "무엇을 바꿨는지"만 로컬에 남겨
/// 두고 나중에 [RecordPatch.fromSnapshot]으로 같은 의미의 요청을 다시
/// 만들어 보낸다.
///
/// 서버 규칙을 그대로 옮긴다.
/// - 사용자가 건드리지 않은 필드는 요청 body에서 아예 제외한다(기존 값 유지).
/// - 사용자가 기존 값을 제거한 필드만 명시적 `null`로 보낸다(삭제).
/// - 빈 문자열은 삭제가 아니라 그대로 저장되는 값이다.
/// - `status`/`currentPage`/`isMasterpiece`/`rereadCount`는 삭제할 수 없는
///   non-null 컬럼이라 아예 3-상태가 필요 없다 — 값이 있을 때만 보낸다
///   (`T?`, null이면 생략).
///
/// 삭제 가능한 필드는 [PatchField]로 생략/수정/삭제를 구분한다.
class RecordPatch {
  const RecordPatch({
    this.status,
    this.currentPage,
    this.isMasterpiece,
    this.rereadCount,
    this.myRating,
    this.shortReview,
    this.sourceType,
    this.difficulty,
    this.startedAt,
    this.finishedAt,
    this.libraryId,
    this.libraryDueAt,
    this.platformName,
    this.discoverySource,
  });

  // 삭제 불가(non-null 컬럼) — null이면 요청에서 생략한다.
  final String? status;
  final int? currentPage;
  final bool? isMasterpiece;
  final int? rereadCount;

  // 삭제 가능 — null이면 생략, PatchField.clear()면 명시적 null(삭제).
  final PatchField<double>? myRating;
  final PatchField<String>? shortReview;
  final PatchField<String>? sourceType;
  final PatchField<String>? difficulty;

  /// `yyyy-MM-dd`.
  final PatchField<String>? startedAt;

  /// `yyyy-MM-dd`.
  final PatchField<String>? finishedAt;
  final PatchField<int>? libraryId;

  /// `yyyy-MM-dd`.
  final PatchField<String>? libraryDueAt;
  final PatchField<String>? platformName;
  final PatchField<String>? discoverySource;

  static const String fieldStatus = 'status';
  static const String fieldCurrentPage = 'currentPage';
  static const String fieldIsMasterpiece = 'isMasterpiece';
  static const String fieldRereadCount = 'rereadCount';
  static const String fieldMyRating = 'myRating';
  static const String fieldShortReview = 'shortReview';
  static const String fieldSourceType = 'sourceType';
  static const String fieldDifficulty = 'difficulty';
  static const String fieldStartedAt = 'startedAt';
  static const String fieldFinishedAt = 'finishedAt';
  static const String fieldLibraryId = 'libraryId';
  static const String fieldLibraryDueAt = 'libraryDueAt';
  static const String fieldPlatformName = 'platformName';
  static const String fieldDiscoverySource = 'discoverySource';

  /// 요청 body. 포함된 키만 서버가 수정 대상으로 본다 — 값이 `null`인 키는
  /// "삭제", 아예 없는 키는 "유지"다.
  Map<String, dynamic> toJson() {
    final body = <String, dynamic>{};
    if (status != null) body[fieldStatus] = status;
    if (currentPage != null) body[fieldCurrentPage] = currentPage;
    if (isMasterpiece != null) body[fieldIsMasterpiece] = isMasterpiece;
    if (rereadCount != null) body[fieldRereadCount] = rereadCount;
    if (myRating.isPresent) body[fieldMyRating] = myRating.requestValue;
    if (shortReview.isPresent) body[fieldShortReview] = shortReview.requestValue;
    if (sourceType.isPresent) body[fieldSourceType] = sourceType.requestValue;
    if (difficulty.isPresent) body[fieldDifficulty] = difficulty.requestValue;
    if (startedAt.isPresent) body[fieldStartedAt] = startedAt.requestValue;
    if (finishedAt.isPresent) body[fieldFinishedAt] = finishedAt.requestValue;
    if (libraryId.isPresent) body[fieldLibraryId] = libraryId.requestValue;
    if (libraryDueAt.isPresent) {
      body[fieldLibraryDueAt] = libraryDueAt.requestValue;
    }
    if (platformName.isPresent) {
      body[fieldPlatformName] = platformName.requestValue;
    }
    if (discoverySource.isPresent) {
      body[fieldDiscoverySource] = discoverySource.requestValue;
    }
    return body;
  }

  /// 이번 수정이 건드린 필드 이름들(= [toJson]의 키). 로컬 우선 편집을
  /// dirty로 남길 때 "무엇을 바꿨는지"를 함께 저장해, 나중에 재시도하는
  /// push가 그 필드만 다시 보내도록 하기 위해 쓴다
  /// (`BookshelfDao.applyLocalEdit`).
  Set<String> get changedFields => toJson().keys.toSet();

  bool get isEmpty => toJson().isEmpty;

  /// 로컬 dirty 행을 서버로 재전송할 요청을 만든다.
  ///
  /// [changedFields]는 그 행에 쌓인 로컬 편집이 실제로 건드린 필드 이름이다
  /// (`user_book.dirty_fields`). 그 필드만 요청에 싣고, 현재 로컬 값이
  /// null이면 "사용자가 지웠다"는 뜻이므로 명시적 `null`(삭제)로 보낸다.
  ///
  /// [changedFields]가 null인 행은 `dirty_fields` 컬럼이 없던 시절(DB v15
  /// 이하)에 쌓인 레거시 dirty 행이다 — 무엇을 바꿨는지 알 수 없으므로 예전
  /// 동작 그대로 "값이 있는 필드만 보내고 null은 생략"한다. 이 행들에
  /// 삭제(명시적 null)를 보내면 사용자가 지운 적 없는 서버 값까지 지울 수
  /// 있다.
  factory RecordPatch.fromSnapshot(
    BookItem item, {
    required Set<String>? changedFields,
  }) {
    final fields = changedFields ?? const <String>{};
    final legacy = fields.isEmpty;
    bool includes(String name) => legacy || fields.contains(name);

    // status가 FINISHED인데 완독일을 모르는 상태로 status를 보내면 서버가
    // 완독일을 오늘 날짜로 새로 잡아버린다(문서 기준). 그 조합일 때만
    // status를 생략한다 — [BookItem.copyWithRecord]가 최초 완독 전환 시
    // 로컬에도 곧바로 오늘 날짜를 채우므로 정상 흐름에서는 드물다.
    final skipStatus =
        item.status == BookStatus.finished && item.finishedAt == null;

    // 반대로 status를 FINISHED로 보내면서 완독일을 이미 알고 있으면, 그
    // 날짜를 함께 못박는다. 서버는 status가 FINISHED인데 finishedAt이 없는
    // 요청을 받으면 "오늘"로 새로 잡는데, 오프라인 편집이 며칠 뒤에야
    // 재전송되면 그 "오늘"이 사용자가 실제로 완독한 날과 달라진다.
    final pinFinishedAt =
        includes(fieldStatus) &&
        item.status == BookStatus.finished &&
        item.finishedAt != null;

    /// 삭제 가능 필드의 3-상태 변환. 레거시 행에서는 null을 생략으로 낮춘다.
    PatchField<T>? field<T extends Object>(String name, T? value) {
      if (!includes(name) && !(name == fieldFinishedAt && pinFinishedAt)) {
        return null;
      }
      if (value != null) return PatchField.value(value);
      return legacy ? null : PatchField<T>.clear();
    }

    return RecordPatch(
      status: includes(fieldStatus) && !skipStatus ? item.status.apiValue : null,
      currentPage: includes(fieldCurrentPage) ? item.currentPage : null,
      isMasterpiece: includes(fieldIsMasterpiece) ? item.isMasterpiece : null,
      rereadCount: includes(fieldRereadCount) ? item.rereadCount : null,
      myRating: field(fieldMyRating, item.myRating),
      shortReview: field(fieldShortReview, item.shortReview),
      sourceType: field(fieldSourceType, item.sourceType),
      difficulty: field(fieldDifficulty, item.difficulty),
      startedAt: field(fieldStartedAt, formatApiDate(item.startedAt)),
      finishedAt: field(fieldFinishedAt, formatApiDate(item.finishedAt)),
      libraryId: field(fieldLibraryId, item.libraryId),
      libraryDueAt: field(fieldLibraryDueAt, formatApiDate(item.libraryDueAt)),
      platformName: field(fieldPlatformName, item.platformName),
      discoverySource: field(fieldDiscoverySource, item.discoverySource),
    );
  }

  /// `yyyy-MM-dd` — API가 받는 날짜 형식.
  static String? formatApiDate(DateTime? date) =>
      date?.toIso8601String().substring(0, 10);

  /// [fromSnapshot]이 레거시 dirty 행(`dirty_fields`가 NULL)에 대해 실제로
  /// 전송하는 필드 집합. 그런 행에 새 편집이 겹칠 때 추적 목록의 출발점으로
  /// 쓴다(`BookshelfDao.applyLocalEdit`) — 그러지 않고 이번 편집이 건드린
  /// 필드만 남기면, 아직 서버로 못 올린 이전 오프라인 편집들이 요청에서
  /// 통째로 빠져 영영 반영되지 않는다.
  static Set<String> nonNullFieldsOf(BookItem item) {
    return {
      // 삭제 불가 필드는 로컬에서도 항상 값이 있어 늘 전송된다.
      fieldStatus,
      fieldCurrentPage,
      fieldIsMasterpiece,
      fieldRereadCount,
      if (item.myRating != null) fieldMyRating,
      if (item.shortReview != null) fieldShortReview,
      if (item.sourceType != null) fieldSourceType,
      if (item.difficulty != null) fieldDifficulty,
      if (item.startedAt != null) fieldStartedAt,
      if (item.finishedAt != null) fieldFinishedAt,
      if (item.libraryId != null) fieldLibraryId,
      if (item.libraryDueAt != null) fieldLibraryDueAt,
      if (item.platformName != null) fieldPlatformName,
      if (item.discoverySource != null) fieldDiscoverySource,
    };
  }
}
