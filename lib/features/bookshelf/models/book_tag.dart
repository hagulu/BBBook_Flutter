/// 화면에 노출되는 태그 값 객체. [id]는 로컬 태그 ID다(서버 ID가 아니다) —
/// 오프라인에서 막 추가한 태그는 서버 ID가 아직 없을 수 있어, 화면은 항상
/// 로컬 ID로 태그를 가리킨다(`TagRepository`/`TagDao` 참고). 태그 추가/삭제
/// API 호출 시 서버 ID로의 변환은 `TagRepository`가 전담한다.
class BookTag {
  const BookTag({required this.id, required this.name});

  final int id;
  final String name;

  factory BookTag.fromJson(Map<String, dynamic> json) {
    return BookTag(id: json['id'] as int, name: json['name'] as String);
  }
}
