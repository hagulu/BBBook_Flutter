import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// 완독 탭 우측 연/월 빠른 스크롤 인덱스(Google 포토 사진 스크러버 참고).
///
/// 평소엔 아무것도 그리지 않는다(제스처 영역조차 없음 — 그래야 밑에 있는
/// 그리드가 오른쪽 가장자리에서도 정상적으로 스크롤/탭된다). 목록을
/// 스크롤하는 동안(또는 이미 나타난 썸을 직접 터치/드래그하는 동안)에만
/// 오른쪽 가장자리에 큼직한 썸(thumb)이 나타나고, 그때만 그 썸 영역 자체가
/// 제스처를 받는다. 썸을 드래그하는 동안에는 부모가 [onScrubChanged]로 받아
/// "YYYY년 M월" 버블을 그리는데, 버블은 썸/손가락에 가리지 않도록 이 위젯의
/// 폭보다 더 왼쪽에 그려야 한다(부모 책임).
class FinishedMonthIndexBar extends StatefulWidget {
  const FinishedMonthIndexBar({
    super.key,
    required this.groups,
    required this.scrollController,
    required this.onSelect,
    required this.onScrubChanged,
  });

  final List<({int year, int month, String groupKey})> groups;
  final ScrollController scrollController;
  final ValueChanged<String> onSelect;

  /// 드래그 중 버블에 표시할 라벨과, 트랙 기준 세로 위치(dy). 드래그가 끝나면 null.
  final ValueChanged<({String label, double dy})?> onScrubChanged;

  /// 썸이 오른쪽 가장자리에서 왼쪽으로 튀어나오는 폭(반원 반지름과 동일).
  /// 반투명이라 책 표지 위에 겹쳐도 되므로 콘텐츠 레이아웃 폭 계산에는
  /// 쓰지 않고, 버블이 썸/손가락을 피해 얼마나 왼쪽에 떠야 하는지 계산할
  /// 때만 참조한다.
  static const width = 32.0;

  @override
  State<FinishedMonthIndexBar> createState() => _FinishedMonthIndexBarState();
}

class _FinishedMonthIndexBarState extends State<FinishedMonthIndexBar> {
  // 반원 모양: 폭(반지름) == FinishedMonthIndexBar.width, 높이 == 반지름의 2배.
  static const _thumbHeight = FinishedMonthIndexBar.width * 2;
  static const _autoHideDelay = Duration(milliseconds: 900);

