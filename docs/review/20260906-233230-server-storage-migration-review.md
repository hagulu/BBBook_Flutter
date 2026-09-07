# 리뷰 결과

## 요약

- 로컬 → 서버 저장 전환의 기본 단계 분리는 명확하지만, 실제 이미지 복구와 전환 직후 데이터 정합성을 깨뜨릴 수 있는 높은 우선순위 문제 3건과 사전 검증 누락 1건이 있어 수정이 필요하다.

## 문제점

- [문제][높음] 기존 서버 PHOTO 메모까지 무조건 신규 첨부로 다시 올려 전환이 롤백된다. `record_import_snapshot_builder.dart:79`는 모든 PHOTO 메모를 `pendingMemoImages`에 넣고, `record_import_payload_builder.dart:63`은 기존 `imageUrl`도 항상 `null`로 바꾸며, `server_storage_migration_service.dart:201`은 해당 사진을 전부 `/attachments`로 올린다. 그러나 API 문서는 Import 이전부터 이미지가 연결돼 있던 PHOTO 메모에는 첨부를 거부한다고 명시한다. 서버 → 로컬 전환은 행을 soft delete할 뿐 기존 `image_url`을 지우지 않으므로, 서버에서 내려받은 PHOTO 메모가 하나라도 있으면 복구 후 첨부 단계에서 400이 발생하고 세션 전체가 정리될 수 있다. 현재 테스트도 기존 `imageUrl`을 일부러 버리는 동작을 정상으로 고정하고 있어 이 계약 위반을 잡지 못한다.
- [문제][높음] Import 응답에 없는 서버 `updated_at` 대신 과거 로컬 시각을 `synced_updated_at`으로 확정한다. `bookshelf_dao.dart:961`은 Import 전 로컬 행의 `updated_at`을 읽어 `bookshelf_dao.dart:975`에 충돌 검사 기준값으로 저장하지만, `/items` 응답은 서버 ID만 반환하고 Import로 생성·복구된 서버 행의 실제 `updated_at`은 반환하지 않는다. 전환 직후 첫 기록 수정은 이 오래된 시각을 `PATCH /api/me/books/{userBookId}`의 `updatedAt`으로 보내 409가 되고, 기존 `resolveConflict` 경로는 그 사이 추가 수정이 없으면 방금 만든 dirty 상태를 해제하므로 사용자 편집이 서버에 반영되지 않는다. 전환 완료 시 실제 서버 시각을 동기화하지도 않아 첫 수정 전에 자동으로 보정된다는 보장도 없다.
- [문제][높음] `/complete` 성공과 로컬 모드 전환 사이의 결과가 메모리에만 있어 장애 후 안전하게 재개할 수 없다. `server_storage_migration_service.dart:249`에서 서버 세션을 먼저 확정한 뒤, `server_storage_migration_repository_steps.dart:109`의 네 개 개별 DAO 트랜잭션과 `server_storage_migration_service.dart:275`의 모드 전환을 순차 수행한다. 이 구간에서 DB 오류, 앱 종료, 또는 `/complete` 성공 응답 유실이 생기면 서버 데이터는 이미 활성인데 앱은 계속 로컬 모드이고 ID 매핑도 전부 또는 일부만 반영된다. 다음 시도에서 활성 기존 독후감은 API 정책상 본문을 덮어쓰지 않으며 첨부도 거부하므로, 이미지가 있는 독후감은 반복 실패하고 그 사이 로컬 본문을 수정했다면 서버에 반영되지 않은 채 전환될 수 있다. 코드 주석의 “다음 재시도도 멱등 키 덕분에 안전”은 독후감 재사용·첨부 계약까지는 성립하지 않는다.
- [문제][중간] 로컬 모드에서 허용되는 255자 초과 노트 제목을 사전 검증하지 않는다. `book_note_detail_screen.dart:200`의 제목 `TextField`에는 `maxLength`가 없고 로컬 저장 모드에서는 서버 검증을 거치지 않아 긴 제목을 저장할 수 있지만, `record_import_validation.dart:45`는 신규 노트의 제목 존재 여부만 확인한다. Import API는 제목이 255자를 넘으면 400으로 세션 전체를 정리하므로 사용자는 원인을 알 수 없는 일반 실패만 받고 같은 재시도를 반복하게 된다.

## 개선 제안

- 기존 PHOTO 메모 재첨부 → `/items` 응답의 `created`, 로컬의 기존 `imageUrl`, 세션 복구 여부를 함께 사용해 실제로 새 이미지 연결이 필요한 메모만 `/attachments` 대상으로 만들고, 서버에 남아 있는 유효한 키는 유지하도록 분기한다. 기존 이미지 보유 메모와 신규 로컬 PHOTO 메모를 나눈 계약 테스트를 추가한다.
- 잘못된 `synced_updated_at` → 서버 시각을 알 수 없는 상태에서는 `synced_updated_at`을 `null`로 두어 첫 수정의 충돌 검사를 생략하거나, 모드 전환 완료 전에 서버 전체 동기화를 수행해 응답의 실제 `updatedAt`으로 기준값을 채운다. Import 직후 첫 기록 수정이 409 없이 저장되는 경로를 검증한다.
- `/complete` 이후 복구 불가 → 청크 응답의 localId↔serverId와 이미지 치환 결과를 로컬 임시 테이블에 내구성 있게 저장하고, 완료 여부와 함께 재개할 수 있게 한다. `/complete` 뒤의 도메인 행 반영과 저장 모드 전환은 가능한 한 하나의 로컬 트랜잭션으로 묶고, 재실행 시 활성 독후감을 새 Import로 다시 보내기 전에 완료된 세션 결과를 우선 확정한다.
- 노트 제목 길이 누락 → 제목 입력에 255자 제한을 적용하고, 과거·비정상 로컬 데이터까지 처리하도록 `validateRecordImportSnapshot`에도 `note.title.length > 255` 검사를 추가해 세션 시작 전에 수정 가능한 안내를 보여준다.
