# 리뷰 결과

대상: 워킹 트리 변경(다크 테마 도입) — 98개 파일 수정 + `lib/core/theme/theme_mode_provider.dart` 신규
`flutter analyze` 결과: `No issues found!`

## 요약

- `ThemeExtension` 기반 `AppPalette`로 색상을 역할 토큰화하고 98개 화면을 `AppColors.of(context)`로 옮긴 구조 선택은 타당하며 테마 저장·복원(`theme_mode_provider.dart`)도 순서·롤백 처리가 견고하다. 다만 (1) 다크에서 명도가 뒤집힌 토큰을 배경으로 쓰는 자리 1건이 실제 가독성 불량이고, (2) 독후감 편집기/리더에서 `const` 싱글턴이던 Quill 스타일이 매 build 재생성으로 바뀐 성능 퇴행이 있으며, (3) 팔레트 전환에서 빠진 파일과 새 루트 `AnnotatedRegion`의 부작용을 정리해야 한다.

## 문제점

### 1. [문제] 표지 없는 책 카드가 다크 모드에서 사실상 읽히지 않는다

`lib/features/bookshelf/screens/widgets/book_cover.dart:110-137`

```dart
decoration: BoxDecoration(
  // 흰 제목 텍스트가 얹히므로 accentFill(옅은 라임) 대신 어두운 숲 톤
  // 하나로 채운다 — primary를 쓰면 밝은 쪽 절반에서 글자가 안 보인다.
  color: AppColors.of(context).accentForeground,   // 라이트 #556B3B / 다크 #C4D98C
),
...
style: const TextStyle(color: Colors.white, ...),
```

주석이 명시한 전제("accentForeground = 어두운 숲 톤")가 다크 팔레트에서 깨졌다. 다크의 `accentForeground`는 밝은 라임(`#C4D98C`, 상대 휘도 약 0.63)이라 흰 글씨와의 대비가 **약 1.5:1**로, WCAG AA(4.5:1)는 물론 최소 가독선에도 못 미친다. 표지 이미지가 없는 책마다 책장 그리드 전체에 노출되는 자리다.

`accentForeground`는 이름이 "foreground"인데 여기서만 배경으로 쓰이고 있어, 팔레트가 라이트/다크로 명도를 뒤집는 순간 깨질 수밖에 없는 사용이었다.

### 2. [문제] Quill `DefaultStyles`·`QuillEditorConfig`의 const가 깨져 편집기가 매 리빌드마다 스타일 트리를 새로 만든다

- `lib/features/book_reflection/screens/book_reflection_editor_screen.dart:36,42` — `const _reflectionBodyTextStyle` / `const bookReflectionQuillStyles` → `…(BuildContext context) =>` 함수
- `lib/features/public_reflection/screens/public_reflection_reader_screen.dart:18,26` — 동일 패턴
- 호출부: `book_reflection_editor_screen.dart:690`, `book_reflection_detail_screen.dart:405`, `public_reflection_reader_screen.dart:249` (`config: const QuillEditorConfig(...)` → `QuillEditorConfig(...)`)

`DefaultStyles`는 h1~h6·인용·목록·코드블록까지 수십 개의 `DefaultTextBlockStyle`을 품은 큰 객체이고, flutter_quill은 `==`를 재정의하지 않아 동일성 비교로 변경을 판단한다. 이제 build마다 새 인스턴스가 들어가므로 **항상 "스타일이 바뀌었다"로 취급**된다. 특히 편집기는 키 입력·선택 변경마다 리빌드되므로, 긴 독후감에서 타이핑 지연으로 드러날 수 있는 자리다.

### 3. [문제] `AppColors.readableText`가 span 하나당 `computeLuminance()`를 최대 46회 호출한다

`lib/core/theme/app_theme.dart:19-36`, 호출부 `lib/features/book_reflection/screens/book_reflection_editor_screen.dart:129-142`

```dart
if (contrast(foreground) >= 4.5) return foreground;        // luminance 2회
final target = contrast(Colors.white) > contrast(Colors.black) ? ... ;  // 4회
for (var step = 1; step <= 20; step++) { ... contrast(candidate) ... }  // 최대 40회
```

