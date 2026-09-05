/// 저자명 표시용 가공. 원본 데이터는 그대로 두고 화면 노출 시에만 가공한다
/// (외부 소스 데이터에 붙어 오는 역할 표기라 화면에는 불필요 — 책 정보 수정
/// 화면은 원본을 그대로 보여준다).
/// - "(지은이)" 표기(및 앞 공백) 제거
/// - "저"/"원저" 같은 저자 역할 접미사(및 앞 공백) 제거 — "역"(번역가)은
///   그대로 둔다
/// - 저자 그룹과 번역가 그룹을 나누는 "/"를 가운데점(·)으로 바꿔
///   "저자1, 저자2 · 번역가1 역, 번역가2 역" 형태로 통일한다
///   (`api-books.md`의 "저자1, 저자2 / 번역가1 역, 번역가2 역" 응답 형식 기준)
String displayAuthor(String author) {
  return author
      .replaceAll(RegExp(r'\s?\(지은이\)'), '')
      .replaceAll(RegExp(r'\s(원저|저)(?=\s*(,|/|$))'), '')
      .replaceAll(RegExp(r'\s*/\s*'), ' · ')
      .trim();
}

/// 저자명이 담긴 nullable 필드(`BookItem.author` 등)에서 매번
/// `author != null && author.isNotEmpty ? displayAuthor(author) : null`을
/// 반복하지 않도록 하는 확장. 저자를 화면에 보여주는 곳은 원본 필드를 직접
/// 쓰지 말고 이 getter를 통해서만 노출한다(책 정보 수정 화면처럼 원본 그대로
/// 편집해야 하는 곳은 예외).
extension AuthorDisplayX on String? {
  String? get displayedAuthorOrNull {
    final value = this;
    if (value == null || value.isEmpty) return null;
    return displayAuthor(value);
  }
}
