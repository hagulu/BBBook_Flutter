# 리뷰 결과

## 요약
- ISBN 미연결 제외 UI와 DB 스키마는 추가됐지만, 기존 부모 행 교체 저장 방식 때문에 제외 기록이 유지되지 않으며 저장 실패 처리와 상태 표시 접근성도 보완해야 한다.

## 문제점
- [데이터 정합성][높음] `lib/features/bookshelf/data/bookshelf_database.dart:141`~`:145`의 `dismissed_isbn_link`는 `user_book`을 `ON DELETE CASCADE`로 참조한다. 그런데 동기화·서버 응답 반영은 `lib/features/bookshelf/data/bookshelf_dao.dart:418`~`:421`, 로컬 우선 수정과 push 확정은 `:273`~`:277`, `:291`~`:295`에서 `ConflictAlgorithm.replace`로 같은 기본 키의 `user_book` 행을 교체한다. SQLite의 `INSERT OR REPLACE`는 충돌한 부모 행을 삭제한 뒤 다시 삽입하므로 자식 제외 기록이 cascade 삭제되고 복원되지 않는다. 따라서 사용자가 "목록에서 제외"를 선택해도 해당 책이 전체/증분 동기화되거나 책 기록이 수정된 뒤 ISBN 미연결 배너에 다시 나타난다.
- [비동기 오류 처리][중간] `lib/features/book_record/screens/widgets/isbn_link_search_sheet.dart:195`~`:205`는 제외 기록 저장을 `unawaited`로 시작한 직후 시트를 닫고, Future에는 성공 콜백만 연결한다. DB 쓰기가 실패하면 오류가 처리되지 않고 사용자는 다음 책으로 진행하거나 최종 완료 안내를 받으므로, 제외가 저장되지 않았다는 사실을 알 수 없다. 로그아웃·삭제와 쓰기가 겹쳐 외래 키 제약에 실패하는 경우도 동일하게 처리되지 않는다.
- [접근성][중간] `lib/features/bookshelf/screens/widgets/finished_tab_view.dart:841`~`:849`의 ISBN 미연결 표시는 임의의 표지 이미지 위에 작은 오류 색상 아이콘만 배치한다. 배경 대비가 보장되지 않고 의미를 전달하는 `Semantics` 라벨도 없어, 저시력·스크린 리더 사용자는 새로 추가된 연결 상태를 확인할 수 없다.

## 개선 제안
- 부모 행 교체 시 제외 기록이 cascade 삭제됨 → `user_book` 갱신을 행 삭제가 발생하지 않는 `UPDATE` 또는 SQLite `ON CONFLICT DO UPDATE` 방식으로 바꾸거나, 최소한 해당 트랜잭션에서 기존 제외 상태를 보존해 upsert 후 복원한다. 전체 동기화, 증분 동기화, 로컬 편집, push 확정 경로 모두 같은 보존 규칙을 적용한다.
- 제외 저장 실패가 사용자에게 숨겨짐 → `_handleSkip`을 비동기로 바꾸고 로컬 저장 완료 후 provider 갱신과 `Navigator.pop`을 수행한다. 실패 시 공통 스낵바로 안내하고 시트를 유지해 재시도할 수 있게 하며, 처리 중에는 중복 탭을 막는다.
- ISBN 미연결 상태가 시각·스크린 리더에서 불명확함 → 아이콘에 표지와 분리되는 대비 배경을 추가하고, 카드 전체 또는 상태 배지에 `ISBN 미연결` 의미가 중복 없이 읽히도록 `Semantics`를 제공한다.
