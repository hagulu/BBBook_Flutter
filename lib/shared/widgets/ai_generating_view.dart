import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../core/theme/app_theme.dart';

/// AI 생성 대기 중임을 알리는 전용 표시(반짝이는 아이콘 + 상태 문구 + 점).
///
/// 일반 대기(`AppLoading`/`AppLoadingOverlay`)와 달리 AI 메모/독후감 생성처럼
/// 수 초~수십 초가 걸리는 작업 전용이다 — 단순 스피너 대신 "AI가 지금 뭔가
/// 만들고 있다"는 인상을 주기 위해 두 AI 진입점(메모 생성·독후감 생성)에서만
/// 공유해 쓴다.
///
/// 항상 어두운 전체 화면 차단막([_AiLoadingBarrier]) 위에서만 쓰이므로,
/// 밝기에 따라 바뀌는 테마 역할 색(`AppColors.of(context)`) 대신 카메라·사진
/// 뷰어와 같은 고정 미디어 색(`AppColors.mediaForeground`/`mediaBackdrop`)과
/// 브랜드 고정색을 쓴다 — 그래야 라이트/다크 테마 어디서도 글씨와 아이콘이
/// 항상 또렷하게 보인다(`color` 스킬: 같은 역할의 UI는 동일한 색상 규칙을
/// 따른다).
class AiGeneratingView extends StatefulWidget {
  const AiGeneratingView({super.key, required this.message});

  final String message;

  @override
  State<AiGeneratingView> createState() => _AiGeneratingViewState();
}

class _AiGeneratingViewState extends State<AiGeneratingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool? _animationsDisabled;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animationsDisabled = MediaQuery.disableAnimationsOf(context);
    if (_animationsDisabled == animationsDisabled) return;
    _animationsDisabled = animationsDisabled;
    if (animationsDisabled) {
      _controller
        ..stop()
        ..value = 0;
    } else {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = _controller.value;
              final breathe = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
              return SizedBox(
                width: 104,
                height: 104,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Transform.scale(
                      scale: 0.88 + 0.22 * breathe,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              AppColors.accentFill.withValues(alpha: 0.42),
                              AppColors.accentFill.withValues(alpha: 0),
                            ],
                          ),
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                    Transform.rotate(
                      angle: t * 2 * math.pi,
                      child: const Icon(
                        PhosphorIconsFill.sparkle,
                        size: 38,
                        color: AppColors.accentFill,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          Text(
            widget.message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.mediaForeground,
              fontWeight: FontWeight.w700,
              fontSize: 17,
              height: 1.4,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 18),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    _ThinkingDot(opacity: _dotOpacity(_controller.value, i)),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  double _dotOpacity(double t, int index) {
    final phase = (t - index / 3) % 1.0;
    final pulse = math.pow(math.sin(phase * math.pi), 6).toDouble();
    return 0.18 + 0.82 * pulse;
  }
}

class _ThinkingDot extends StatelessWidget {
  const _ThinkingDot({required this.opacity});

  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(
          color: AppColors.accentFill,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// [AiGeneratingView]를 전체 화면 차단 오버레이로 띄우는 전용 헬퍼.
///
/// `AppLoading`과 같은 참조 카운트 안전장치를 따르되(중첩 호출 방지),
/// 화면 전체를 잠그는 일반 로딩과 구분해 AI 생성 진행 상태에서만 쓴다.
class AppAiLoading {
  const AppAiLoading._();

  static OverlayEntry? _entry;
  static int _refCount = 0;

  static void show(BuildContext context, {required String message}) {
    _refCount++;
    if (_refCount > 1) return;

    final overlay = Overlay.of(context, rootOverlay: true);
    _entry = OverlayEntry(builder: (_) => _AiLoadingBarrier(message: message));
    overlay.insert(_entry!);
  }

  static void hide() {
    if (_refCount <= 0) return;
    _refCount--;
    if (_refCount > 0) return;

    _entry?.remove();
    _entry = null;
  }
}

class _AiLoadingBarrier extends StatelessWidget {
  const _AiLoadingBarrier({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    // 루트 Overlay에 직접 삽입되는 위젯은 Material 조상이 없다. 투명
    // Material을 제공하지 않으면 Text가 WidgetsApp의 디버그 기본 스타일
    // (노란 이중 밑줄)을 상속하므로, 공통 AppSnackBar와 같은 방식으로
    // 정상적인 Material 텍스트 문맥을 만든다.
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ModalBarrier(
            dismissible: false,
            color: AppColors.mediaBackdrop.withValues(alpha: 0.68),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Semantics(
                  container: true,
                  liveRegion: true,
                  label: '$message 잠시만 기다려 주세요.',
                  child: ExcludeSemantics(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 280),
                      child: AiGeneratingView(message: message),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
