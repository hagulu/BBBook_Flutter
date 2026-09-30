# 리뷰 결과

## 요약

- 현재 가져오기 화면·진입점 변경에서 저장 모드와 외부 기록 가져오기 동선이 맞지 않는 문제 1건을 확인했다. `flutter analyze`는 통과했다.

## 문제점

- [P2][동기화가 꺼져 있어도 외부 기록 파일을 선택·분석하게 됨] `lib/features/book_search/screens/book_search_screen.dart:127-128`, `lib/features/book_search/screens/book_search_screen.dart:200-204`, `lib/features/external_record_import/screens/external_import_guide_screen.dart:72-75` — 새 진입점은 계정 유무만 확인하고 안내 화면은 항상 파일 선택을 허용한다. 하지만 `ExternalImportController.startImport()`는 로컬 저장 모드에서 가져오기를 거절한다(`lib/features/external_record_import/providers/external_import_providers.dart:231-242`). 이 상태에서는 사용자가 파일을 선택하고 분석 결과에서 책을 고른 뒤 가져오기 버튼을 눌러야 동기화를 켜야 한다는 안내를 받는다. 특히 큰 북모리 파일은 불필요한 분석을 끝까지 거치게 된다.

## 개선 제안

- 동기화가 꺼져 있어도 외부 기록 파일을 선택·분석하게 됨 → 파일 선택 전에 저장 모드를 확인해, 동기화가 꺼져 있으면 안내 화면에서 설정의 기록 동기화를 켜야 한다고 알리고 파일 선택을 막는다. 가져오기 실행 시의 기존 저장 모드 검사는 유지한다.

검증: `flutter analyze` 통과. 프로젝트 지침에 따라 앱과 테스트는 실행하지 않았다.
