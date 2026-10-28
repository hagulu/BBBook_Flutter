# 리뷰 결과

## 요약

이전 26건 중 **20건은 지적한 주요 원인이 코드상 보완됐고, 5건은 일부 경로가 남았으며, 1건은 이번 변경에 포함되지 않았습니다.** 아래 판정은 정적 검토 기준입니다. 카메라·OS 복귀 동작까지 실행 검증됐다는 의미는 아닙니다.

## 문제점

이번 수정의 상세 지적은 [FUP-01](../01-sync/20261028-151136-conflict-resolution.md), [FUP-02](../01-sync/20261028-151136-import-completion.md), [FUP-03·04](../02-community/20261028-151136-submission-sheets.md)에 모았습니다. 다음 표는 이전 ID와의 대응이며 별도 신규 건수로 합산하지 않습니다.

| 기능·이전 ID | 판정 | 현재 코드에서 확인한 내용 |
|---|---|---|
| 인증 AUTH-01 | 주요 원인 보완 | `LocalAuthStore.readUser()`가 standalone 소유 저장 모드를 우선해 구형 최초 동기화 키로 이전 계정을 다시 추정하지 않음 |
| 인증 AUTH-02 | 이번 수정 미포함 | 다른 계정이 standalone 기록을 채택할 때 원격 바인딩을 계정별로 재설정하는 변경 없음. 기존 계정 serverId를 보내면 Import 소유권 검사에 걸리는 경로가 남음 |
| 최초 다운로드 INIT-01 | 주요 원인 보완 | 독후감 초기 insert에 server_id 추가, 기존 양수 ID 행의 누락 바인딩 backfill 추가 |
| 책 ID SYNC-01 | 주요 원인 보완 | 음수 책 ID 할당 시 책뿐 아니라 노트·독후감·태그 매핑이 참조 중인 ID까지 확인하며 ZIP 복원도 같은 할당기 사용 |
| 충돌 SYNC-02 | 일부 경로 남음 | 서버 최신 수정 시각 확인·로컬 최신 편집 재전송 추가. 확인 요청의 HTTP 실패가 편집 폐기로 이어짐(FUP-01) |
| 전체 동기화 SYNC-03 | 일부 경로 남음 | 최초 전체 기록·노트·독후감·태그는 서버 exportedAt 사용. 책장 `_fullSync()`는 여전히 기본값으로 기기 DateTime.now를 저장 |
| 동기화 켜기 MODE-ON-01 | 일부 경로 남음 | 동일 실행의 짧은 complete 응답 유실 재확인 추가. 재시도 소진·재시작 뒤 결과 복구는 없음(FUP-02) |
| 청크 MODE-ON-02 | 주요 원인 보완 | 새 노트와 첫 메모 두 항목의 자리를 먼저 확보하고 노트별 메모를 이어 배치함. 운영 청크 크기 500 기준 첫 메모만 다음 청크로 떨어지는 원인 보완 |
| 외부 가져오기 IMP-01 | 주요 원인 보완 | 서버 모드에서는 기존 책 필드 유지·메모 추가로 확인 문구와 결과 요약을 맞춤. 로컬 모드의 덮어쓰기 안내와 구분 |
| 대량 작업 겹침 IMP-02 | 주요 원인 보완 | 외부 Import 실행 락을 저장 모드 양방향 전환·ZIP·설정·백그라운드 동기화가 확인하고, 외부 Import도 진행 중 ZIP/전환 확인 |
| 완독 CSV CSV-01 | 주요 원인 보완 | 파일 내용 기반 UUID v5와 행 위치로 clientRequestId를 고정해 동일 파일 재선택 시 키가 유지됨 |
| ZIP ARC-01 | 주요 원인 보완 | export 결과에 discard 추가, 저장 성공·취소 경로의 finally에서 작업용 폴더 제거 |
| 직접 등록 ADD-01 | 주요 원인 보완 | 논리적 저장 중 가드·PopScope·기존 AppLoading을 함께 사용하며 await 전 필요한 notifier/repository 확보 |
| ISBN REC-01 | 주요 원인 보완 | 로컬 ISBN 연결의 중복 검사와 Import 사전 중복 검증 추가 |
| 노트 NOTE-01 | 주요 원인 보완 | 신규 화면의 rebuild 시 기존 생성 noteId를 보존하고 그 ID로 다시 조회 |
| 공개 설정 REF-01 | 주요 원인 보완 | 공개 변경과 본문 push가 독후감별 쓰기 큐를 공유하며 대기 후 서버 ID를 다시 읽음 |
| 바코드 DEV-01 | 주요 원인 보완·실기기 미검증 | lifecycle observer에서 inactive 중지·resumed 시작 처리와 예외 처리 추가 |
| 바코드 DEV-02 | 주요 원인 보완·실기기 미검증 | 빠른 등록에 scanWindow를 지정해 인식 범위를 화면 중앙으로 제한 |
| 바코드 DEV-03 | 주요 원인 보완 | 로컬 빠른 등록도 상세 메타를 조회해 생성하며 상세 조회 실패를 처리 |
| 바코드 DEV-04 | 주요 원인 보완 | 도움말 모달 등으로 스캐너 route가 현재 화면이 아니면 인식 처리하지 않음 |
| 독자평 REV-01 | 일부 경로 남음 | 비동기 onSubmit 성공 뒤에만 닫고 실패 시 입력 유지. 드래그 닫기와 전송 중 추가 편집은 FUP-03·04로 남음 |
| 토론 COMM-01 | 일부 경로 남음 | 전체 화면 폼과 답변에 PopScope 추가. 답변 시트의 드래그 닫기는 FUP-03으로 남음 |
| 토론 COMM-02 | 주요 원인 보완 | 새로고침 generation을 증가시키고 이전 loadMore 응답·오류의 상태 반영을 차단 |
| 탈퇴 PROF-01 | 주요 원인 보완 | 서버 성공 후 auth 정리를 화면 mounted 여부와 분리하고, 요청 전 auth/api 참조 확보 |
| 설정 SET-01 | 주요 원인 보완 | 동기화 끄기 확인창을 로컬 모드 로그아웃의 기록 보존 정책에 맞게 변경 |
| 재시도 NET-01 | 주요 원인 보완 | 검색·추가 로드·책 상세의 사용자 재시도에서 ApiClient 대기 상태를 해제 |

