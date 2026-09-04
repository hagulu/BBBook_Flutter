import 'my_discussion_answer_summary.dart';

/// `GET /api/me/discussion-answers` 응답 전체(페이지 번호 기반 페이지네이션,
/// `api-me-discussion-answers-get.md`). 다른 3개 "내가 작성한 콘텐츠" 목록과
/// 달리 이 엔드포인트만 커서가 아니라 `page`/`totalPages`를 반환한다.
class MyDiscussionAnswerPage {
  const MyDiscussionAnswerPage({
    required this.items,
    required this.page,
    required this.size,
    required this.totalElements,
    required this.totalPages,
  });

  final List<MyDiscussionAnswerSummary> items;

  /// 0부터 시작하는 서버 페이지 번호.
  final int page;
  final int size;
  final int totalElements;
  final int totalPages;

  factory MyDiscussionAnswerPage.fromJson(Map<String, dynamic> json) {
    return MyDiscussionAnswerPage(
      items: (json['items'] as List<dynamic>? ?? const [])
          .map(
            (item) => MyDiscussionAnswerSummary.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(growable: false),
      page: json['page'] as int? ?? 0,
      size: json['size'] as int? ?? 0,
      totalElements: json['totalElements'] as int? ?? 0,
      totalPages: json['totalPages'] as int? ?? 0,
    );
  }
}
