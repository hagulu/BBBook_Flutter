# 리뷰 결과

## 요약
청크 전송과 완료 후 로컬 반영 순서는 적절하지만, 완료 응답을 잃었을 때의 복구와 제목 없는 노트의 청크 경계가 문제입니다. P1 1건, P2 1건입니다.

## 확인 범위
로컬 스냅샷, 식별자 백필, 사전 검증, 청크 분할, 표지·메모 사진 첨부, complete, 로컬 ID 매핑 반영, 서버 모드 변경과 재시도를 확인했습니다.

## 문제점

### [MODE-ON-01][P1] complete는 서버에서 성공했는데 응답을 못 받으면 재시도가 안전하지 않음

- 조건: 마지막 `/complete` 처리 중 통신이 끊기거나 앱이 종료돼 서버 확정 결과를 앱이 받지 못합니다. 대량 전송 중 일반적으로 고려해야 하는 응답 유실입니다.
- 근거: [lib/features/server_storage_migration/services/server_storage_migration_service.dart:298](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/server_storage_migration/services/server_storage_migration_service.dart:298)은 완료 응답 후에만 로컬 ID·이미지 결과를 적용합니다. 세션 ID와 완료 직전 매핑은 실행 메모리에만 있고, 재시도는 다시 start부터 실행합니다. [lib/features/server_storage_migration/data/server_storage_migration_repository_steps.dart:131](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/server_storage_migration/data/server_storage_migration_repository_steps.dart:131)에도 이 잔여 경로가 설명돼 있습니다.
- 영향 1: 이미 서버에 이미지가 붙은 PHOTO 메모를 로컬에서는 여전히 미업로드로 판단해 다시 첨부합니다. API 계약상 Import 전부터 이미지가 있는 메모에는 첨부할 수 없어 재시도가 반복 실패할 수 있습니다.
- 영향 2: 사용자가 실패 안내를 보고 로컬 기록을 수정한 뒤 재시도하면, 이전에 확정된 활성 서버 행은 Import에서 내용을 덮지 않고 재사용합니다. 그런데 [lib/features/bookshelf/data/bookshelf_dao.dart:1343](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/bookshelf/data/bookshelf_dao.dart:1343) 등의 확정 반영은 해당 로컬 행의 dirty를 해제하므로 이후 동기화에서 수정 내용이 사라질 수 있습니다.
- 계약 근거: [../../api-doc/api-me-records-import-start-post.md:11](/Users/hagulu/develop/service/BBBook/project/app/bbbook/../../api-doc/api-me-records-import-start-post.md:11), [../../api-doc/api-me-records-import-importId-complete-post.md:5](/Users/hagulu/develop/service/BBBook/project/app/bbbook/../../api-doc/api-me-records-import-importId-complete-post.md:5), [../../api-doc/api-me-records-import-importId-items-post.md:136](/Users/hagulu/develop/service/BBBook/project/app/bbbook/../../api-doc/api-me-records-import-importId-items-post.md:136), [../../api-doc/api-me-records-import-importId-attachments-post.md:5](/Users/hagulu/develop/service/BBBook/project/app/bbbook/../../api-doc/api-me-records-import-importId-attachments-post.md:5).

### [MODE-ON-02][P2] 새 제목 없는 노트가 첫 메모와 다른 청크로 떨어질 수 있음

- 근거: [lib/features/server_storage_migration/data/record_import_payload_builder.dart:211](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/server_storage_migration/data/record_import_payload_builder.dart:211)은 모든 notes를 넣은 뒤 모든 noteMemos를 넣습니다. 서버의 `maxChunkItemCount` 경계에서 새 노트만 있는 청크가 생깁니다.
- 일반 데이터 예: 서버 ID가 없는 책 250개, 제목 없이 메모를 작성한 새 노트 250개, 메모 250개를 한도 500으로 전송하면 첫 청크는 books 250 + notes 250이고 메모는 없습니다.
- 영향: [../../api-doc/api-me-records-import-importId-items-post.md:152](/Users/hagulu/develop/service/BBBook/project/app/bbbook/../../api-doc/api-me-records-import-importId-items-post.md:152)의 신규 제목 전용 노트 계약과 맞지 않습니다. 같은 요청에 메모도 기존 serverId도 없는 제목 null 노트가 되어 400과 세션 롤백 대상이 될 수 있습니다. 사전 검증은 전체 스냅샷에 메모가 있는지만 보기 때문에 통과합니다. 실서버 실행으로 재현한 결과는 아니며, 문서 계약과 분할 결과를 대조한 항목입니다.

## 개선 제안

- MODE-ON-01: 완료 직전 세션·매핑·스냅샷 식별자를 내구성 있게 남기고, 결과가 불명확한 작업은 확정 여부를 확인한 뒤 반영하도록 복구 범위를 제한합니다. 서버의 현재 조회·완료 계약만으로 확실히 구별할 수 없는 부분은 API 계약 보완도 필요합니다. 데이터 유실 위험이라 이 항목은 수정 범위가 넓어져도 우선 검토할 가치가 있습니다. 단순히 첨부 실패를 무시하거나 모든 dirty를 해제하는 방식은 안전하지 않습니다.
- MODE-ON-02: 새 제목 없는 노트와 최소 첫 메모를 같은 청크에 배치합니다. 부모 책 선행과 총 항목 한도를 함께 유지합니다. 전체 분할 구조를 바꾸기 전에 청크 단위 계약만 좁게 검증하면 됩니다.

## 확인된 보호 장치

청크·첨부 성공 직후에는 server_id를 로컬에 확정하지 않고 complete 후 한 트랜잭션으로 적용합니다. 표지는 `created` 대신 `coverUploadRequired`로 첨부 여부를 판단합니다. 이미지 개수·파일 형식·용량과 태그 수 등 사전 검증이 있으며 중복 start는 진행 중 Future를 공유합니다.
