# 리뷰 결과

## 요약
- 날짜 선택 바텀시트는 정적 분석을 통과했지만, 날짜 삭제가 서버에 보존되지 않는 상태 정합성 오류와 오늘 날짜 선택·스크린 리더 안내 문제가 있다.

## 문제점
- [데이터 정합성][높음] `lib/features/book_record/screens/book_record_screen.dart:452`는 "선택 해제" 결과를 빈 문자열로 전달하지만, `lib/features/bookshelf/models/book_item.dart:154`~`:157`에서 즉시 `null`로 변환한다. 이후 dirty push는 `lib/features/bookshelf/data/bookshelf_repository.dart:192`~`:193`에서 이 `null`을 그대로 전달하고, `lib/features/book_record/data/book_record_api.dart:73`~`:74`는 null인 날짜 필드를 요청 본문에서 생략한다. 따라서 서버의 기존 시작일·완독일은 삭제되지 않고, push 응답이 확정 반영되면 화면에서 잠시 지워졌던 날짜도 기존 값으로 돌아온다.
- [입력 동작][중간] `lib/features/book_record/screens/widgets/meta_dialogs.dart:469`는 날짜가 미설정이어도 `lastDate`인 오늘을 선택값으로 넣는다. `calendar_date_picker2`의 `allowSameValueSelection` 기본값에서는 현재 선택값을 다시 탭해도 `onValueChanged`가 호출되지 않으므로, 날짜가 없는 사용자는 달력을 처음 열어 오늘을 탭해도 `:470`의 닫기·저장 흐름으로 진입할 수 없다.
- [접근성][중간] `lib/features/book_record/screens/widgets/meta_dialogs.dart:437`~`:444`는 화면에 보이는 요일과 월·년 텍스트만 한글로 바꾸고, 앱은 한국어 `MaterialLocalizations`를 제공하지 않는다. `calendar_date_picker2`는 각 날짜와 월 이동을 `MaterialLocalizations.formatFullDate()`·`formatMonthYear()`로 스크린 리더에 전달하므로, 한국어 UI에서 날짜가 영어로 안내된다. 모드 선택 의미도 별도 `semanticsDictionary`가 없어 패키지 기본 라벨에 의존한다.

## 개선 제안
- 날짜 삭제 의도가 dirty 스냅샷에서 사라짐 → 로컬 레코드와 별도로 변경 필드 또는 `pendingClearStartedAt`/`pendingClearFinishedAt` 같은 삭제 의도를 저장하고, 재시도 시 해당 필드에 빈 문자열을 전송한다. 단순히 모든 null 날짜를 빈 문자열로 바꾸면 수정하지 않은 null 필드까지 삭제 요청이 되므로 변경 필드 단위로 구분해야 한다.
- 미설정 날짜에 오늘을 미리 선택해 콜백이 발생하지 않음 → `initialDate`가 null이면 `value`를 빈 목록으로 전달하고 표시 월만 오늘로 맞추거나, 동일 값 탭도 저장 동작이어야 한다면 `allowSameValueSelection: true`를 명시한다.
- 달력의 시각 언어와 스크린 리더 언어가 다름 → `flutter_localizations`와 한국어 `MaterialLocalizations`를 연결해 날짜 의미 정보를 한국어로 제공하고, `CalendarDatePicker2SemanticsLabel.selectMonth`·`selectYear`도 `semanticsDictionary`로 명시한다.
