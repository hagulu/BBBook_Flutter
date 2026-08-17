import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// 전체 화면 공통 Loading.
///
/// 화면 어디서든 [show]/[hide]를 호출할 수 있으며, 중첩 호출을 참조 카운트로
/// 안전하게 처리한다(마지막 [hide]에서만 실제로 닫힘).
class AppLoading {
  const AppLoading._();

  static OverlayEntry? _entry;
  static int _refCount = 0;

  static void show(BuildContext context) {
    _refCount++;
    if (_refCount > 1) return;

    final overlay = Overlay.of(context, rootOverlay: true);
    _entry = OverlayEntry(builder: (_) => const _FullScreenLoadingBarrier());
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

class _FullScreenLoadingBarrier extends StatelessWidget {
  const _FullScreenLoadingBarrier();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ModalBarrier(
          dismissible: false,
          color: Colors.black.withValues(alpha: 0.3),
        ),
        Center(
          child: Semantics(
            liveRegion: true,
            label: '로딩 중',
            child: const CircularProgressIndicator(color: AppColors.accentForeground),
          ),
        ),
        // 아래 화면의 시맨틱스(포커스·스크린 리더 탐색)를 차단해 로딩 중 조작을 막는다.
        const BlockSemantics(),
      ],
    );
  }
}

/// 영역 단위 공통 Loading.
///
/// [isLoading]이 true인 동안 [child] 위에 스피너 오버레이를 표시한다.
class AppLoadingOverlay extends StatelessWidget {
  const AppLoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
  });

  final bool isLoading;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading) ...[
          Positioned.fill(
            child: AbsorbPointer(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.15),
                child: Center(
                  child: Semantics(
                    liveRegion: true,
                    label: '로딩 중',
                    child: const CircularProgressIndicator(
                      color: AppColors.accentForeground,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // child의 시맨틱스를 차단해 로딩 중 버튼 등을 스크린 리더로 조작할 수 없게 한다.
          const BlockSemantics(),
        ],
      ],
    );
  }
}
