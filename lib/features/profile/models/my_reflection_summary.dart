import '../../book_reflection/models/book_reflection.dart';
import '../../bookshelf/models/book_item.dart';
import 'my_content_book.dart';

/// "내가 작성한 독후감" 목록 항목(`my-content-screens.md` §2-4).
///
/// 서버 목록 API 대신 로컬 DB([BookReflection])에서 직접 만든다 — 그래야
/// 목록의 [id]가 상세 화면이 바로 쓸 수 있는 로컬 PK가 되어, 서버 ID로 로컬
/// 행을 다시 찾는 동기화 타이밍 문제가 생기지 않는다.
class MyReflectionSummary {
  const MyReflectionSummary({
    required this.id,
    required this.userBookId,
    required this.book,
    required this.title,
    required this.previewText,
    required this.isPublic,
    required this.isHidden,
    required this.createdAt,
  });

  /// 로컬 PK(`BookReflectionDetailScreen.reflectionId`에 그대로 넘긴다).
  final int id;
  final int userBookId;
  final MyContentBookRef? book;

  /// isHidden이면 표시하지 않는다(관리자 숨김 처리).
  final String? title;

  /// isHidden이면 표시하지 않는다.
  final String? previewText;
  final bool isPublic;
  final bool isHidden;
  final DateTime createdAt;

  factory MyReflectionSummary.fromLocal({
    required BookReflection reflection,
    required BookItem? book,
  }) {
    return MyReflectionSummary(
      id: reflection.id,
      userBookId: reflection.userBookId,
      book: book == null
          ? null
          : MyContentBookRef(
              title: book.title,
              author: book.author,
              coverImageUrl: book.coverImageUrl,
            ),
      title: reflection.isHidden ? null : reflection.title,
      previewText: reflection.isHidden
          ? null
          : reflection.contentText?.trim(),
      isPublic: reflection.isPublic,
      isHidden: reflection.isHidden,
      createdAt: reflection.createdAt,
    );
  }
}
