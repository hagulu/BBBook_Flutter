/// `POST /api/me/books`와 `POST /api/me/books/custom`의 공통 CREATE 응답.
///
/// `created == false`는 같은 `clientRequestId` 재시도로 기존 데이터를 반환한
/// 경우이며, 호출부는 신규 생성 성공과 동일하게 서버 ID와 표시 정보를
/// 로컬에 확정 반영한다.
class UserBookCreateResult {
  const UserBookCreateResult({
    required this.userBookId,
    required this.bookId,
    required this.isbn13,
    required this.title,
    required this.author,
    required this.publisher,
    required this.totalPages,
    required this.coverImageUrl,
    required this.status,
    required this.created,
  });

  final int userBookId;
  final int? bookId;
  final String? isbn13;
  final String title;
  final String? author;
  final String? publisher;
  final int? totalPages;
  final String? coverImageUrl;
  final String status;
  final bool created;

  factory UserBookCreateResult.fromJson(Map<String, dynamic> json) {
    return UserBookCreateResult(
      userBookId: json['userBookId'] as int,
      bookId: json['bookId'] as int?,
      isbn13: json['isbn13'] as String?,
      title: json['title'] as String,
      author: json['author'] as String?,
      publisher: json['publisher'] as String?,
      totalPages: json['totalPages'] as int?,
      coverImageUrl: json['coverImageUrl'] as String?,
      status: json['status'] as String,
      created: json['created'] as bool,
    );
  }
}