### 별도 상태 확인이 필요한 기존 잔여 항목

**AUTH-02**의 근거는 [lib/features/auth/providers/auth_notifier.dart:345](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/auth/providers/auth_notifier.dart:345)의 채택과 [lib/features/auth/data/local_auth_store.dart:159](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/auth/data/local_auth_store.dart:159)의 소유자 변경입니다. 이번 변경은 AUTH-01의 부팅 복원 우선순위이며 다른 계정용 serverId 전환까지 포함하지 않습니다. 동일 계정 복귀 시 필요한 바인딩을 무조건 지우는 대응은 피해야 합니다. 원래 계약·발생 조건은 [이전 인증 리뷰](../../20261028-124818-full-review/01-auth/20261028-124818-login-logout-ownership.md)에 있습니다.

**SYNC-03**의 잔여 근거는 [lib/features/bookshelf/data/bookshelf_repository.dart:225](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/bookshelf/data/bookshelf_repository.dart:225)입니다. 기기 시간이 서버보다 앞설 때 이 baseline 이후로 잡히지 않는 변경이 생길 수 있습니다. 이번 노트·독후감·태그 보완은 효과가 있으나 책장 경로까지 해결된 상태는 아닙니다. 원래 범위는 [이전 동기화 리뷰](../../20261028-124818-full-review/02-sync/20261028-124818-background-data-integrity.md)에 있습니다.

## 개선 제안

우선 충돌 오류 분기(FUP-01)를 고치고, 완료 결과 미확정(FUP-02)의 복구 정책을 구체화하는 것이 좋습니다. 입력 시트 2건은 기능 내부의 작은 수정으로 다룰 수 있습니다. 기존 미반영 AUTH-02·잔여 SYNC-03은 해결 완료로 닫지 않고 후속 목록에 유지합니다.

## 실행 결과와 범위

| 항목 | 결과 |
|---|---|
| `flutter analyze` | 통과 — No issues found! (3.3초) |
| 코드 변경 | 앱 수정 없음. 리뷰 폴더와 인덱스만 작성 |
| 변경분 확인 | 앱 코드 39파일과 관련 DAO/API/호출부, 이전 리뷰 26건 대조 |
| API 계약 | 로컬 `../../api-doc`의 Import 시작·항목·첨부·완료·취소 계약 확인 |
| Flutter 동작 | 설치된 SDK의 BottomSheet 드래그·Navigator.pop 경로 확인 |
| 테스트 | 요청이 없어 실행하지 않음 |
| 앱·실기기 | 프로젝트 지침에 따라 실행하지 않음 |
| 백엔드 소스·MCP | 사용하지 않음 |

## 후속 수동 확인 목록

실행 결과가 아니라 향후 확인 시나리오입니다.

- 동기화: 충돌 확인 GET 오류에도 미전송 편집 유지, 정상 비교 후 필요한 필드만 재전송, 책장 전체 조회 뒤 서버 기준 시각 확인.
- 대량 업로드: 완료 응답 유실·장시간 연결 끊김·재시작 뒤 같은 작업 결과 복구, PHOTO 메모 재시도, 실패 후 추가 로컬 편집 보존.
- 입력·터치: 요청 중 시트 드래그·바깥 탭·뒤로 가기, 응답 대기 중 본문·별점·스포일러 변경, 실패 후 재전송.
- 계정·저장 모드: 최초 다운로드 후 동기화 끄기→로그아웃→재실행, 같은 계정과 다른 계정의 기록 이어받기 구분, 대량 작업 중 저장 모드 전환 차단.
- 기기: 바코드 화면에서 홈 이동·복귀, 권한 화면 왕복, 도움말 표시 중 인식 차단, 빠른 연속 스캔, 회전 후 중앙 인식 범위 정렬. 정적 보완만으로 native 동작을 확정하지 않음.

희귀한 이벤트 조합만을 전제로 한 방어, 모든 실패의 자동 재전송, 기록 자동 삭제, 전면 리팩터링은 후속 목록에 추가하지 않았습니다.
