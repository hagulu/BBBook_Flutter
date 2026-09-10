# 리뷰 결과

## 요약
- 현재 미커밋 외부 기록 가져오기·Android 공유 수신 변경에서 기존 기록 유실 위험 1건, 동시 실행 충돌 1건, CSV 식별자 충돌 1건을 확인했다. `flutter analyze`는 통과했다.
- 코드와 기존 Import API 문서를 대조한 정적 리뷰다. 앱 실행과 테스트는 수행하지 않았으며, 구현 코드는 수정하지 않았다.

## 문제점

- [P1 문제] 같은 ISBN의 기존 책 정보가 별도 안내 없이 외부 값과 기본값으로 덮어써진다.
  - 위치: `lib/features/external_record_import/services/external_import_snapshot_builder.dart:34` 및 `lib/features/external_record_import/providers/external_import_providers.dart:129`.
  - 재현 조건: BBBook에서 이미 기록한 책과 같은 ISBN을 가진 북모리 책을 처음 가져온다. 외부 소스 기반 `clientRequestId`는 기존 BBBook 책의 키와 다르므로 ISBN 매칭 경로를 탄다.
  - `../../api-doc/api-me-records-import-importId-items-post.md`의 `books[n]` 계약상 이 경우 기존 표지를 제외한 필드는 요청 값으로 대체된다. 빌더는 `isMasterpiece=false`를 넣고 난이도·대출 정보·플랫폼·카테고리 등은 채우지 않으며, `bookToImportJson()`은 해당 기본값과 null도 전송한다. 기존 명작 표시와 부가 정보가 지워지고 진행 상태·별점도 외부 기록으로 바뀐다.
  - 사전 동기화는 기존 편집을 서버에 올릴 뿐, 뒤따르는 Import의 덮어쓰기를 막지 않는다. `cancel` API 문서에 따르면 활성 기존 행의 필드 변경은 취소해도 복구되지 않아, 이후 청크가 실패해도 정보 유실이 남는다.

- [P1 문제] 설정 진입과 Android 공유 진입에서 외부 Import가 동시에 실행되어 서로의 서버 세션을 취소할 수 있다.
  - 위치: `lib/features/external_record_import/providers/external_import_providers.dart:112`, `lib/features/external_record_import/widgets/external_import_share_coordinator.dart:81`, `lib/features/external_record_import/services/external_record_import_service.dart:92`.
  - 재현 조건: 설정에서 파일 A를 가져오는 동안 다른 앱으로 이동해 파일 B를 BBBook으로 공유하고, 새로 열린 화면에서 가져오기를 누른다.
  - 공유 coordinator의 `_opening`은 자신이 연 화면만 추적하므로 설정에서 연 Import 화면 위에도 새 화면을 push한다. 컨트롤러는 파일별 family 상태이므로 B는 A의 실행 상태를 알지 못하며, 시작 조건도 저장 방식 전환만 확인한다.
  - `/start`는 계정의 진행 중 세션을 그대로 반환한다. A가 이미 청크를 보냈다면 B가 `importedCount > 0` 분기에서 A의 세션을 취소해 업로드 데이터를 정리한다. 아직 0이라면 두 실행이 같은 세션과 중첩된 localId를 사용해 충돌한다.

- [P2 문제] 제목·저자·출판사가 같은 CSV 행 두 개 때문에 파일 전체를 가져오지 못한다.
  - 위치: `lib/features/external_record_import/services/external_import_snapshot_builder.dart:141`.
  - 재현 조건: 북적북적 CSV에 제목·저자·출판사가 같고 인덱스나 독서 날짜·메모는 다른 기록이 두 행 존재한다.
  - CSV 파서는 각 행의 `인덱스`를 `sourceBookId`로 보존하지만, `_bookIdentity()`는 북모리에서만 이를 사용한다. CSV에는 ISBN도 채우지 않으므로 두 행은 동일한 책 `clientRequestId`를 갖는다. 미리보기에서는 두 행 모두 가져올 수 있다고 표시하지만, 실행 시 `validateRecordImportSnapshot()`의 중복 키 검사에서 전체 파일이 거부된다.

## 개선 제안

- 기존 책 필드 유실 → 사전 동기화 후 ISBN별 기존 기록을 확인하고, 기존 책의 멱등 키·정보를 보존하는 매핑 정책을 적용한다. 외부 값으로 교체할 필요가 있다면 변경될 항목을 미리 보여주고 명시적인 선택을 받는다.
- 동시 Import 충돌 → 설정·공유 진입이 공통으로 사용하는 계정 단위 실행 잠금을 첫 비동기 작업 전에 획득한다. 실행 중 공유 파일은 대기시키고, 다른 실행이 소유한 진행 중 세션을 임의로 취소하지 않도록 한다.
- CSV 식별자 충돌 → 같은 서지 정보의 별도 기록을 구분하는 안정적인 외부 식별자를 사용하거나, 한 책으로 합칠 정책이라면 메모와 독서 정보를 보존해 미리보기 전에 병합한다. 중복 기록 한 쌍 때문에 다른 모든 책까지 거부하지 않도록 한다.
