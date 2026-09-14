import 'package:flutter/material.dart';

/// 앱 전역 색상 토큰. 새로운 색상은 반드시 여기에서만 추가/관리한다.
///
/// "북숲" 컨셉에 맞춘 **햇빛 드는 밝은 숲** 팔레트다.
/// `docs/porting-reference/design-system.md`는 웹 원본의 블루 팔레트를 기록한
/// 문서이며, 앱은 의도적으로 그린 계열로 분기했다. 문서의 hex 값을 그대로
/// 되돌리지 말 것(역할 매핑만 참고).
///
/// 토큰은 "역할" 단위로만 나눈다. 비슷한 톤을 상황별로 쪼개지 않고,
/// 아래 목록으로 모든 화면을 커버한다.
class AppColors {
  const AppColors._();

  static AppPalette of(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>();
    assert(palette != null, 'AppPalette가 없는 Theme에서 AppColors.of를 호출했습니다.');
    return palette ?? AppPalette.light;
  }

  /// 저장된 리치 텍스트 색상은 바꾸지 않고 표시할 때만 대비를 보정한다.
  static final _readableTextCache = <(int, int), Color>{};

  static Color readableText(Color foreground, Color background) {
    final key = (foreground.toARGB32(), background.toARGB32());
    final cached = _readableTextCache[key];
    if (cached != null) return cached;

    double contrast(Color color) {
      final a = Color.alphaBlend(color, background).computeLuminance();
      final b = background.computeLuminance();
      return a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
    }

    if (contrast(foreground) >= 4.5) {
      _readableTextCache[key] = foreground;
      return foreground;
    }
    final target = contrast(Colors.white) > contrast(Colors.black)
        ? Colors.white
        : Colors.black;
    var low = 0.0;
    var high = 1.0;
    for (var step = 0; step < 7; step++) {
      final middle = (low + high) / 2;
      final candidate = Color.lerp(foreground, target, middle)!;
      if (contrast(candidate) >= 4.5) {
        high = middle;
      } else {
        low = middle;
      }
    }
    final adjusted = Color.lerp(foreground, target, high)!;
    _readableTextCache[key] = adjusted;
    return adjusted;
  }

  // --- 브랜드: 숲 ---
  /// 버튼·선택 칩·활성 탭 등 넓은 영역을 채우는 부드러운 라임 강조색.
  /// 이 색 위의 글씨·아이콘은 [textStrong]을 사용한다.
  static const accentFill = Color(0xFFCADB7A);

  /// 밝은 표면 위에서 읽혀야 하는 브랜드 텍스트·아이콘·보더·포커스 색.
  static const accentForeground = Color(0xFF556B3B);

  /// 별점처럼 텍스트 없이 색 자체로 구분하는 브랜드 그래픽 강조색.
  static const accentGraphic = Color(0xFF789A3F);

  /// 뱃지·아바타·선택 카드 배경에 사용하는 옅은 브랜드 표면색.
  static const accentSurface = Color(0xFFE7EFD0);

  /// 독서 진행률 숫자·슬라이더·진행 바의 활성 구간 전용 색.
  static const progressFill = Color(0xFF627D3E);

  // --- 브랜드: 햇살 ---
  /// 나뭇잎 사이 햇살. 별점/걸작 표시/주의 아이콘 공용.
  static const highlightGold = Color(0xFFF5C518);

  /// 옅은 햇살 배경. 주의 안내/걸작 강조 배경.
  static const highlightGoldSurface = Color(0xFFFEF3C7);

  // --- 메모 타입 ---
  /// 요약 메모: 차분한 파란색.
  static const memoSummaryForeground = Color(0xFF245F8F);
  static const memoSummarySurface = Color(0xFFDCEEFF);

  /// 발췌 메모: 문장을 구분하기 위한 보라색.
  static const memoQuoteForeground = Color(0xFF7250A5);
  static const memoQuoteSurface = Color(0xFFEFE7FA);

  /// 생각 메모: 아이디어를 연상시키는 호박색.
  static const memoThoughtForeground = Color(0xFF96600B);
  static const memoThoughtSurface = Color(0xFFFFF0C9);

  /// 사진 메모: 이미지 콘텐츠를 구분하는 로즈색.
  static const memoPhotoForeground = Color(0xFFA34062);
  static const memoPhotoSurface = Color(0xFFFBE2EB);

