import '../../../core/network/patch_field.dart';
import 'book_status.dart';
import 'book_tag.dart';
import 'record_patch.dart';

/// 책장의 책 한 권. `GET /api/me/books/sync` 응답 및 로컬 DB(`user_book` 테이블) 공용 모델.
class BookItem {
  const BookItem({
    required this.userBookId,
    this.serverId,
    this.clientRequestId,
    this.createThumbnailPath,
    this.bookId,
    this.isbn13,
    required this.title,
    this.author,
    this.publisher,
    this.statsTotalPages,
    this.displayTotalPages,
    this.coverImageUrl,
    this.displayCategoryId,
    this.category,
    required this.status,
    required this.currentPage,
    this.myRating,
    this.shortReview,
    required this.isMasterpiece,
    this.sourceType,
    required this.rereadCount,
    this.difficulty,
    this.startedAt,
    this.finishedAt,
    this.libraryId,
    this.libraryDueAt,
    this.platformName,
    this.discoverySource,
    required this.tags,
    required this.createdAt,
    required this.updatedAt,
  });

  final int userBookId;

  /// 서버의 실제 `user_book.id`. 로컬 신규 생성 직후에는 null이고, CREATE
  /// 성공(동일 clientRequestId 재시도로 기존 행을 받은 경우 포함) 후 채운다.
  /// 로컬 [userBookId]는 화면/FK가 계속 참조하는 안정적인 PK라 바꾸지 않는다.
  final int? serverId;

  /// CREATE 멱등 키. 로컬 신규 생성 시 한 번 발급하며 dirty 재시도에서도
  /// 같은 값을 계속 사용한다. 기존 데이터와 서버 동기화 행은 null일 수 있다.
  final String? clientRequestId;

  /// 커스텀 CREATE가 아직 성공하지 않은 동안 재업로드할 관리 디렉터리 표지
  /// 경로. 성공 후 null로 정리한다.
  final String? createThumbnailPath;
  final int? bookId;
  final String? isbn13;
  final String title;
  final String? author;
  final String? publisher;

  /// 종이책 기준 쪽수(알라딘 책 정보 기준, 통계 계산에 사용).
  final int? statsTotalPages;

  /// 실제 읽는 판본(전자책 등)의 쪽수 override. null이면 [statsTotalPages]로
  /// fallback한다 — [effectiveTotalPages] 참고.
  final int? displayTotalPages;
  final String? coverImageUrl;
  final int? displayCategoryId;
  final String? category;
  final BookStatus status;
  final int currentPage;
  final double? myRating;
  final String? shortReview;
  final bool isMasterpiece;
  final String? sourceType;
  final int rereadCount;
  final String? difficulty;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final int? libraryId;
  final DateTime? libraryDueAt;
  final String? platformName;
  final String? discoverySource;
  final List<BookTag> tags;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// 오디오북 여부(`sourceType == 'AUDIO_BOOK'`). 오디오북은 쪽수 대신
  /// [currentPage] 자체를 0~100 진행률 값으로 쓴다.
  bool get isAudioBook => sourceType == 'AUDIO_BOOK';

  /// 실제 진행률 계산 기준 쪽수. [displayTotalPages]가 있으면 그 값을,
  /// 없으면 [statsTotalPages]로 fallback한다(오디오북에는 의미 없는 값).
  int? get effectiveTotalPages => displayTotalPages ?? statsTotalPages;

  /// 완독/재독 시 진행 상태를 "끝까지" 채울 때 쓰는 상한값. 오디오북은
  /// 100(퍼센트), 그 외는 [effectiveTotalPages].
  int? get progressUpperBound => isAudioBook ? 100 : effectiveTotalPages;

  /// 0.0 ~ 1.0. 오디오북은 [currentPage]를 그대로 0~100 퍼센트로 취급하고,
  /// 그 외는 [effectiveTotalPages]를 모르면 null(진행률 표시 불가).
  double? get progressRatio {
    if (isAudioBook) {
      return (currentPage.clamp(0, 100)) / 100.0;
    }
    final total = effectiveTotalPages;
    if (total == null || total <= 0) return null;
    return (currentPage / total).clamp(0.0, 1.0);
  }

