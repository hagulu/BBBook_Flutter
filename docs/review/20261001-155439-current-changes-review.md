# 리뷰 결과

## 요약
- 현재 변경분에서 저장 방식 전환의 표지 복구 누락 1건과 사용자 안내·토론 답변 표시 문제 2건을 확인했다.

## 문제점
- [P1][중단된 전환의 서버 정리에서 표지 원본 경로를 복구하지 않음] `lib/features/storage_mode/data/local_storage_migration_steps.dart:110-121`, `lib/features/storage_mode/providers/storage_mode_providers.dart:85-89`, `lib/features/server_storage_migration/data/record_import_snapshot_builder.dart:91-109` — `switchToLocal()`이 먼저 `LOCAL`과 서버 정리 대기를 저장한 뒤 진행 중인 동기화를 기다리고 표지 사본을 `cover_image_url`로 승격한다. 그 사이 앱이 종료되면 재진입 시 `retryServerCleanup()`은 승격 없이 서버 기록만 삭제한다. 화면은 `local_cover_path`로 표지를 계속 보여주지만 원본 컬럼에는 삭제될 서버 URL이 남는다. 나중에 서버 저장으로 다시 전환하면 Import가 이 URL을 기존 원격 표지로 판단해 로컬 사본을 업로드하지 않으므로, 서버 정리 후 표지를 잃을 수 있다.
- [P2][확보하지 못한 이미지가 있어도 완료 화면에서 알리지 않음] `lib/features/storage_mode/services/local_storage_migration_service.dart:154-162`, `lib/features/profile/screens/profile_settings_screen.dart:431-440`, `lib/features/bookshelf/data/bookshelf_repository.dart:81-83` — 403/404 등으로 받을 수 없는 이미지는 `unavailableImages`에 기록되지만 완료 상태에서는 진행 카드가 즉시 사라지고 별도 안내가 없다. 책 표지는 같은 앱 세션의 다음 시도에서 제외되어 이번 결과 건수에도 잡히지 않는다. 사용자는 이미지가 누락된 채 서버 기록이 정리된 사실을 확인할 수 없다.
- [P2][숨김 답변만 있는 페이지를 답변이 없는 토론으로 표시함] `lib/features/discussion/models/discussion_answer.dart:101-110`, `lib/features/discussion/screens/discussion_detail_screen.dart:823-888` — 답변 `items`에서 숨김 항목을 제거하지만 서버의 `totalElements`와 `totalPages`는 그대로 둔다. 한 페이지가 모두 숨김 답변이면 화면은 양수인 전체 답변 수를 표시하면서 동시에 “아직 답변이 없습니다.”라고 안내한다. 뒤 페이지에 공개 답변이 있어도 현재 페이지가 빈 화면으로 보인다.

## 개선 제안
- 중단된 전환의 표지 경로 누락 → 로컬 모드 기록과 표지 사본 승격을 복구 가능한 한 단계로 묶고, 서버 정리 재시도에서도 승격 완료를 확인한 뒤 삭제한다.
- 확보하지 못한 이미지의 무안내 → 서버 기록을 정리하기 전에 누락 건수를 보여주거나 완료 후에도 확인 가능한 경고를 남긴다. 이전 시도에서 제외한 URL도 누락 집계에 포함한다.
- 숨김 답변의 빈 페이지 → 공개 답변 기준으로 집계·페이지를 구성하거나, 빈 페이지를 건너뛰고 전체 답변 수와 빈 상태 문구를 실제 노출 항목에 맞춘다.