`contrast()` 한 번이 `computeLuminance()` 2회(= `pow()` 6회)다. 색이 지정된 span에서는 최악 46회, 즉 `pow()` 138회가 **span 하나마다, build마다** 돈다. `reflectionTextSpanBuilder`는 편집기·상세·공개 리더 세 화면이 공유하므로(따라서 "편집 중에만 보정된다"는 불일치는 없다) 문단이 많은 글에서 스크롤·타이핑 시 누적된다. 캐시가 없다.

부수적으로 두 가지가 더 걸린다.

- 보정이 `brightness == Brightness.dark`에서만 걸려, 다크에서 지정한 밝은 색이 라이트 모드에서는 보정 없이 흰 배경에 그대로 나온다. 저장 색을 바꾸지 않는 표시 시점 보정이라면 두 방향 모두 필요하다.
- 배경을 `colors.pageBackground`로 가정하는데, 실제 에디터/리더 본문은 카드 표면 위에 놓일 수 있어 계산 기준과 실제 배경이 어긋난다.

### 4. [문제] 새 루트 `AnnotatedRegion`이 전체화면 검정 화면의 상태바 아이콘을 뒤집는다

`lib/app/app.dart:22-38`에서 `MaterialApp.builder`에 앱 전역 `AnnotatedRegion<SystemUiOverlayStyle>`을 추가하고, 아이콘 밝기를 `Theme.of(context).brightness`로만 결정한다. AppBar가 있는 화면은 AppBar가 더 깊은 곳에서 자체 오버레이 스타일을 발행하므로 문제없다. 하지만 아래 두 화면은 **AppBar 없이** 검정 배경만 깐다.

- `lib/shared/image/screens/shared_camera_screen.dart:417-418` — `Scaffold(backgroundColor: AppColors.mediaBackdrop)`
- `lib/shared/image/widgets/shared_image_viewer.dart:50-52` — `mediaBackdrop` 배경

두 파일 모두 `SystemUiOverlayStyle`을 직접 지정하지 않는다. 결과적으로 **라이트 모드에서 검정 화면 위에 어두운 상태바 아이콘**을 요청하게 된다(다크 모드에서는 우연히 맞다).

변경 전에도 이 조합이 늘 정상이었던 건 아니다. 애노테이션이 어디에도 없으면 Flutter는 마지막으로 설정된 오버레이 스타일을 유지하므로, 일반 AppBar 화면에서 넘어오면 이미 어두운 아이콘이 남아 있었다. 이번 변경이 바꾼 것은 **직전 라우트에 따라 달라지던 것이 라이트 모드에서 항상 어긋나도록 확정됐다**는 점이다. 어느 쪽이든 이 화면들은 자기 오버레이 스타일을 선언해야 한다.

### 5. [문제] 팔레트 전환에서 빠진 파일이 남아 있다

수정 대상 98개 밖에서 색을 쓰는 파일:

| 파일 | 상태 |
| --- | --- |
| `lib/shared/widgets/app_snackbar.dart:227-235` | 루트 Overlay는 `MaterialApp`의 `AnimatedTheme` 아래에 있어 테마 접근이 **가능한데도** 라이트 상수 사용 |
| `lib/shared/image/screens/shared_camera_screen.dart` | 검정 배경 전용 — 의도로 보이나 `AppColors.surface`를 "흰색"의 뜻으로 사용 |
| `lib/shared/image/widgets/shared_image_viewer.dart` | 위와 동일 |
| `lib/features/book_note/screens/widgets/memo_ocr_capture.dart` | 위와 동일 |
| `lib/features/profile/models/reading_stats_summary.dart:32` | 잘못된 카테고리 색 폴백으로 라이트 `AppColors.border` 반환 |

`app_snackbar`는 실제 대비는 양호하다(라이트 `accentForeground` `#556B3B` 88% 합성 위 흰 글씨 ≈ 7:1). 문제는 결과가 아니라 **커버리지 구멍**이다. 다크 팔레트의 스낵바 색이 정의되지 않은 채 라이트 값이 두 모드에 쓰이고 있어, 팔레트를 손대면 조용히 어긋난다.