  /// 출처를 [newSourceType]으로 바꿀 때 [currentPage]를 정리한다. 쪽수와
  /// 퍼센트는 단위가 달라 자동으로 환산하면(과거 시도) 오히려 사용자가
  /// 의도하지 않은 값으로 조용히 바뀔 수 있으므로, 출처가 실제로 바뀌고
  /// 진행 기록이 있으면(0보다 크면) 0으로 초기화해 새 출처 기준으로
  /// 다시 시작하게 한다 — 호출부가 이 초기화를 사용자에게 미리 안내해야
  /// 한다(`showSourcePlatformDialog`의 경고 확인). 출처가 그대로거나 애초에
  /// 진행 기록이 없으면 값을 그대로 둔다.
  int normalizedCurrentPageForSourceChange({required String? newSourceType}) {
    if (newSourceType == sourceType || currentPage <= 0) return currentPage;
    return 0;
  }

  /// 책 정보(제목/저자/출판사/총쪽수/카테고리/표지)와 ISBN 연결만 바꾼
  /// 사본을 만든다. 서버 응답 없이 로컬에서 직접 반영하는 경로(로컬 저장
  /// 모드의 책 정보 수정·ISBN 연결)가 쓴다 — 넘긴 값이 그대로 새 값이므로
  /// 바뀌지 않는 필드는 호출부가 현재 값을 그대로 넘긴다.
  BookItem copyWithBookInfo({
    required String title,
    required String? author,
    required String? publisher,
    required int? statsTotalPages,
    required int? displayTotalPages,
    required int? displayCategoryId,
    required String? category,
    required String? coverImageUrl,
    required String? isbn13,
    required int? bookId,
    required DateTime updatedAt,
  }) {
    return BookItem(
      userBookId: userBookId,
      serverId: serverId,
      clientRequestId: clientRequestId,
      createThumbnailPath: createThumbnailPath,
      bookId: bookId,
      isbn13: isbn13,
      title: title,
      author: author,
      publisher: publisher,
      statsTotalPages: statsTotalPages,
      displayTotalPages: displayTotalPages,
      coverImageUrl: coverImageUrl,
      displayCategoryId: displayCategoryId,
      category: category,
      status: status,
      currentPage: currentPage,
      myRating: myRating,
      shortReview: shortReview,
      isMasterpiece: isMasterpiece,
      sourceType: sourceType,
      rereadCount: rereadCount,
      difficulty: difficulty,
      startedAt: startedAt,
      finishedAt: finishedAt,
      libraryId: libraryId,
      libraryDueAt: libraryDueAt,
      platformName: platformName,
      discoverySource: discoverySource,
      tags: tags,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// [tags]와 [updatedAt]만 다른 사본을 만든다. 태그 추가/삭제 응답이
  /// 태그 정보만 돌려주는 API(POST/DELETE tags)의 결과를 로컬 [BookItem]에
  /// 반영할 때 사용한다.
  BookItem copyWithTags(List<BookTag> tags, {required DateTime updatedAt}) {
    return BookItem(
      userBookId: userBookId,
      serverId: serverId,
      clientRequestId: clientRequestId,
      createThumbnailPath: createThumbnailPath,
      bookId: bookId,
      isbn13: isbn13,
      title: title,
      author: author,
      publisher: publisher,
      statsTotalPages: statsTotalPages,
      displayTotalPages: displayTotalPages,
      coverImageUrl: coverImageUrl,
      displayCategoryId: displayCategoryId,
      category: category,
      status: status,
      currentPage: currentPage,
      myRating: myRating,
      shortReview: shortReview,
      isMasterpiece: isMasterpiece,
      sourceType: sourceType,
      rereadCount: rereadCount,
      difficulty: difficulty,
      startedAt: startedAt,
      finishedAt: finishedAt,
      libraryId: libraryId,
      libraryDueAt: libraryDueAt,
      platformName: platformName,
      discoverySource: discoverySource,
      tags: tags,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// 책 기록 화면의 필드 수정(`PATCH /api/me/books/:userBookId`에 대응하는
  /// 필드만)을 로컬에 즉시 반영할 때 쓴다. [patch]에 담기지 않은 필드는 현재
  /// 값을 그대로 유지하고, `PatchField.clear()`로 담긴 필드는 로컬에서도
  /// 즉시 지운다 — 서버 PATCH의 "생략=유지 / 명시적 null=삭제" 규칙과 로컬
  /// 반영을 같은 의미로 맞춘다(빈 문자열은 지움 신호가 아니라 값이다).
  ///
  /// [RecordPatch.status]가 `'FINISHED'`이고 `finishedAt`이 생략되면(문서
  /// 기준 서버가 `X-Timezone` 기준 오늘 날짜로 자동 설정하는 것과 동일한
  /// 조합) 로컬에도 즉시 오늘 날짜(KST)를 채운다. 그러지 않으면
  /// `status=FINISHED, finishedAt=null`인 로컬 상태가 dirty로 남았을 때,
  /// 재시도 push가 그 조합을 "서버가 오늘 날짜로 새로 잡아버릴 위험"으로
  /// 오인해 status 자체를 생략하게 되고([RecordPatch.fromSnapshot]), 결국
  /// 완독 전환이 서버에 끝내 반영되지 못한 채 재시도 응답으로 로컬 상태만
  /// 원래대로 되돌아간다.
  ///
  /// 반대로 수정 결과 status가 `FINISHED`인데 `finishedAt`을 명시적으로
  /// 지우면, 서버는 그 삭제를 무시하고 기존 완독일(없으면 오늘)을
  /// 유지/설정한다(api-doc의 finishedAt 예외 규칙 — 완독인 책은 완독일이
  /// 반드시 있어야 한다). 로컬에서만 지워 버리면 화면은 지워진 것처럼
  /// 보이다가 push 응답이나 다음 동기화에서 날짜가 되살아나므로, 여기서도
  /// 서버와 똑같이 값을 유지한다.
  BookItem copyWithRecord(RecordPatch patch, {required DateTime updatedAt}) {
    final status = patch.status;
    final nextStatus = status != null
        ? BookStatus.fromApiValue(status)
        : this.status;
    final autoFillFinishedAt =
        status == 'FINISHED' && !patch.finishedAt.isPresent;
    final keepFinishedAtOnClear =
        nextStatus == BookStatus.finished &&
        patch.finishedAt.isPresent &&
        patch.finishedAt.requestValue == null;
    return BookItem(
      userBookId: userBookId,
      serverId: serverId,
      clientRequestId: clientRequestId,
      createThumbnailPath: createThumbnailPath,
      bookId: bookId,
      isbn13: isbn13,
      title: title,
      author: author,
      publisher: publisher,
      statsTotalPages: statsTotalPages,
      displayTotalPages: displayTotalPages,
      coverImageUrl: coverImageUrl,
      displayCategoryId: displayCategoryId,
      category: category,
      status: nextStatus,
      currentPage: patch.currentPage ?? currentPage,
      myRating: patch.myRating.applyTo(myRating),
      shortReview: patch.shortReview.applyTo(shortReview),
      isMasterpiece: patch.isMasterpiece ?? isMasterpiece,
      sourceType: patch.sourceType.applyTo(sourceType),
      rereadCount: patch.rereadCount ?? rereadCount,
      difficulty: patch.difficulty.applyTo(difficulty),
      startedAt: patch.startedAt.isPresent
          ? _parseDate(patch.startedAt.requestValue)
          : startedAt,
      finishedAt: keepFinishedAtOnClear
          ? (finishedAt ?? _todayInKst())
          : patch.finishedAt.isPresent
          ? _parseDate(patch.finishedAt.requestValue)
          : (autoFillFinishedAt ? _todayInKst() : finishedAt),
      libraryId: patch.libraryId.applyTo(libraryId),
      libraryDueAt: patch.libraryDueAt.isPresent
          ? _parseDate(patch.libraryDueAt.requestValue)
          : libraryDueAt,
      platformName: patch.platformName.applyTo(platformName),
      discoverySource: patch.discoverySource.applyTo(discoverySource),
      tags: tags,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// 이 앱은 한국어 전용 서비스라 서버에 항상 `X-Timezone: Asia/Seoul`을
  /// 고정으로 보낸다(book_record_api.dart) — 기기의 실제 타임존 설정과
  /// 무관하게 서버가 계산하는 "오늘"과 맞추기 위해 KST(UTC+9, DST 없음)
  /// 기준으로 직접 계산한다.
  static DateTime _todayInKst() {
    final kstNow = DateTime.now().toUtc().add(const Duration(hours: 9));
    return DateTime(kstNow.year, kstNow.month, kstNow.day);
  }

  factory BookItem.fromSyncJson(Map<String, dynamic> json) {
    return BookItem.fromDetailJson(
      json,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  /// `PATCH /api/me/books/:userBookId`(및 `.../book-info`) 응답(책 기록 상세
  /// 데이터)에는 `createdAt`이 내려오지 않는다. 로컬 DB의 `NOT NULL` 컬럼을
  /// 채우기 위해 호출 측이 기존 로컬 행의 [createdAt]을 그대로 넘긴다.
  /// `updatedAt`은 두 응답 모두에 내려오므로(api-doc) json에서 직접 읽는다 —
  /// 서버가 실제로 반영한 `user_book.updated_at`이라 다음 PATCH의 충돌 검사
  /// 기준값으로 그대로 쓸 수 있다.
  factory BookItem.fromDetailJson(
    Map<String, dynamic> json, {
    required DateTime createdAt,
    int? localUserBookId,
    String? clientRequestId,
    String? createThumbnailPath,
  }) {
    return BookItem(
      userBookId: localUserBookId ?? json['userBookId'] as int,
      serverId: json['userBookId'] as int,
      clientRequestId: clientRequestId,
      createThumbnailPath: createThumbnailPath,
      bookId: json['bookId'] as int?,
      isbn13: json['isbn13'] as String?,
      title: json['title'] as String,
      author: json['author'] as String?,
      publisher: json['publisher'] as String?,
      statsTotalPages: json['statsTotalPages'] as int?,
      displayTotalPages: json['displayTotalPages'] as int?,
      coverImageUrl: json['coverImageUrl'] as String?,
      displayCategoryId: json['displayCategoryId'] as int?,
      category: json['category'] as String?,
      status: BookStatus.fromApiValue(json['status'] as String),
      currentPage: json['currentPage'] as int,
      myRating: (json['myRating'] as num?)?.toDouble(),
      shortReview: json['shortReview'] as String?,
      isMasterpiece: json['isMasterpiece'] as bool,
      sourceType: json['sourceType'] as String?,
      rereadCount: json['rereadCount'] as int,
      difficulty: json['difficulty'] as String?,
      startedAt: _parseDate(json['startedAt'] as String?),
      finishedAt: _parseDate(json['finishedAt'] as String?),
      libraryId: json['libraryId'] as int?,
      libraryDueAt: _parseDate(json['libraryDueAt'] as String?),
      platformName: json['platformName'] as String?,
      discoverySource: json['discoverySource'] as String?,
      tags: (json['tags'] as List<dynamic>? ?? [])
          .map((e) => BookTag.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt: createdAt,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  static DateTime? _parseDate(String? value) {
    if (value == null || value.isEmpty) return null;
    return DateTime.parse(value);
  }
}

/// 책 한 권과 함께 정리해야 할 로컬 이미지 경로 묶음
/// ([BookshelfDao.findLocalImagePathsForBook]).
class BookLocalImagePaths {
  const BookLocalImagePaths({
    required this.memoImages,
    required this.reflectionImages,
    required this.coverImage,
  });

  final List<String> memoImages;
  final List<String> reflectionImages;

  /// 로컬 저장 모드에서 사용자가 고른 표지(서버 URL이면 파일이 없다).
  final String? coverImage;
}
