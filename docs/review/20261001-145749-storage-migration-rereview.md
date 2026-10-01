# 리뷰 결과

## 요약
- 메모·독후감 이미지 정리 작업을 기다리도록 개선됐지만, 책 표지의 실제 파일 확인과 다운로드 불가 이미지 안내에 문제가 남아 있다.

## 문제점
- [P1][없는 책 표지 파일을 확보한 것으로 판정함] `lib/features/bookshelf/data/bookshelf_repository.dart:77-92`, `lib/core/storage/local_image_store.dart:127-132`, `lib/features/bookshelf/data/bookshelf_dao.dart:146-153` — `_uploadedCoversPendingDownload()`는 `resolve(localCoverPath) != null`이면 표지가 있다고 판단하지만, `resolve()`는 경로에 해당하는 `File` 객체만 만들고 파일 존재 여부는 확인하지 않는다. `local_cover_path`가 남아 있고 실제 파일이 삭제됐거나 0바이트인 경우 다운로드와 누락 검사에서 모두 빠진다. 전환 후 그 경로가 `cover_image_url`로 승격되고 서버 기록은 정리되어 사용자 지정 표지를 잃을 수 있다.
- [P2][다운로드 불가 이미지가 있어도 누락 안내 없이 완료됨] `lib/features/storage_mode/services/local_storage_migration_service.dart:154-183`, `lib/features/profile/screens/profile_settings_screen.dart:419-440`, `lib/features/bookshelf/data/bookshelf_repository.dart:81-84` — 403/404 등으로 받을 수 없는 메모·독후감 이미지나 책 표지는 누락 검사에서 제외된다. 서비스가 `unavailableImages`를 보관해도 설정 화면은 완료된 진행 카드를 숨겨 누락 사실을 표시하지 않는다. 책 표지는 같은 앱 세션에서 다시 전환을 시도할 때 `_unavailableCoverUrls`에 남아 재시도 및 이번 결과 건수에서도 빠진다.

## 개선 제안
- 없는 책 표지 파일 오판 → `resolve()`가 반환한 파일의 존재 여부와 크기를 확인하고, 로컬 모드 전환 직전에도 승격할 표지 사본을 검증한다.
- 다운로드 불가 이미지의 조용한 누락 → 서버 기록 정리 전 누락 건수를 알리고 사용자의 선택을 받거나, 완료 후에도 확인 가능한 경고를 표시한다. 이전 시도에서 제외된 표지도 누락 건수에 포함한다.
