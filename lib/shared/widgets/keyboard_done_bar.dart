import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// iOS 숫자 키패드에는 리턴/완료 키가 없어 입력을 마칠 방법이 없다.
/// 자식 안의 입력창이 포커스를 가지면 키보드 바로 위에 "완료" 바를 띄워
/// 키보드를 내린다. iOS가 아니면 아무것도 하지 않는다.
class KeyboardDoneBar extends StatefulWidget {
  const KeyboardDoneBar({super.key, required this.child, this.onDone});

  final Widget child;

  /// 완료 버튼을 눌렀을 때 포커스를 해제하기 전에 실행한다. 포커스 해제만으로는
  /// 제출(onSubmitted)이 일어나지 않는 입력창이 값을 적용할 때 쓴다.
  final VoidCallback? onDone;

  /// 완료 바가 현재 화면에 떠 있는지. 키보드 바로 위에 고정된 하단 UI가
  /// 완료 바에 가려지지 않도록 그 높이만큼 비켜 주는 데 쓴다.
  static final ValueNotifier<bool> isShown = ValueNotifier(false);

  /// 완료 바의 높이.
  static const double height = 44;

  static int _activeCount = 0;

  // dispose·레이아웃 중에 호출될 수 있어 다음 프레임에 반영한다.
  static void _syncShown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      isShown.value = _activeCount > 0;
    });
  }

  @override
  State<KeyboardDoneBar> createState() => _KeyboardDoneBarState();
}

class _KeyboardDoneBarState extends State<KeyboardDoneBar> {
  OverlayEntry? _entry;

  bool get _enabled => defaultTargetPlatform == TargetPlatform.iOS;

  void _onFocusChange(bool hasFocus) {
    if (!_enabled) return;
    if (hasFocus) {
      _show();
    } else {
      _hide();
    }
  }

  void _show() {
    if (_entry != null) return;
    final entry = OverlayEntry(
      builder: (overlayContext) => Positioned(
        left: 0,
        right: 0,
        bottom: MediaQuery.viewInsetsOf(overlayContext).bottom,
        child: _DoneBar(
          onDone: () => FocusManager.instance.primaryFocus?.unfocus(),
        ),
      ),
    );
    _entry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
    KeyboardDoneBar._activeCount++;
    KeyboardDoneBar._syncShown();
  }

  void _hide() {
    if (_entry == null) return;
    _entry!.remove();
    _entry = null;
    KeyboardDoneBar._activeCount--;
    KeyboardDoneBar._syncShown();
  }

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: _onFocusChange,
      child: widget.child,
    );
  }
}

class _DoneBar extends StatelessWidget {
  const _DoneBar({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Material(
      color: colors.surfaceSubtle,
      child: Container(
        height: KeyboardDoneBar.height,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.border)),
        ),
        child: TextButton(
          onPressed: onDone,
          child: Text(
            '완료',
            style: TextStyle(
              color: colors.accentForeground,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
