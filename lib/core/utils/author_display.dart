/// 저자명 표시용 가공. 원본 데이터는 그대로 두고 화면 노출 시에만
/// "(지은이)" 표기와 "저"/"원저" 같은 역할 접미사(및 앞 공백)를 제거한다
/// (외부 소스 데이터에 붙어 오는 역할 표기라 화면에는 불필요 — 책 정보 수정
/// 화면은 원본을 그대로 보여준다).
String displayAuthor(String author) {
  return author
      .replaceAll(RegExp(r'\s?\(지은이\)'), '')
      .replaceAll(RegExp(r'\s(원저|저)(?=,|$)'), '')
      .trim();
}
