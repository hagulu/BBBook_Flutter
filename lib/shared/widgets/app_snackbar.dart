import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../core/theme/app_theme.dart';

/// 공통 SnackBar 종류(성공/정보/에러).
enum AppSnackBarType { success, info, error }

/// 공통 SnackBar(pill 형태, 아이덴티티 컬러 반투명 배경 + 상태 아이콘).
///
/// 화면별 커스텀 SnackBar 대신 항상 이 컴포넌트를 사용한다.
///
/// `ScaffoldMessenger`가 아니라 앱의 루트 [Overlay]에 직접 [OverlayEntry]를
/// 꽂아서 그린다(`app_loading.dart`의 `AppLoading`과 동일한 방식) —
/// `ScaffoldMessenger.showSnackBar`는 화면의 `Scaffold`를 기준으로 그려져,
/// 바텀시트가 열려 있는 동안 호출하면 바텀시트가 그 위(더 높은
/// Route/Overlay 레이어)를 차지해 스낵바가 가려져 보이지 않는 문제가 있었다.
class AppSnackBar {
  const AppSnackBar._();

  static final List<_QueuedMessage> _queue = [];
  static OverlayEntry? _entry;

  /// [replaceCurrent]가 true면 표시 전 대기 중인 메시지를 모두 지운다(최신
  /// 메시지만 의미 있는 연속 스캔 등 특수 흐름에서만 사용). 기본값은 false로,
  /// 여러 안내가 순서대로 큐잉된다.
  static void show(
    BuildContext context, {
    required String message,
    AppSnackBarType type = AppSnackBarType.info,
    Duration duration = const Duration(seconds: 4),
    bool replaceCurrent = false,
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    if (replaceCurrent) {
      _queue.clear();
      final current = _entry;
      _entry = null;
      current?.remove();
    }
    _queue.add(
      _QueuedMessage(message: message, type: type, duration: duration),
    );
    if (_entry == null) _showNext(overlay);
  }

  static void _showNext(OverlayState overlay) {
    if (_queue.isEmpty) {
      _entry = null;
      return;
    }
    final item = _queue.removeAt(0);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _AppSnackBarHost(
        message: item.message,
        type: item.type,
        duration: item.duration,
        onDismissed: () {
          // `replaceCurrent`로 이미 다른 entry로 교체됐으면(= 이 entry가
          // 더는 현재 `_entry`가 아니면) 이 콜백은 무효화된 이전 세대의
          // 것이니 아무것도 하지 않는다 — 그러지 않으면 이미 제거된
          // entry에 `remove()`를 다시 호출해 예외가 나고, `_showNext`도
          // 새 흐름을 건드리게 된다.
          if (_entry != entry) return;
          entry.remove();
          _entry = null;
          _showNext(overlay);
        },
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }

  static void success(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 4),
    bool replaceCurrent = false,
  }) => show(
    context,
    message: message,
    type: AppSnackBarType.success,
    duration: duration,
    replaceCurrent: replaceCurrent,
  );

  static void info(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 4),
    bool replaceCurrent = false,
  }) => show(
    context,
    message: message,
    type: AppSnackBarType.info,
    duration: duration,
    replaceCurrent: replaceCurrent,
  );

  static void error(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 4),
    bool replaceCurrent = false,
  }) => show(
    context,
    message: message,
    type: AppSnackBarType.error,
    duration: duration,
    replaceCurrent: replaceCurrent,
  );
}

class _QueuedMessage {
  const _QueuedMessage({
    required this.message,
    required this.type,
    required this.duration,
  });

  final String message;
  final AppSnackBarType type;
  final Duration duration;
}

/// 루트 오버레이에 꽂히는 스낵바 한 건. 등장/퇴장 애니메이션을 직접
/// 관리하고, 퇴장이 끝나면 [onDismissed]로 자신을 제거하고 다음 대기 중인
/// 메시지를 이어서 보여달라고 알린다.
class _AppSnackBarHost extends StatefulWidget {
  const _AppSnackBarHost({
    required this.message,
    required this.type,
    required this.duration,
    required this.onDismissed,
  });