  // --- 독후감 리치 텍스트 에디터 팔레트 ---
  static const reflectionTextBlue = Color(0xFF0061A3);
  static const reflectionTextSky = Color(0xFF0EA5E9);
  static const reflectionTextGreen = Color(0xFF16A34A);
  static const reflectionTextOrange = Color(0xFFEA580C);
  static const reflectionTextRed = Color(0xFFE03C3C);
  static const reflectionTextGray = Color(0xFF94A3B8);
  static const reflectionHighlightYellow = Color(0xFFFEF08A);
  static const reflectionHighlightOrange = Color(0xFFFED7AA);
  static const reflectionHighlightPink = Color(0xFFFECDD3);
  static const reflectionHighlightSky = Color(0xFFBAE6FD);
  static const reflectionHighlightGreen = Color(0xFFBBF7D0);
  static const reflectionHighlightPurple = Color(0xFFE9D5FF);
  static const reflectionQuoteText = Color(0xFF64748B);

  // --- 토론 선택지(Poll) ---
  /// 토론 선택지를 순서대로 구분하는 고정 팔레트. 1~5번째 선택지가 차례로
  /// 배정되고, 마지막 [pollGray]는 자동 제공되는 "기타" 전용이다.
  /// 웹 원본(`--color-poll-*`)이 메모/에디터 토큰을 `color-mix`로 섞어 만든
  /// 값이라, 같은 공식을 이 팔레트의 대응 토큰에 그대로 적용했다.
  /// (예: [pollBlue] = [memoSummaryForeground] 55% + [reflectionTextSky] 45%)
  static const pollBlue = Color(0xFF1A7FB8);
  static const pollPurple = memoQuoteForeground;
  static const pollGreen = Color(0xFF38A046);
  static const pollAmber = Color(0xFFBC5C0B);
  static const pollPink = Color(0xFFB53F57);
  static const pollGray = reflectionTextGray;

  // --- 텍스트 ---
  /// 제목·강조 텍스트.
  static const textStrong = Color(0xFF27311F);

  /// 본문 텍스트.
  static const textBody = Color(0xFF454F3E);

  /// 메타 정보·설명·placeholder. [surfaceSubtle] 위에서도 4.5:1을 넘도록
  /// 조정된 값이다.
  static const textMuted = Color(0xFF626E5B);

  /// 비활성/off 상태 전용(비활성 탭 아이콘, 선택 안 된 토글 등).
  /// 읽기용 텍스트에는 쓰지 않는다.
  static const controlInactive = Color(0xFF7E8976);

  // --- 표면 ---
  /// 화면 전체 배경. 거의 흰색에 가깝지만 [accentFill]과 같은 라임 계열로
  /// 아주 옅게 물들어 있다("보일듯 말듯").
  static const pageBackground = Color(0xFFFBFCF6);

  /// 카드·모달·시트 배경.
  static const surface = Color(0xFFFFFFFF);

  /// 입력창·비활성 필·보조 버튼 배경.
  static const surfaceSubtle = Color(0xFFF1F5E9);

  /// 카메라·이미지처럼 화면 비율 차이로 생기는 미디어 바깥 여백.
  static const mediaBackdrop = Color(0xFF000000);

  /// 카메라·전체 화면 이미지 위에 쓰는 모드와 무관한 전경색.
  static const mediaForeground = Color(0xFFFFFFFF);

  /// 서버 카테고리 색이 없을 때 사용하는 모드와 무관한 중립 회색.
  static const categoryFallback = Color(0xFF94A3B8);

  /// 보더·구분선·진행률 트랙.
  static const border = Color(0xFFDDE5D2);

  // --- 상태 ---
  /// 오류·삭제·좋아요(하트) 등 경고성 강조.
  static const error = Color(0xFFC34A45);

  // --- 그림자 ---
  /// 카드/시트 기본 그림자.
  static const shadowSoft = Color(0x1427311F);

  /// 떠 있는 요소(플로팅 버튼 등) 강한 그림자.
  static const shadowStrong = Color(0x3327311F);
}

/// 외부 서비스 브랜드 고정 색상. 가이드라인상 임의 변경 불가이므로
/// 앱 팔레트와 분리해 둔다.
class AppBrandColors {
  const AppBrandColors._();

  static const kakao = Color(0xFFFEE500);
  // 카카오 로그인 디자인 가이드: 레이블 #000000 85%.
  static const kakaoLabel = Color(0xD9000000);
  static const naver = Color(0xFF03C75A);
  static const google = Color(0xFF4285F4);

  // Google 로그인 브랜딩 가이드(Light 스타일) 고정 색상.
  static const googleBorder = Color(0xFF747775);
  static const googleLabel = Color(0xFF1F1F1F);
}

