# 리뷰 결과

## 요약
- 새 CSV 컬럼의 파싱·태그 저장은 연결됐고 이전의 파싱 중 화면 멈춤과 실패 목록 대량 렌더링은 개선됐으나, 중복 처리와 일부 입력값의 저장·표시 규칙에 문제가 남아 있다.

## 문제점
- [P1][삭제된 ISBN 책이 다시 나타날 수 있음] `lib/features/external_record_import/providers/external_import_providers.dart:148-156`, `lib/features/bookshelf/data/bookshelf_dao.dart:49-58`, `lib/features/external_record_import/screens/finished_csv_import_screen.dart:96-105` — 기존 책 확인은 `pending_delete = 0`인 로컬 행만 조회한다. 서버에 같은 ISBN의 soft delete 행만 남은 경우 CSV 행을 신규 대상으로 선택하지만, 실제 저장에 쓰는 records Import는 그 행을 CSV 값으로 복구한다(`../../api-doc/api-me-records-import-importId-items-post.md`, books[n] 규격). 완독 CSV API의 "상태와 관계없이 같은 ISBN은 건너뜀" 규칙과 달라 삭제한 책이 되살아난다. 이전 리뷰의 P1 문제가 유지됐다.
- [P2][ISBN으로 매칭한 책의 기본 정보가 보완되지 않음] `lib/features/external_record_import/data/finished_csv_importer.dart:286-305`, `lib/features/external_record_import/services/external_import_snapshot_builder.dart:60-86` — 완독 CSV API는 내부 book과 ISBN이 매칭되면 표지·카테고리를 가져오고, CSV에서 비운 저자·출판사·총 쪽수를 book 값으로 보완한다(`../../api-doc/api-me-books-import-finished-csv-post.md`, 처리 규칙). 현재 경로는 CSV 값을 그대로 records Import 스냅샷으로 만들며 book 조회나 보완 단계가 없다. 예를 들어 ISBN과 제목만 있는 행은 해당 책이 서버에 있어도 저자·출판사·쪽수·표지가 비어 있는 기록으로 전달된다.
- [P2][CSV 난이도가 저장돼도 화면에서 미설정으로 보일 수 있음] `lib/features/external_record_import/data/finished_csv_importer.dart:234-236`, `lib/features/external_record_import/data/finished_csv_importer.dart:329-335`, `lib/features/book_record/models/record_labels.dart:79-84`, `lib/features/book_record/screens/book_record_screen.dart:314-341` — 길이 30자 이내의 알 수 없는 난이도 값(예: `MEDIUM`)을 파서가 그대로 받아 저장한다. 책 기록 화면은 `EASY`·`MODERATE`·`HARD`만 표시하고 나머지는 "설정 안 됨"으로 다뤄, 가져오기가 성공해도 입력한 값이 보이지 않는다.
- [P2][행이 많은 CSV에서 ISBN 조회 Future가 한꺼번에 생성됨] `lib/features/external_record_import/services/external_import_file_analyzer.dart:19`, `lib/features/external_record_import/providers/external_import_providers.dart:572-584` — 파일은 최대 64MB까지 허용하지만, 분석 뒤 서로 다른 ISBN마다 DB 조회를 시작해 모두 `Future.wait`에 담는다. 새 파서는 별도 isolate로 옮겨졌으나 ISBN이 많은 파일은 UI isolate에서 대량 Future와 DB 작업을 한 번에 만들며 메모리 사용과 분석 지연이 커질 수 있다. 이전 리뷰의 대량 파일 문제 중 이 경로는 남아 있다.

## 개선 제안
- 삭제된 ISBN 복구 → 완독 CSV 경로에서 삭제 상태를 포함한 기존 ISBN을 건너뛰도록 처리한다.
- 기본 정보 누락 → CSV 전용 API를 사용하는 서버 저장 경로를 마련하거나, ISBN에 대응하는 book 정보를 조회해 필수 보완 값을 스냅샷에 반영한다.
- 난이도 표시 누락 → 화면이 표시할 수 없는 값을 행 실패로 처리하거나, 저장한 자유 텍스트를 화면에서도 표시한다.
- 대량 ISBN 조회 → 기존 책 조회를 ISBN 묶음 단위로 수행하고 한 번에 만드는 작업 수를 제한한다.