  final String message;
  final AppSnackBarType type;
  final Duration duration;
  final VoidCallback onDismissed;

  @override
  State<_AppSnackBarHost> createState() => _AppSnackBarHostState();
}

class _AppSnackBarHostState extends State<_AppSnackBarHost> {
  static const _transitionDuration = Duration(milliseconds: 200);

  bool _visible = false;
  Timer? _hideTimer;
  Timer? _exitTimer;

  @override
  void initState() {
    super.initState();
    // 다음 프레임에 켜야 진입 애니메이션(투명→불투명, 아래→제자리)이 재생된다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _visible = true);
    });
    _hideTimer = Timer(widget.duration, _startExit);
  }

  void _startExit() {
    if (!mounted) return;
    setState(() => _visible = false);
    _exitTimer = Timer(_transitionDuration, widget.onDismissed);
  }

  @override
  void dispose() {
    // 퇴장 애니메이션 도중(entry.remove() 전) `replaceCurrent`로 이 위젯이
    // 강제로 dispose될 수 있다 — 이 타이머를 취소하지 않으면 200ms 뒤
    // 이미 제거된 `OverlayEntry`에 `onDismissed`(remove() 재호출)가
    // 그대로 발사된다(app_snackbar 리뷰 참고).
    _hideTimer?.cancel();
    _exitTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: MediaQuery.paddingOf(context).bottom + 32,
      child: IgnorePointer(
        child: Center(
          child: AnimatedSlide(
            offset: _visible ? Offset.zero : const Offset(0, 0.3),
            duration: _transitionDuration,
            curve: Curves.easeOut,
            child: AnimatedOpacity(
              opacity: _visible ? 1 : 0,
              duration: _transitionDuration,
              child: _AppSnackBarContent(
                message: widget.message,
                type: widget.type,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppSnackBarContent extends StatelessWidget {
  const _AppSnackBarContent({required this.message, required this.type});

  final String message;
  final AppSnackBarType type;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (type) {
      // 스낵바는 흰 아이콘/텍스트를 얹는 불투명 pill이라, 옅어진
      // AppColors.accentFill 대신 대비가 확실한 accentForeground를 쓴다.
      AppSnackBarType.success => (AppColors.accentForeground, PhosphorIconsFill.checkCircle),
      AppSnackBarType.info => (AppColors.accentForeground, PhosphorIconsFill.info),
      // 반투명 합성 후 흰 텍스트와의 대비가 WCAG AA(4.5:1)에 못 미쳐(원본
      // AppColors.error 88% 합성 시 약 3.71:1) 검정과 섞어 더 어둡게 만든다.
      AppSnackBarType.error => (
        Color.lerp(AppColors.error, Colors.black, 0.2)!,
        PhosphorIconsFill.xCircle,
      ),
    };

    // `Material` 조상 없이 루트 Overlay에 직접 꽂히므로(위 AppSnackBar
    // 문서 참고) `MaterialType.transparency`로 감싼다 — 그러지 않으면 이
    // 안의 `Text`가 디버그 모드에서 "Material 조상 없음"을 알리는 노란
    // 물결 밑줄과 함께 그려진다(배경/오버레이 시각에는 영향 없음).
    //
    // 기존 `ScaffoldMessenger.showSnackBar`는 자체적으로 화면에 새로
    // 삽입되는 안내를 스크린 리더에 자동 전달했지만, 루트 Overlay에 직접
    // 꽂는 이 구현은 그 처리를 대신 해줘야 한다 — `liveRegion: true`로
    // 명시한다. 내부 `Text`는 `ExcludeSemantics`로 가려 같은 메시지가
    // 두 번 읽히지 않게 한다.
    return Material(
      type: MaterialType.transparency,
      child: Semantics(
        container: true,
        liveRegion: true,
        label: message,
        child: ExcludeSemantics(
          child: Align(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.86,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
