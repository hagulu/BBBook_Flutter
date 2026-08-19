import 'book_status.dart';
import 'book_tag.dart';

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
    this.totalPages,
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
  final int? totalPages;
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

  /// 0.0 ~ 1.0. totalPages를 모르면 null(진행률 표시 불가).
  double? get progressRatio {
    final total = totalPages;
    if (total == null || total <= 0) return null;
    return (currentPage / total).clamp(0.0, 1.0);
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
      totalPages: totalPages,
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
  /// 필드만)을 로컬에 즉시 반영할 때 쓴다. 각 파라미터가 null이면 현재 값을
  /// 유지한다 — 서버 PATCH의 "null이면 변경 없음" 의미론과 맞춰, 호출부가
  /// 건드리지 않은 필드가 그대로 보존되게 한다.
  ///
  /// [status]가 `'FINISHED'`이고 [finishedAt]을 생략하면(문서 기준 서버가
  /// `X-Timezone` 기준 오늘 날짜로 자동 설정하는 것과 동일한 조합) 로컬에도
  /// 즉시 오늘 날짜(KST)를 채운다. 그러지 않으면 `status=FINISHED,
  /// finishedAt=null`인 로컬 상태가 dirty로 남았을 때, 재시도 push가 그
  /// 조합을 "서버가 오늘 날짜로 새로 잡아버릴 위험"으로 오인해 status
  /// 자체를 생략하게 되고(`BookshelfRepository._pushDirtyItem`), 결국
  /// 완독 전환이 서버에 끝내 반영되지 못한 채 재시도 응답으로 로컬 상태만
  /// 원래대로 되돌아간다.
  BookItem copyWithRecord({
    String? status,
    int? currentPage,
    double? myRating,
    String? shortReview,
    bool? isMasterpiece,
    String? sourceType,
    int? rereadCount,
    String? difficulty,
    String? startedAt,
    String? finishedAt,
    String? platformName,
    String? discoverySource,
    required DateTime updatedAt,
  }) {
    final autoFillFinishedAt = status == 'FINISHED' && finishedAt == null;
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
      totalPages: totalPages,
      coverImageUrl: coverImageUrl,
      displayCategoryId: displayCategoryId,
      category: category,
      status: status != null ? BookStatus.fromApiValue(status) : this.status,
      currentPage: currentPage ?? this.currentPage,
      myRating: myRating ?? this.myRating,
      shortReview: shortReview ?? this.shortReview,
      isMasterpiece: isMasterpiece ?? this.isMasterpiece,
      sourceType: sourceType ?? this.sourceType,
      rereadCount: rereadCount ?? this.rereadCount,
      difficulty: difficulty ?? this.difficulty,
      startedAt: startedAt != null ? _parseDate(startedAt) : this.startedAt,
      finishedAt: finishedAt != null
          ? _parseDate(finishedAt)
          : (autoFillFinishedAt ? _todayInKst() : this.finishedAt),
      libraryId: libraryId,
      libraryDueAt: libraryDueAt,
      platformName: platformName ?? this.platformName,
      discoverySource: discoverySource ?? this.discoverySource,
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
      totalPages: json['totalPages'] as int?,
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