카메라/뷰어/OCR 3종은 항상 검정 배경이라 고정색이 맞다. 다만 `AppColors.surface`(= 라이트 흰색)를 "전경 흰색"이라는 의미로 쓰고 있어, 팔레트 값이 바뀌면 의도가 소리 없이 깨진다.

### 6. [문제] `AppColors.of(context)`가 조용히 라이트로 폴백한다

`lib/core/theme/app_theme.dart:15-16`

```dart
static AppPalette of(BuildContext context) =>
    Theme.of(context).extension<AppPalette>() ?? AppPalette.light;
```

98개 파일을 일괄 전환한 변경에서, Theme 밖 context를 잘못 넘긴 자리는 **에러 없이 라이트 팔레트로 렌더**된다. 다크 모드에서 한 위젯만 흰 배경으로 뜨는 형태로 드러나 원인 추적이 어렵다.

### 7. [문제] `CommunityMenuTile`의 파괴적 액션 판정이 색상 동등 비교다

`lib/shared/widgets/community_content.dart:561-584`

```dart
this.color,                                       // 기본값 제거, nullable
final Color? color;
...
destructive: color == AppColors.of(context).error,
```

`color`는 오직 이 비교를 위해서만 존재하고 실제 렌더에는 쓰이지 않는다. 호출부 3곳(`discussion_detail_screen.dart:668`, `discussion_answer_item.dart:202`, `review_item.dart:59`)이 모두 같은 context의 `AppColors.of(context).error`를 넘기고 있어 지금은 동작하지만, 다른 context나 `withValues()`가 섞인 색을 넘기는 순간 파괴적 스타일이 조용히 사라진다.

## 개선 제안

### 1. 표지 플레이스홀더 → 배경/전경 쌍을 팔레트에서 함께 가져온다

`accentForeground`를 배경으로 쓰는 것 자체를 걷어낸다. 팔레트에 `coverPlaceholderSurface` / `coverPlaceholderText` 쌍을 추가하고(다크는 짙은 숲 `#40552D` + `textStrong` 같은 조합), `Colors.white` 고정을 제거한다. 최소 수정으로 막으려면 `accentFill`(다크 `#40552D`, 라이트 `#CADB7A`) 배경 + `textStrong` 전경으로 바꿔도 양쪽 모두 AA를 넘긴다.

더 근본적으로는, 이름이 `…Foreground`인 토큰을 배경으로 쓰는 자리가 더 없는지 점검하는 게 좋다(확인 결과 현재는 이 한 곳뿐이며 나머지 `accentForeground` 사용처는 모두 아이콘·텍스트·보더다).

### 2. Quill 스타일 → 라이트/다크 두 개의 최상위 `final` 싱글턴으로 되돌린다

`DefaultStyles`는 팔레트 두 벌만 존재하므로 context마다 만들 이유가 없다.

```dart
final _reflectionQuillStylesLight = DefaultStyles( ... AppPalette.light.textStrong ... );
final _reflectionQuillStylesDark  = DefaultStyles( ... AppPalette.dark.textStrong ... );

DefaultStyles bookReflectionQuillStyles(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? _reflectionQuillStylesDark
        : _reflectionQuillStylesLight;
```

**`const`가 아니라 `final`이어야 한다.** `AppPalette.dark.textStrong`은 const 객체의 인스턴스 필드 읽기라 상수식이 아니고, `const DefaultStyles(...)`로 쓰면 "Invalid constant value" 컴파일 오류가 난다. 색을 원시 16진 리터럴로 다시 적으면 컴파일은 되지만 다크 팔레트가 두 곳에 중복되어, 팔레트를 도입한 이유가 무너진다. 최상위 `final`은 지연 초기화 후 프로세스 수명 동안 같은 인스턴스를 돌려주므로 목적(동일성 안정)에는 `const`와 동등하다.

