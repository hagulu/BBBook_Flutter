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
  static const kakaoLabel = Color(0xFF3C1E1E);
  static const naver = Color(0xFF03C75A);
  static const google = Color(0xFF4285F4);
}

ThemeData buildAppTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.accentFill,
    primary: AppColors.accentFill,
    onPrimary: AppColors.textStrong,
    error: AppColors.error,
    onError: Colors.white,
    surface: AppColors.surface,
    onSurface: AppColors.textStrong,
    outline: AppColors.border,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.pageBackground,
    // 전역 fontFamily를 따로 지정하지 않는다. `useMaterial3`인 `ThemeData`는
    // `defaultTargetPlatform`에 맞춰 `Typography.material2021`을 구성하는데,
    // iOS에서는 이미 본문에 `CupertinoSystemText`, 큰 제목에
    // `CupertinoSystemDisplay`라는 공식 프록시 패밀리명을 스타일별로 따로
    // 적용해 San Francisco를 그대로 쓴다(`typography.dart`). 여기서
    // fontFamily를 하나로 덮어쓰면 이 스타일별 구분(Display/Text)이 사라지고
    // 비공식 패밀리명이라 OS 버전에 따라 폴백될 위험도 있다.
    // titleTextStyle을 여기 넣으면 화면별 foregroundColor 상속이 끊긴다.
    // toolbarHeight는 기본값(kToolbarHeight=56)을 그대로 쓴다.
    appBarTheme: const AppBarTheme(centerTitle: false),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.transparent,
      modalBackgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      dragHandleColor: AppColors.border,
      dragHandleSize: Size(36, 4),
    ),
    // 기본 M3 bodyLarge(16px)는 TextField 입력 글씨로 쓰기엔 커 보여서(design-system.md
    // 본문 14~15px 기준) 앱 전역 입력창 글씨 크기를 낮춘다.
    textTheme: const TextTheme(
      bodyLarge: TextStyle(fontSize: 14, color: AppColors.textBody),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accentFill,
        foregroundColor: AppColors.textStrong,
        minimumSize: const Size.fromHeight(48),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textBody,
        minimumSize: const Size.fromHeight(48),
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),
    ),
    // design-system.md: "텍스트 입력/검색창: 보더 없이 필 배경 + rounded-xl
    // outline-none" — 밑줄(UnderlineInputBorder) 대신 보더 없는 필 배경으로 통일.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceSubtle,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: const TextStyle(color: AppColors.textMuted),
      labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
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
        borderSide: const BorderSide(
          color: AppColors.accentForeground,
          width: 1.5,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.error, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
    ),
  );
}
