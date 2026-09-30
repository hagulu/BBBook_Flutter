# 리뷰 결과

## 요약
- 현재 작업 트리의 로그아웃 직전 동기화 변경에는 충돌 시 기록 유실을 알리지 못하는 문제와 화면 종료 후 참조를 사용하는 문제가 있습니다.

## 문제점
- [높음] `lib/features/record_sync/providers/logout_record_sync_provider.dart:40` — 남은 `is_dirty` 행만 확인해 안전한 로그아웃 여부를 결정합니다. 그런데 책 기록 push가 409 충돌을 받으면 `BookshelfDao.resolveConflict()`는 해당 로컬 수정의 `is_dirty`를 0으로 바꾸고, 이어지는 전체 동기화가 서버 값으로 덮어씁니다(`lib/features/bookshelf/data/bookshelf_dao.dart:727`, `lib/features/bookshelf/data/bookshelf_repository.dart:327`). 따라서 최종 동기화 중 로컬 수정이 폐기되어도 미동기화 기록이 없다고 판단해 경고 없이 로그아웃합니다.
- [보통] `lib/features/profile/screens/profile_screen.dart:677` — 최종 동기화가 끝나 `true`를 반환한 뒤 화면이 아직 살아 있는지 확인하지 않고 `WidgetRef`로 로그아웃을 호출합니다. 동기화 중 라우트 변경 등으로 화면이 제거되면 폐기된 `WidgetRef`를 읽어 예외가 발생할 수 있습니다.

## 개선 제안
- 409 충돌로 로컬 수정이 폐기되는 경우 → 최종 동기화 결과에 충돌/폐기 여부를 포함하고, 자동 로그아웃 전에 사용자가 그 사실을 확인하도록 합니다. `is_dirty`가 0인지 여부만으로 성공을 판정하지 않습니다.
- 동기화 완료 후 화면이 제거된 경우 → `authNotifierProvider.notifier`를 읽기 전에 `context.mounted`를 다시 확인하고, 제거됐다면 로그아웃 흐름을 종료합니다.
