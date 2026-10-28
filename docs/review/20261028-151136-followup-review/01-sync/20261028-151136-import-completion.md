# 리뷰 결과

## 요약

`completeConfirmingDelivery()`는 짧은 응답 유실 후 같은 실행 안에서 완료 여부를 확인하는 데 도움이 됩니다. 하지만 **재시도 소진이나 앱 재시작 뒤의 결과 불명확 상태는 여전히 일반 실패로 끝나고, 재시도가 새 Import로 시작돼 사진 전환 실패·편집 유실로 이어질 수 있습니다.** 기존 MODE-ON-01의 잔여 P1 1건입니다.

## 문제점

### [FUP-02][P1] 완료 결과가 불명확한 Import를 일반 실패로 처리해 다음 실행에서 안전하게 이어받지 못함

**위치**

- [lib/features/server_storage_migration/data/record_import_api.dart:149](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/server_storage_migration/data/record_import_api.dart:149): 같은 importId로 완료를 다시 요청하고 409이면 확정을 확인하지만, 추가 재시도는 두 번으로 끝납니다. importId·매핑을 다음 실행에 사용할 수 있도록 저장하는 처리는 없습니다.
- [lib/features/server_storage_migration/services/server_storage_migration_service.dart:297](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/server_storage_migration/services/server_storage_migration_service.dart:297): 서버 완료 이후에야 로컬 매핑을 적용하고 모드를 전환합니다. 실패는 330행의 공통 catch에서 일반 실패로 안내합니다.
- [lib/features/server_storage_migration/services/server_storage_migration_service.dart:126](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/server_storage_migration/services/server_storage_migration_service.dart:126): 사용자가 다시 시작하면 현재 로컬 스냅샷으로 `/start`부터 진행합니다.
- [lib/features/bookshelf/data/bookshelf_dao.dart:1369](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/bookshelf/data/bookshelf_dao.dart:1369): 결과 반영은 연결된 책의 dirty와 변경 필드도 지웁니다.
- [lib/features/server_storage_migration/data/server_storage_migration_repository_steps.dart:129](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/server_storage_migration/data/server_storage_migration_repository_steps.dart:129): 구현 주석에도 확정 후 앱 종료와 재첨부 400의 잔여 위험이 기록돼 있습니다.

**일반적인 발생 조건 A — 사진이 있는 데이터**

1. 로컬 PHOTO 메모를 포함해 동기화 켜기를 진행하고 서버 `/complete`는 성공합니다.
2. 완료 응답을 받는 시점에 연결이 끊기고, 연결이 추가 재시도 이후까지 복구되지 않습니다. 또는 작업 중 앱을 닫았다가 다음에 다시 실행합니다.
3. 서버는 이미 확정됐지만 로컬은 서버 ID·사진 URL을 반영하지 못한 채 로컬 모드로 남습니다.
4. 나중에 재시도하면 새 세션이 기존 메모를 재사용합니다. 로컬에는 업로드 완료 URL이 없어 다시 첨부를 시도합니다.
5. 새 세션 이전부터 서버 메모에 붙어 있는 사진이므로 첨부 API는 400을 반환합니다. 보통의 재시도로 전환을 끝낼 수 없습니다.

**일반적인 발생 조건 B — 실패 후 추가 편집**

사진이 없는 기록이라 재시도가 완료되는 경우에도 위험이 있습니다. 위처럼 첫 완료 결과를 잃은 뒤 사용자가 로컬 감상 A를 B로 바꾸고 나중에 다시 전환하면, `/items`는 이미 활성인 서버 책의 A를 유지합니다. 클라이언트는 새 로컬 B가 반영됐다는 확인 없이 매핑을 적용하면서 dirty를 지웁니다. 이후 서버 재조회 때 B가 A로 되돌아갈 수 있습니다.

두 조건은 오래 지속되는 통신 장애 또는 업로드 뒤 앱을 닫았다가 재시도하는 흐름입니다. 서버 완료와 로컬 반영 사이의 극단적으로 짧은 순간만을 전제로 하지 않습니다.

**계약 대조**

- [api-me-records-import-start-post.md:13](/Users/hagulu/develop/service/BBBook/project/app/bbbook/../../api-doc/api-me-records-import-start-post.md:13): 진행 중 세션은 재사용하지만 이미 완료된 세션은 다음 `/start`의 진행 중 세션이 아닙니다.
- [api-me-records-import-importId-items-post.md:136](/Users/hagulu/develop/service/BBBook/project/app/bbbook/../../api-doc/api-me-records-import-importId-items-post.md:136): 어떤 키로 매칭하든 활성 기존 책은 값을 수정하지 않습니다. 멱등 재사용은 중복 생성 방지이며 새 로컬 편집 반영을 보장하지 않습니다.
- [api-me-records-import-importId-attachments-post.md:31](/Users/hagulu/develop/service/BBBook/project/app/bbbook/../../api-doc/api-me-records-import-importId-attachments-post.md:31): 동일 세션의 사진 재첨부는 허용하지만, Import 이전부터 이미지가 연결된 메모의 재첨부는 거부합니다. 세션이 달라지면 조건도 달라집니다.
- [api-me-records-import-importId-cancel-post.md:65](/Users/hagulu/develop/service/BBBook/project/app/bbbook/../../api-doc/api-me-records-import-importId-cancel-post.md:65): 취소의 409로 COMPLETED를 확인하는 이번의 한정된 사용은 문서와 맞습니다. 그 확인 방법 자체를 결함으로 지적한 것은 아닙니다.

## 개선 제안

완료 결과가 불명확한 상태를 일반적인 업로드 실패와 구분합니다. 새 세션을 열기 전에 **같은 작업의 확정 여부와 해당 매핑을 확인·복구할 수 있어야** 합니다. importId·확정 전 매핑·반영 대상 스냅샷 식별 정보를 완료 요청 전후에 지속 저장하는 방식과, 필요한 결과 확인 API 계약을 함께 검토할 수 있습니다. 확인된 기존 서버 값과 다른 로컬 편집을 성공 처리하면서 dirty에서 지우지 않아야 합니다.

짧은 자동 재확인은 유지할 가치가 있습니다. 재시도 횟수를 무작정 늘리거나, 사진을 자동 삭제하거나, 기존 서버 기록을 덮어써 문제를 감추는 대응은 권하지 않습니다. 확정 결과 복구는 변경 범위가 넓을 수 있지만 원본 유실 위험 때문에 검토할 필요가 있습니다. 이번 리뷰에서는 앱 코드를 변경하지 않았습니다.

## 후속 검증 시나리오

아직 실행하지 않았습니다.

1. 서버 완료 성공 뒤 응답만 유실시키고, 확인 재시도 시간보다 길게 연결을 끊었다가 복구합니다. 사진을 삭제하거나 재선택하지 않아도 전환을 마칠 수 있어야 합니다.
2. 같은 조건 뒤 앱을 다시 실행해도 같은 작업의 결과를 확인할 수 있어야 합니다.
3. 결과 불명확 후 로컬 텍스트를 추가 편집한 경우 새 편집이 그대로 남고 실제 서버 반영 전까지 미전송 상태가 유지돼야 합니다.
4. 일반적인 서버 검증 실패로 롤백된 경우와 이미 확정된 경우를 구분해야 합니다.
