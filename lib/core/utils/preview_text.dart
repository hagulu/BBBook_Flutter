final _whitespace = RegExp(r'\s+');

/// 목록 미리보기용으로 줄바꿈·연속 공백을 공백 하나로 합쳐 한 문단처럼 만든다.
String? flattenPreviewText(String? text) {
  if (text == null) return null;
  return text.replaceAll(_whitespace, ' ').trim();
}
