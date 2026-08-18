# 리뷰 결과

## 요약
- 개인 메모(`book_memo`)와 최초 기록 동기화(`record_sync`) 기능은 트랜잭션 처리, 세션 세대 체크 등 기존 코드베이스 패턴을 대체로 잘 따르지만, 선택 상태 시각 대비를 없앤 접근성 회귀와 서버 백업이 없는 메모 데이터가 로그아웃 시 영구 삭제되는 문제가 있다.

## 문제점
- [높음][접근성] 선택 상태를 표시하던 보더가 6개 파일에서 모두 제거되어, `AppColors.accentFill`(라임)과 `AppColors.surfaceSubtle` 배경의 대비가 약 1.36:1로 사실상 구분되지 않는데도 색상만으로 선택 여부를 나타낸다. `lib/features/book_record/screens/widgets/pill_option.dart:34-37`, `lib/features/book_search/screens/book_search_screen.dart:373-375`, `lib/features/bookshelf/screens/widgets/finished_filter_panel.dart:189-195`(공용 필 칩), `lib/features/book_record/screens/widgets/icon_option_selector.dart:78-84`, `lib/features/book_record/screens/widgets/meta_dialogs.dart:64-70`(카드형 선택), `lib/features/book_record/screens/widgets/book_category_field.dart:169-175`(카테고리 칩)이 모두 `selected ? 강조색 : 기본색` 형태였던 보더 조건을 지우고 고정 보더/투명 보더로 바꿨다. `icon_option_selector.dart:21-22`의 클래스 주석은 여전히 "선택된 카드만 파란 보더 + 옅은 강조 배경으로 두드러지게 한다"고 설명하지만 실제 코드는 더 이상 그렇게 동작하지 않는다. 같은 저장소에 이미 커밋된 접근성 대비 리뷰(`docs/review/20260817-153500-forest-color-palette-review.md`) 대응으로 추가됐던 보더 보강을 이번 작업 범위에서 의도치 않게 되돌린 것으로 보인다.
- [높음][데이터] 개인 메모(`book_memo`)와 독후감(`book_reflection`)은 `BookMemoRepository`가 "네트워크/API 의존성을 갖지 않는다"고 명시할 만큼 서버 업로드 경로가 전혀 없는 로컬 전용 데이터다. 그런데 로그아웃 흐름(`lib/features/auth/providers/auth_notifier.dart`)이 호출하는 `BookshelfDatabase.clearAll()`(`lib/features/bookshelf/data/bookshelf_database.dart:247` 이하)이 `book_memo_item`/`book_memo`/`book_reflection`을 전부 삭제하며, 사진 조각의 원본 파일(`memo_images/`)도 함께 고아가 된다. 로그아웃 버튼(`lib/features/profile/screens/profile_tab_placeholder.dart:23`)에는 확인 다이얼로그나 경고가 없어, 사용자가 작성한 메모·사진·독후감이 서버에 백업된 적 없이 로그아웃 한 번으로 복구 불가능하게 사라진다.
- [중간][문서] 이전 리뷰(`docs/review/20260817-171413-initial-record-sync-review.md`)에서 지적된 `docs/file-index.md` 누락이 이번에도 재발했다. `record_sync_dao.dart`, `models/record_sync_payload.dart`는 여전히 인덱스에 없고, 새로 추가한 `book_memo_dao.dart`, `models/book_memo.dart`, `screens/widgets/book_memo_item_sheet.dart`도 등록되지 않았다.
- [낮음][리소스] `BookMemoRepository._resolveImageUrl`(`lib/features/book_memo/data/book_memo_repository.dart:165-182`)는 사진을 고를 때마다 앱 지원 디렉터리에 새 파일을 복사하지만, 기존 사진을 다른 사진으로 교체하거나(`updateItem`) 조각을 삭제해도(`deleteItem`) 이전 파일을 지우지 않는다. 위 로그아웃 삭제 문제와 별개로, 정상적으로 앱을 계속 쓰기만 해도 `memo_images/` 아래 파일이 무기한 누적된다.
- [낮음][미완성] `_MemoRichText`(`lib/features/book_memo/screens/book_memo_detail_screen.dart:546-548`)는 `::hl[[...]]` 마크업을 하이라이트로 렌더링하지만, 이 마크업을 생성하는 입력 UI나 서버 응답이 저장소 어디에도 없어 현재는 도달 불가능한 렌더링 분기다.

## 개선 제안
- 문제 → 개선 방법: 6개 파일의 선택 보더 조건(`selected ? 강조색 : 기본색/투명`)을 복원하거나, `accentFill`/`accentSurface`가 배경과 최소 3:1 대비를 갖도록 색을 조정한다. `icon_option_selector.dart`의 주석도 실제 동작에 맞춘다.
- 문제 → 개선 방법: 메모·독후감 데이터를 로그아웃 시 삭제 대상에서 제외해 계정별로 보존하거나, 최소한 로그아웃 전에 "저장되지 않은 메모가 삭제됩니다" 같은 `AppConfirm` 경고를 추가한다. 장기적으로는 메모/독후감도 서버 동기화 대상에 포함하는 것을 검토한다.
- 문제 → 개선 방법: `docs/file-index.md`의 `features/record_sync`, `features/book_memo` 섹션에 누락된 5개 파일 항목을 추가한다.
- 문제 → 개선 방법: `updateItem`/`deleteItem`에서 교체·삭제되는 이전 `image_url` 로컬 파일을 함께 삭제한다.
- 문제 → 개선 방법: `::hl[[...]]` 하이라이트 마크업은 작성 UI를 함께 추가하거나, 사용처가 없다면 렌더링 분기를 제거한다.
