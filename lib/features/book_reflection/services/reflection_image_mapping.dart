/// push 요청에 담아 보낸 본문과 서버가 돌려준 본문의 이미지를 **등장 순서대로**
/// 짝지어 "서버 URL → 로컬 사본 경로" 매칭을 만든다.
///
/// 보낸 URL을 그대로 키로 쓰지 않는 이유는 서버가 임시 업로드 URL
/// (`/api/reflections/images/temp`)을 저장 시점에 다른 경로로 바꿔 돌려줄 수
/// 있기 때문이다. 그때 보낸 URL로 매칭을 남기면 본문에 없는 URL의 매칭이
/// 생겨(화면은 서버에서 다시 받고, 정리는 로컬 파일을 지운다) 방금 올린
/// 사본이 곧바로 쓸모없어진다.
///
/// [documentSources]는 로컬 본문의 이미지 출처(업로드 전 로컬 상대 경로가
/// 섞여 있을 수 있다), [responseSources]는 응답 본문의 이미지 출처다.
/// [localImagePathBySource]는 "로컬 본문의 출처 → 로컬 사본 경로"로,
/// 이번에 업로드한 이미지와 이미 매칭돼 있던 이미지를 합쳐 넘긴다.
///
/// 두 목록의 길이가 다르면(서버가 본문 구조 자체를 바꿨거나 예상 밖 응답)
/// 순서 짝짓기를 신뢰할 수 없으므로 아무 매칭도 만들지 않는다 — 그 경우
/// 이후 hydration이 서버 이미지를 다시 내려받아 복구한다.
Map<String, String> resolveReflectionImageMappings({
  required List<String> documentSources,
  required List<String> responseSources,
  required Map<String, String> localImagePathBySource,
}) {
  if (documentSources.length != responseSources.length) return const {};
  final mappings = <String, String>{};
  for (var index = 0; index < documentSources.length; index++) {
    final remoteUrl = responseSources[index];
    if (remoteUrl.isEmpty) continue;
    final localImagePath = localImagePathBySource[documentSources[index]];
    if (localImagePath == null) continue;
    mappings[remoteUrl] = localImagePath;
  }
  return mappings;
}
