# 리뷰 결과

## 요약
- 완독 CSV 가져오기 흐름은 동작하도록 연결됐지만, 삭제된 책의 ISBN 처리와 큰 파일 처리에서 실제 사용자 영향이 있는 문제가 확인됐다. `flutter analyze`는 통과했다.

## 문제점
- [P1][삭제된 ISBN 책이 건너뛰어지지 않고 복구됨] `lib/features/external_record_import/screens/finished_csv_import_screen.dart:103`, `lib/features/external_record_import/providers/external_import_providers.dart:148-156`, `lib/features/bookshelf/data/bookshelf_dao.dart:49-58` — CSV 화면은 일반 기록 Import 흐름을 사용한다. 기존 책 조회는 `pending_delete = 0`인 로컬 행만 찾으므로, 서버에 같은 ISBN의 soft delete 행만 있으면 새 행으로 선택된다. 그러나 일반 Import API는 그 삭제 행을 CSV 내용으로 복구한다(`../../api-doc/api-me-records-import-importId-items-post.md`, books[n] 규격). 완독 CSV API는 상태와 관계없이 같은 ISBN의 기존 책을 건너뛰도록 명시한다(`../../api-doc/api-me-books-import-finished-csv-post.md`, 처리 규칙). 따라서 사용자가 삭제한 책이 다시 책장에 나타나고 결과에도 등록으로 집계될 수 있다.
- [P2][큰 CSV 분석 중 화면이 멈추고 메모리 사용이 급증할 수 있음] `lib/features/external_record_import/services/external_import_file_analyzer.dart:18-22`, `lib/features/external_record_import/data/finished_csv_importer.dart:45-115`, `lib/features/external_record_import/providers/external_import_providers.dart:572-584` — 최대 64MB CSV를 한 번에 읽고, UI isolate에서 전체 행을 동기적으로 파싱한 뒤, ISBN마다 DB 조회 Future를 한꺼번에 생성한다. 행이 많은 정상 CSV에서 파일 선택 직후 화면 응답이 늦어지고 메모리가 크게 늘 수 있다.
- [P2][실패 행이 많은 CSV에서 결과 팝업이 모든 항목을 한꺼번에 그림] `lib/features/external_record_import/screens/widgets/finished_csv_import_sheets.dart:203-225`, `lib/features/external_record_import/screens/widgets/finished_csv_import_sheets.dart:265-304` — 실패 목록을 `SingleChildScrollView` 안의 `Column`으로 모두 생성한다. 허용된 파일 크기 내에서도 실패 행이 수천 개면 결과 팝업 생성과 스크롤이 느려지고 메모리 압박이 생긴다.

## 개선 제안
- 삭제된 ISBN 복구 → 완독 CSV 경로에서 서버의 기존 ISBN 상태까지 확인해 건너뛰거나, 동기화 모드에서는 CSV 전용 API의 중복 처리 규칙을 사용한다. 로컬 모드에서도 삭제 대기 행을 같은 규칙으로 다룬다.
- 큰 파일 분석의 UI 지연 → CSV 파싱을 별도 isolate나 스트리밍 처리로 옮기고, 기존 ISBN 조회는 묶어서 처리한다.
- 실패 목록의 대량 생성 → 결과 팝업 내부 목록을 높이가 제한된 `ListView.builder`로 바꿔 보이는 항목만 만든다.