지적한 결함은 "`const`가 빠졌다"가 아니라 **인스턴스 동일성이 매 build 깨진다**는 것이므로 `final`로 충분하다. 같은 수정이 `_readerQuillStyles`, `_readerBodyTextStyle`, `_reflectionBodyTextStyle`에 그대로 적용된다.

`QuillEditorConfig`도 스타일을 제외한 나머지가 상수이므로, 스타일만 이렇게 분리해 넘기면 재생성 비용이 사라진다.

### 3. `readableText` → 결과 캐시 + 이분 탐색, 그리고 양방향 적용

- `Map<(int fg, int bg), Color>` 정적 캐시를 둔다. 독후감에서 쓰이는 색 조합은 팔레트 수준으로 적고, 한 번 계산하면 재사용된다. 이것만으로 체감 비용이 사실상 0이 된다.
- 루프를 20회 선형 탐색 대신 6~7회 이분 탐색으로 바꾸면 최악 호출도 1/3로 줄어든다.
- `brightness == Brightness.dark` 게이트를 없애고 두 모드 모두에서 보정한다. 라이트에서 이미 대비가 충분한 색은 첫 `if`에서 그대로 반환되므로 동작 변화 없이 다크에서 작성한 색만 교정된다.
- 배경 인자를 `pageBackground` 고정 대신 실제 렌더 표면(`surface` 또는 호출부가 아는 값)으로 넘긴다.

### 4. 검정 전용 화면에 자체 `SystemUiOverlayStyle`을 지정한다

`shared_camera_screen.dart`와 `shared_image_viewer.dart`의 최상위를 `AnnotatedRegion<SystemUiOverlayStyle>(value: SystemUiOverlayStyle.light, child: …)`로 감싼다(`SystemUiOverlayStyle.light` = 밝은 아이콘). `barcode_scan_screen.dart`는 검정 AppBar가 있어 자동으로 해결되지만, 같은 이유로 명시해 두면 의도가 드러난다.

앱 전역 `AnnotatedRegion`에서 `systemNavigationBarColor`를 `pageBackground`로 두는 것 자체는 적절하다.

### 5. 남은 파일 정리

- `app_snackbar.dart` — `_AppSnackBarContent.build`에서 `AppColors.of(context)`로 전환하고, 다크용 스낵바 색을 팔레트에 넣는다. `error` 케이스의 `Color.lerp(..., Colors.black, 0.2)` 보정은 라이트 기준 대비 계산에서 나온 값이므로, 다크 팔레트 `error`(`#F2948C`)에 대해서는 다시 계산해야 한다.
- 카메라/뷰어/OCR — 의도적 고정색임을 코드로 드러낸다. `AppColors.surface`(팔레트 토큰) 대신 `AppColors.mediaBackdrop`처럼 모드 무관 고정 상수(`mediaForeground` 등)를 하나 추가해 그쪽을 참조한다.
- `reading_stats_summary.dart:32` — 폴백을 상수 대신 렌더 시점에 팔레트에서 받도록 바꾸거나, 모드 무관 중립 회색 상수를 별도로 둔다.

### 6. `AppColors.of` 폴백을 디버그에서 드러낸다

```dart
static AppPalette of(BuildContext context) {
  final palette = Theme.of(context).extension<AppPalette>();
  assert(palette != null, 'AppPalette가 없는 Theme에서 AppColors.of를 호출했습니다.');
  return palette ?? AppPalette.light;
}
```

릴리스 동작(라이트 폴백)은 유지하면서 개발 중에만 전환 누락이 즉시 드러난다.

### 7. `CommunityMenuTile` — 색 비교 대신 `destructive` 플래그

`Color? color` 파라미터를 `bool destructive = false`로 바꾸고 호출부 3곳을 `destructive: true`로 고친다. 파라미터가 의미하는 바가 이름에 드러나고, 비교가 사라져 context 의존도 없어진다.

### 8. `ThemeData` 두 벌을 최상위 `final`로 올리고 `AppPalette`에 `==`/`hashCode`를 넣는다

