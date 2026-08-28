import 'discussion_topic.dart';

/// 토론 답변 한 건(`GET /api/discussions/{topicId}/answers`).
///
/// 선택은 사용자가 아니라 **답변 단위**로 관리된다 — 같은 사용자가 선택지마다
/// 별도의 답변을 남길 수 있고, 각 답변이 결과 집계에 모두 반영된다.
class DiscussionAnswer {
  const DiscussionAnswer({
    required this.id,
    required this.topicId,
    required this.user,
    this.content,
    required this.hasVote,
    this.optionId,
    required this.isHidden,
    required this.likeCount,
    required this.likedByMe,
    required this.isMine,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final int topicId;
  final DiscussionAuthor user;

  /// 숨김 처리(`isHidden`)된 답변은 서버가 본문을 null로 내려준다.
  final String? content;

  /// 이 답변 자체에 유효한 선택이 있는지 여부. false면 선택 배너를 그리지
  /// 않는다(투표 없음 또는 삭제된 선택지를 참조하던 답변).
  final bool hasVote;

  /// [hasVote]가 true인데 null이면 "기타"를 선택한 답변이다.
  final int? optionId;
  final bool isHidden;
  final int likeCount;
  final bool likedByMe;
  final bool isMine;
  final DateTime createdAt;
  final DateTime updatedAt;

  DiscussionAnswer copyWith({
    String? content,
    int? likeCount,
    bool? likedByMe,
    DateTime? updatedAt,
  }) {
    return DiscussionAnswer(
      id: id,
      topicId: topicId,
      user: user,
      content: content ?? this.content,
      hasVote: hasVote,
      optionId: optionId,
      isHidden: isHidden,
      likeCount: likeCount ?? this.likeCount,
      likedByMe: likedByMe ?? this.likedByMe,
      isMine: isMine,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory DiscussionAnswer.fromJson(Map<String, dynamic> json) {
    return DiscussionAnswer(
      id: json['id'] as int,
      topicId: json['topicId'] as int? ?? 0,
      user: DiscussionAuthor.fromJson(json['user'] as Map<String, dynamic>),
      content: json['content'] as String?,
      hasVote: json['hasVote'] as bool? ?? false,
      optionId: json['optionId'] as int?,
      isHidden: json['isHidden'] as bool? ?? false,
      likeCount: json['likeCount'] as int? ?? 0,
      likedByMe: json['likedByMe'] as bool? ?? false,
      isMine: json['isMine'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}

/// `GET /api/discussions/{topicId}/answers` 커서 기반 목록 페이지(최신순).
class DiscussionAnswersPage {
  const DiscussionAnswersPage({
    required this.items,
    required this.nextCursor,
    required this.hasNext,
  });

  final List<DiscussionAnswer> items;
  final int? nextCursor;
  final bool hasNext;

  factory DiscussionAnswersPage.fromJson(Map<String, dynamic> json) {
    return DiscussionAnswersPage(
      items: (json['items'] as List<dynamic>? ?? const [])
          .map((e) => DiscussionAnswer.fromJson(e as Map<String, dynamic>))
          .toList(),
      nextCursor: json['nextCursor'] as int?,
      hasNext: json['hasNext'] as bool? ?? false,
    );
  }
}