ThemeData buildAppTheme({Brightness brightness = Brightness.light}) {
  final colors = brightness == Brightness.dark
      ? AppPalette.dark
      : AppPalette.light;
  final colorScheme = ColorScheme.fromSeed(
    brightness: brightness,
    seedColor: colors.accentFill,
    primary: colors.accentForeground,
    onPrimary: colors.pageBackground,
    error: colors.error,
    onError: brightness == Brightness.dark
        ? colors.pageBackground
        : Colors.white,
    surface: colors.surface,
    onSurface: colors.textStrong,
    onSurfaceVariant: colors.textMuted,
    surfaceContainerLowest: colors.pageBackground,
    surfaceContainerLow: colors.surface,
    surfaceContainer: colors.surface,
    surfaceContainerHigh: colors.surfaceSubtle,
    surfaceContainerHighest: colors.surfaceSubtle,
    primaryContainer: colors.accentSurface,
    onPrimaryContainer: colors.accentForeground,
    secondary: colors.accentForeground,
    onSecondary: colors.pageBackground,
    secondaryContainer: colors.accentFill,
    onSecondaryContainer: colors.textStrong,
    outline: colors.border,
    outlineVariant: colors.border,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    extensions: [colors],
    colorScheme: colorScheme,
    scaffoldBackgroundColor: colors.pageBackground,
    // 전역 fontFamily를 따로 지정하지 않는다. `useMaterial3`인 `ThemeData`는
    // `defaultTargetPlatform`에 맞춰 `Typography.material2021`을 구성하는데,
    // iOS에서는 이미 본문에 `CupertinoSystemText`, 큰 제목에
    // `CupertinoSystemDisplay`라는 공식 프록시 패밀리명을 스타일별로 따로
    // 적용해 San Francisco를 그대로 쓴다(`typography.dart`). 여기서
    // fontFamily를 하나로 덮어쓰면 이 스타일별 구분(Display/Text)이 사라지고
    // 비공식 패밀리명이라 OS 버전에 따라 폴백될 위험도 있다.
    // titleTextStyle을 여기 넣으면 화면별 foregroundColor 상속이 끊긴다.
    // toolbarHeight는 기본값(kToolbarHeight=56)을 그대로 쓴다.
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: colors.pageBackground,
      foregroundColor: colors.textStrong,
      surfaceTintColor: Colors.transparent,
    ),
    dividerColor: colors.border,
    dialogTheme: DialogThemeData(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: Colors.transparent,
      modalBackgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      dragHandleColor: colors.border,
      dragHandleSize: Size(36, 4),
    ),
    // 기본 M3 bodyLarge(16px)는 TextField 입력 글씨로 쓰기엔 커 보여서(design-system.md
    // 본문 14~15px 기준) 앱 전역 입력창 글씨 크기를 낮춘다.
    textTheme: TextTheme(
      bodyLarge: TextStyle(fontSize: 14, color: colors.textBody),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: colors.accentFill,
        foregroundColor: colors.textStrong,
        minimumSize: Size.fromHeight(48),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.textBody,
        minimumSize: Size.fromHeight(48),
        side: BorderSide(color: colors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),
    ),
    // design-system.md: "텍스트 입력/검색창: 보더 없이 필 배경 + rounded-xl
    // outline-none" — 밑줄(UnderlineInputBorder) 대신 보더 없는 필 배경으로 통일.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceSubtle,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: TextStyle(color: colors.textMuted),
      labelStyle: TextStyle(color: colors.textMuted, fontSize: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.accentForeground, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.error, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.error, width: 1.5),
      ),
    ),
  );
}