`lib/app/app.dart:21-22`에서 `buildAppTheme()`과 `buildAppTheme(brightness: Brightness.dark)`를 `build()` 안에서 호출하므로, `BBBookApp`이 리빌드될 때마다 `ThemeData` 두 개와 `AppPalette` 두 개가 새로 만들어진다. 게다가 `AppPalette`는 `copyWith`·`lerp`만 있고 `==`/`hashCode`가 없어, `ThemeData.==`가 `extensions`를 비교할 때 동일성 비교로 떨어져 절대 같다고 판정되지 않는다.

**지금 당장 성능 문제로 드러나지는 않는다.** `BBBookApp`은 `themeModeProvider`만 watch하는 `ConsumerWidget`이라 사실상 테마 변경 시에만 리빌드되고, 그때는 새 `ThemeData`와 `AnimatedTheme` 보간이 오히려 의도한 동작이다. 다만 두 줄로 없앨 수 있는 잠재 비용이고, `ThemeExtension`의 계약상 `==`/`hashCode` 구현이 기대되는 부분이므로 함께 정리해 두는 편이 좋다.

```dart
final _lightTheme = buildAppTheme();
final _darkTheme = buildAppTheme(brightness: Brightness.dark);
```

### 9. 불필요하게 사라진 `const` 복구

`analysis_options.yaml`에 `prefer_const_constructors`가 없어 `flutter analyze`가 잡지 못한다(실제로 `No issues found`). 일괄 전환 과정에서 **색이 그대로인데 `const`만 빠진** 자리가 남았는데, 확인된 곳은 `lib/features/profile/screens/widgets/reading_stats_treemap.dart` 4곳이다.

- `:146` `boxShadow: const [...]` → `[...]` (내부 `BoxShadow`가 여전히 전부 상수)
- `:171`, `:181` `style: const TextStyle(...)` → `TextStyle(...)` (`AppColors.surface` 정적 상수 그대로)
- `:268` `const [Shadow(...)]` → `[Shadow(...)]`

이 파일의 툴팁·라벨 색(`AppColors.textStrong`/`surface`)은 **서버가 준 카테고리 색의 휘도로 고르는 값**이라 앱 테마와 무관한 게 맞다(`:251`). 따라서 색은 그대로 두고 `const`만 되돌리면 된다. 나머지 파일의 `const` 제거는 실제로 `of(context)`가 들어가서 불가피했던 것들로 확인했다.

재발 방지로는 `analysis_options.yaml`에 `prefer_const_constructors` / `prefer_const_literals_to_create_immutables`를 켜는 것을 권한다.

## 문제없음으로 확인한 항목

리뷰 중 의심했으나 검증 결과 정상인 것들을 기록해 둔다.

- `ThemeModeController.select` — `_selectionVersion` 가드로 늦게 끝난 저장이 최신 선택을 덮어쓰지 않고, `_pendingSave` 체인으로 연속 선택 순서가 보장되며, 실패 시 롤백이 스낵바보다 먼저 반영된다.
- `main.dart`의 `loadThemeMode()` → `overrideWithValue` — `runApp` 전 동기 주입이라 첫 프레임 테마 깜빡임이 없다.
- `AppLoading` / `AppSnackBar`의 `Overlay.of(context, rootOverlay: true)` — `MaterialApp`은 `AnimatedTheme`을 `Navigator` **위**에 두므로 루트 Overlay도 테마 아래에 있다. `app_loading.dart`의 `AppColors.of(context)` 전환은 정상 동작한다.
- `reflectionTextSpanBuilder` — 편집기·상세·공개 리더 세 화면이 같은 최상위 함수를 공유한다. "편집 중에만 보정되고 읽을 때는 안 된다"는 불일치는 없다.
- `_DottedLeaderPainter.shouldRepaint` — 새로 추가된 `color` 필드를 비교하므로 테마 전환 시 다시 그려진다.
- `docs/file-index.md` — 신규 `theme_mode_provider.dart`가 등록되어 있고 `app_theme.dart`·`profile_settings_screen.dart` 설명도 갱신되었다. 프로젝트 규칙대로다.
- `AppPalette.lerp` — 모든 필드가 구현되어 있어 테마 전환이 끊기지 않고 보간된다.