  double? _thumbDy;
  bool _isDragging = false;
  Timer? _autoHideTimer;
  ScrollPosition? _observedPosition;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_handleScroll);
  }

  @override
  void didUpdateWidget(covariant FinishedMonthIndexBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_handleScroll);
      _detachIsScrollingListener();
      widget.scrollController.addListener(_handleScroll);
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_handleScroll);
    _detachIsScrollingListener();
    _autoHideTimer?.cancel();
    super.dispose();
  }

  /// 사용자가 목록 자체를 스크롤할 때도(썸을 직접 잡지 않아도) 현재 위치에
  /// 썸을 보여준다. 썸을 드래그하는 중에는 터치 위치가 기준이므로 무시한다.
  ///
  /// 여기서는 썸 위치만 갱신하고 자동 숨김 타이머는 건드리지 않는다 — 이
  /// 콜백은 스크롤 중 프레임마다 호출되므로, [_scheduleAutoHide]를 매번
  /// 부르면 프레임마다 `Timer`를 취소·재생성하게 된다. 숨김 타이머는
  /// [_handleIsScrollingChanged]에서 스크롤이 시작/종료될 때만 한 번씩 예약한다.
  void _handleScroll() {
    if (_isDragging || !mounted) return;
    if (!widget.scrollController.hasClients) return;
    final position = widget.scrollController.position;
    _attachIsScrollingListener(position);
    if (position.maxScrollExtent <= 0) return;
    final trackHeight = context.size?.height;
    if (trackHeight == null || trackHeight <= 0) return;

    final fraction = (position.pixels / position.maxScrollExtent).clamp(0.0, 1.0);
    setState(() => _thumbDy = fraction * trackHeight);
  }

  void _attachIsScrollingListener(ScrollPosition position) {
    if (identical(_observedPosition, position)) return;
    _detachIsScrollingListener();
    _observedPosition = position;
    position.isScrollingNotifier.addListener(_handleIsScrollingChanged);
  }

  void _detachIsScrollingListener() {
    _observedPosition?.isScrollingNotifier.removeListener(_handleIsScrollingChanged);
    _observedPosition = null;
  }

  /// 스크롤이 시작되면(플링/드래그 중) 예약된 숨김 타이머를 취소하고, 스크롤이
  /// 멈추면 그 순간에만 숨김 타이머를 한 번 예약한다.
  void _handleIsScrollingChanged() {
    if (_isDragging || !mounted) return;
    final isScrolling = _observedPosition?.isScrollingNotifier.value ?? false;
    if (isScrolling) {
      _autoHideTimer?.cancel();
    } else {
      _scheduleAutoHide();
    }
  }

  void _scheduleAutoHide() {
    _autoHideTimer?.cancel();
    _autoHideTimer = Timer(_autoHideDelay, () {
      if (mounted && !_isDragging) setState(() => _thumbDy = null);
    });
  }

  void _selectForDy(double dy, double trackHeight) {
    if (widget.groups.isEmpty || trackHeight <= 0) return;
    final clampedDy = dy.clamp(0.0, trackHeight);
    final ratio = clampedDy / trackHeight;
    final index = (ratio * widget.groups.length).floor().clamp(0, widget.groups.length - 1);
    final group = widget.groups[index];

    setState(() => _thumbDy = clampedDy);
    widget.onSelect(group.groupKey);
    widget.onScrubChanged((label: '${group.year}년 ${group.month}월', dy: clampedDy));
  }

  void _startDrag(double dy, double trackHeight) {
    _autoHideTimer?.cancel();
    _isDragging = true;
    _selectForDy(dy, trackHeight);
  }

  void _endDrag() {
    if (!_isDragging) return;
    _isDragging = false;
    widget.onScrubChanged(null);
    _scheduleAutoHide();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.groups.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final trackHeight = constraints.maxHeight;
        final thumbDy = _thumbDy;

        // 썸이 안 보일 때는 제스처 영역 자체를 만들지 않는다 — 밑에 있는
        // 그리드가 오른쪽 가장자리에서도 평소대로 스크롤/탭되도록.
        if (thumbDy == null) {
          return SizedBox(width: FinishedMonthIndexBar.width, height: trackHeight);
        }

        final thumbTop = (thumbDy - _thumbHeight / 2).clamp(0.0, trackHeight - _thumbHeight);

        return SizedBox(
          width: FinishedMonthIndexBar.width,
          height: trackHeight,
          child: Stack(
            children: [
              Positioned(
                top: thumbTop,
                right: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) => _startDrag(thumbTop + details.localPosition.dy, trackHeight),
                  onTapUp: (_) => _endDrag(),
                  onTapCancel: _endDrag,
                  onVerticalDragStart: (details) =>
                      _startDrag(thumbTop + details.localPosition.dy, trackHeight),
                  onVerticalDragUpdate: (details) =>
                      _selectForDy((_thumbDy ?? thumbDy) + details.delta.dy, trackHeight),
                  onVerticalDragEnd: (_) => _endDrag(),
                  onVerticalDragCancel: _endDrag,
                  child: Container(
                    width: FinishedMonthIndexBar.width,
                    height: _thumbHeight,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      // 반원(오른쪽은 화면 가장자리에 붙는 직선, 왼쪽만 완전히
                      // 둥글게)이 되도록 왼쪽 두 모서리 반지름을 폭(반지름)과 같게 둔다.
                      color: AppColors.primary.withValues(alpha: _isDragging ? 0.75 : 0.55),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(FinishedMonthIndexBar.width),
                        bottomLeft: Radius.circular(FinishedMonthIndexBar.width),
                      ),
                    ),
                    child: const Icon(Icons.drag_indicator, size: 16, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