/// Theme에 연결된 역할별 색상. 화면은 AppColors.of(context)로 구독한다.
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.accentFill,
    required this.accentForeground,
    required this.accentGraphic,
    required this.accentSurface,
    required this.progressFill,
    required this.highlightGoldSurface,
    required this.memoSummaryForeground,
    required this.memoSummarySurface,
    required this.memoQuoteForeground,
    required this.memoQuoteSurface,
    required this.memoThoughtForeground,
    required this.memoThoughtSurface,
    required this.memoPhotoForeground,
    required this.memoPhotoSurface,
    required this.textStrong,
    required this.textBody,
    required this.textMuted,
    required this.controlInactive,
    required this.pageBackground,
    required this.surface,
    required this.surfaceSubtle,
    required this.border,
    required this.error,
    required this.shadowSoft,
    required this.shadowStrong,
    required this.reflectionQuoteText,
  });
  final Color accentFill;
  final Color accentForeground;
  final Color accentGraphic;
  final Color accentSurface;
  final Color progressFill;
  final Color highlightGoldSurface;
  final Color memoSummaryForeground;
  final Color memoSummarySurface;
  final Color memoQuoteForeground;
  final Color memoQuoteSurface;
  final Color memoThoughtForeground;
  final Color memoThoughtSurface;
  final Color memoPhotoForeground;
  final Color memoPhotoSurface;
  final Color textStrong;
  final Color textBody;
  final Color textMuted;
  final Color controlInactive;
  final Color pageBackground;
  final Color surface;
  final Color surfaceSubtle;
  final Color border;
  final Color error;
  final Color shadowSoft;
  final Color shadowStrong;
  final Color reflectionQuoteText;
  static const light = AppPalette(
    accentFill: AppColors.accentFill,
    accentForeground: AppColors.accentForeground,
    accentGraphic: AppColors.accentGraphic,
    accentSurface: AppColors.accentSurface,
    progressFill: AppColors.progressFill,
    highlightGoldSurface: AppColors.highlightGoldSurface,
    memoSummaryForeground: AppColors.memoSummaryForeground,
    memoSummarySurface: AppColors.memoSummarySurface,
    memoQuoteForeground: AppColors.memoQuoteForeground,
    memoQuoteSurface: AppColors.memoQuoteSurface,
    memoThoughtForeground: AppColors.memoThoughtForeground,
    memoThoughtSurface: AppColors.memoThoughtSurface,
    memoPhotoForeground: AppColors.memoPhotoForeground,
    memoPhotoSurface: AppColors.memoPhotoSurface,
    textStrong: AppColors.textStrong,
    textBody: AppColors.textBody,
    textMuted: AppColors.textMuted,
    controlInactive: AppColors.controlInactive,
    pageBackground: AppColors.pageBackground,
    surface: AppColors.surface,
    surfaceSubtle: AppColors.surfaceSubtle,
    border: AppColors.border,
    error: AppColors.error,
    shadowSoft: AppColors.shadowSoft,
    shadowStrong: AppColors.shadowStrong,
    reflectionQuoteText: AppColors.reflectionQuoteText,
  );
  // 다크 모드는 무채색에 가까운 검정 표면에 브랜드 강조색만 남긴다.
  static const dark = AppPalette(
    // 선택된 책장 상태·주요 버튼은 검정 표면에서 구분되는 짙은 숲색을 쓴다.
    accentFill: Color(0xFF40552D),
    accentForeground: Color(0xFFC4D98C),
    accentGraphic: Color(0xFFB1CC76),
    accentSurface: Color(0xFF252525),
    progressFill: Color(0xFFB1CC76),
    highlightGoldSurface: Color(0xFF443B1F),
    memoSummaryForeground: Color(0xFF9CCCF2),
    memoSummarySurface: Color(0xFF223849),
    memoQuoteForeground: Color(0xFFCEB4F2),
    memoQuoteSurface: Color(0xFF382D46),
    memoThoughtForeground: Color(0xFFEAC17A),
    memoThoughtSurface: Color(0xFF443820),
    memoPhotoForeground: Color(0xFFEFB0C5),
    memoPhotoSurface: Color(0xFF452D38),
    textStrong: Color(0xFFF0F0F0),
    textBody: Color(0xFFD4D4D4),
    textMuted: Color(0xFFB0B0B0),
    controlInactive: Color(0xFF909090),
    pageBackground: Color(0xFF101010),
    surface: Color(0xFF1A1A1A),
    surfaceSubtle: Color(0xFF242424),
    border: Color(0xFF3A3A3A),
    error: Color(0xFFF2948C),
    shadowSoft: Color(0x33000000),
    shadowStrong: Color(0x66000000),
    reflectionQuoteText: Color(0xFFB0B0B0),
  );
  @override
  AppPalette copyWith({
    Color? accentFill,
    Color? accentForeground,
    Color? accentGraphic,
    Color? accentSurface,
    Color? progressFill,
    Color? highlightGoldSurface,
    Color? memoSummaryForeground,
    Color? memoSummarySurface,
    Color? memoQuoteForeground,
    Color? memoQuoteSurface,
    Color? memoThoughtForeground,
    Color? memoThoughtSurface,
    Color? memoPhotoForeground,
    Color? memoPhotoSurface,
    Color? textStrong,
    Color? textBody,
    Color? textMuted,
    Color? controlInactive,
    Color? pageBackground,
    Color? surface,
    Color? surfaceSubtle,
    Color? border,
    Color? error,
    Color? shadowSoft,
    Color? shadowStrong,
    Color? reflectionQuoteText,
  }) => AppPalette(
    accentFill: accentFill ?? this.accentFill,
    accentForeground: accentForeground ?? this.accentForeground,
    accentGraphic: accentGraphic ?? this.accentGraphic,
    accentSurface: accentSurface ?? this.accentSurface,
    progressFill: progressFill ?? this.progressFill,
    highlightGoldSurface: highlightGoldSurface ?? this.highlightGoldSurface,
    memoSummaryForeground: memoSummaryForeground ?? this.memoSummaryForeground,
    memoSummarySurface: memoSummarySurface ?? this.memoSummarySurface,
    memoQuoteForeground: memoQuoteForeground ?? this.memoQuoteForeground,
    memoQuoteSurface: memoQuoteSurface ?? this.memoQuoteSurface,
    memoThoughtForeground: memoThoughtForeground ?? this.memoThoughtForeground,
    memoThoughtSurface: memoThoughtSurface ?? this.memoThoughtSurface,
    memoPhotoForeground: memoPhotoForeground ?? this.memoPhotoForeground,
    memoPhotoSurface: memoPhotoSurface ?? this.memoPhotoSurface,
    textStrong: textStrong ?? this.textStrong,
    textBody: textBody ?? this.textBody,
    textMuted: textMuted ?? this.textMuted,
    controlInactive: controlInactive ?? this.controlInactive,
    pageBackground: pageBackground ?? this.pageBackground,
    surface: surface ?? this.surface,
    surfaceSubtle: surfaceSubtle ?? this.surfaceSubtle,
    border: border ?? this.border,
    error: error ?? this.error,
    shadowSoft: shadowSoft ?? this.shadowSoft,
    shadowStrong: shadowStrong ?? this.shadowStrong,
    reflectionQuoteText: reflectionQuoteText ?? this.reflectionQuoteText,
  );
  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    return AppPalette(
      accentFill: Color.lerp(accentFill, other.accentFill, t)!,
      accentForeground: Color.lerp(
        accentForeground,
        other.accentForeground,
        t,
      )!,
      accentGraphic: Color.lerp(accentGraphic, other.accentGraphic, t)!,
      accentSurface: Color.lerp(accentSurface, other.accentSurface, t)!,
      progressFill: Color.lerp(progressFill, other.progressFill, t)!,
      highlightGoldSurface: Color.lerp(
        highlightGoldSurface,
        other.highlightGoldSurface,
        t,
      )!,
      memoSummaryForeground: Color.lerp(
        memoSummaryForeground,
        other.memoSummaryForeground,
        t,
      )!,
      memoSummarySurface: Color.lerp(
        memoSummarySurface,
        other.memoSummarySurface,
        t,
      )!,
      memoQuoteForeground: Color.lerp(
        memoQuoteForeground,
        other.memoQuoteForeground,
        t,
      )!,
      memoQuoteSurface: Color.lerp(
        memoQuoteSurface,
        other.memoQuoteSurface,
        t,
      )!,
      memoThoughtForeground: Color.lerp(
        memoThoughtForeground,
        other.memoThoughtForeground,
        t,
      )!,
      memoThoughtSurface: Color.lerp(
        memoThoughtSurface,
        other.memoThoughtSurface,
        t,
      )!,
      memoPhotoForeground: Color.lerp(
        memoPhotoForeground,
        other.memoPhotoForeground,
        t,
      )!,
      memoPhotoSurface: Color.lerp(
        memoPhotoSurface,
        other.memoPhotoSurface,
        t,
      )!,
      textStrong: Color.lerp(textStrong, other.textStrong, t)!,
      textBody: Color.lerp(textBody, other.textBody, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      controlInactive: Color.lerp(controlInactive, other.controlInactive, t)!,
      pageBackground: Color.lerp(pageBackground, other.pageBackground, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceSubtle: Color.lerp(surfaceSubtle, other.surfaceSubtle, t)!,
      border: Color.lerp(border, other.border, t)!,
      error: Color.lerp(error, other.error, t)!,
      shadowSoft: Color.lerp(shadowSoft, other.shadowSoft, t)!,
      shadowStrong: Color.lerp(shadowStrong, other.shadowStrong, t)!,
      reflectionQuoteText: Color.lerp(
        reflectionQuoteText,
        other.reflectionQuoteText,
        t,
      )!,
    );
  }
}
