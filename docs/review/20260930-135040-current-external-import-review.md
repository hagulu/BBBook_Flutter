# 리뷰 결과

## 요약

- 동기화 꺼짐·계정 없음에서도 가져오는 경로가 추가되어 이전 제한은 해소됐지만, 로컬 가져오기에서 같은 ISBN의 파일 내 항목 두 개를 선택하면 한 책의 정보가 사라질 수 있다. `flutter analyze`는 통과했다.

## 문제점

- [P1][같은 ISBN의 두 항목을 한 권으로 합치며 앞 항목의 책 정보를 덮어씀] `lib/features/external_record_import/services/external_record_local_import_service.dart:39-74`, `lib/features/record_archive/data/record_archive_dao.dart:305-366` — 북모리 파서는 항목의 원본 ID로 책을 구분하므로 서로 다른 두 항목이 같은 ISBN을 가질 수 있다(`lib/features/external_record_import/data/bookmory_importer.dart:169-192`). 로컬 가져오기는 두 항목 모두 별도 책으로 만들어 복원 DAO에 전달하지만, DAO는 첫 항목을 삽입한 뒤 두 번째 항목에서 같은 ISBN 행을 찾아 그 행을 갱신한다. 결과적으로 화면에서는 2권을 가져왔다고 표시해도 로컬 책은 1권이고, 첫 항목의 제목·독서 상태 등은 두 번째 값으로 바뀐다. 현재 사전 검증은 중복 `clientRequestId`만 검사해 이 입력을 막지 않는다(`lib/features/server_storage_migration/data/record_import_validation.dart:41-43`).

## 개선 제안

- 같은 ISBN의 두 항목을 한 권으로 합치며 앞 항목의 책 정보를 덮어씀 → 선택한 파일 항목 안에서 ISBN 중복을 검사하고 저장 전에 한 항목만 선택하도록 안내한다. 로컬 복원 트랜잭션에서도 명시적으로 허용한 ISBN 덮어쓰기만 수행하도록 확인해, 선택 확인 이후 생긴 충돌도 조용히 덮어쓰지 않게 한다.

검증: `flutter analyze` 통과. 프로젝트 지침에 따라 앱과 테스트는 실행하지 않았다.
