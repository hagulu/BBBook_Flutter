# 리뷰 결과

## 요약
- 저장 방식 전환 흐름에서 서버 이미지를 로컬에 보존했다고 잘못 판단하거나, 보존하지 못한 사실을 사용자에게 알리지 않는 문제 3건을 확인했다.

## 문제점
- [P1][책 표지를 로컬에 확보하지 않고 서버 기록을 정리함] `lib/features/storage_mode/data/local_storage_migration_steps.dart:54-85`, `lib/features/bookshelf/data/bookshelf_dao.dart:1169-1173`, `lib/features/bookshelf/screens/widgets/book_cover.dart:33-69` — 새 다운로드 단계는 메모 사진과 독후감 이미지만 처리한다. 다른 기기에서 올린 사용자 지정 책 표지는 이 기기에 `local_cover_path`가 없으므로 서버 URL을 계속 사용한다. 로컬 모드로 전환한 뒤 오프라인에서는 표지를 볼 수 없고, 서버의 삭제 기록과 첨부 파일이 정리되면 사본 없이 표지를 잃을 수 있다. 설정 화면의 “최신 기록과 이미지를 받아 이 기기에 남긴다”는 안내와도 다르다.
- [P1][파일이 사라진 이미지의 DB 경로를 완료로 오인할 수 있음] `lib/features/book_note/data/book_note_repository.dart:486`, `lib/features/book_reflection/data/book_reflection_repository.dart:332`, `lib/features/storage_mode/data/local_storage_migration_steps.dart:47-50`, `lib/features/storage_mode/services/local_storage_migration_service.dart:155-192` — 동기화는 사라진 파일의 DB 연결을 지우는 `sweepLocalImages()`를 기다리지 않는다. 다운로드 대상과 누락 개수는 DB 연결 유무로 판정하므로, `local_image_path` 또는 독후감 이미지 매칭은 남아 있지만 실제 파일이 없는 상태에서 sweep이 늦게 끝나면 누락 개수를 0으로 보고 서버 기록 삭제까지 진행할 수 있다. 이후 sweep이 연결을 지우더라도 로컬 모드에서는 다시 내려받지 않는다.
- [P2][받을 수 없는 이미지의 누락 사실이 완료 화면에 보이지 않음] `lib/features/storage_mode/services/local_storage_migration_service.dart:154-181`, `lib/features/profile/screens/profile_settings_screen.dart:419-440` — 다운로드가 403/404 등을 반환하면 해당 이미지는 재시도 대상 개수에서 제외되어 추가 확인 없이 전환한다. `unavailableImages`에 건수가 기록돼도 설정 화면은 `completed` 진행 카드를 즉시 숨기고 결과 알림을 표시하지 않는다. 사용자는 일부 이미지가 이 기기에 저장되지 않은 채 서버 기록이 정리됐다는 사실을 알 수 없다.

## 개선 제안
- 책 표지 미보존 → 서버 URL만 있는 사용자 지정 표지를 로컬 파일로 내려받고, 누락 여부를 전환 전 검증한다.
- 사라진 파일의 DB 경로 오인 → 전환 전 메모·독후감 이미지 sweep 완료를 기다린 뒤 다운로드와 누락 검사를 수행하고, 최종 검사에서는 파일 존재 여부도 확인한다.
- 받을 수 없는 이미지의 조용한 누락 → 전환 전 누락 건수를 사용자에게 알리거나 완료 후에도 확인 가능한 경고를 표시한다. 이전 다운로드에서 제외된 URL도 건수에 포함한다.
