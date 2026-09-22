import 'package:flutter/material.dart';

/// 본문이 현재 보이는 영역보다 길 때만 공통 헤더를 더 접는다.
class BookRecordNestedScrollView extends StatefulWidget {
  const BookRecordNestedScrollView({
    super.key,
    required this.headerSliverBuilder,
    required this.body,
  });

  final NestedScrollViewHeaderSliversBuilder headerSliverBuilder;
  final Widget body;

  @override
  State<BookRecordNestedScrollView> createState() =>
      _BookRecordNestedScrollViewState();
}

class _BookRecordNestedScrollViewState
    extends State<BookRecordNestedScrollView> {
  final _scrollKey = GlobalKey<NestedScrollViewState>();

  double _remainingContentExtent() {
    final controller = _scrollKey.currentState?.innerController;
    if (controller == null || !controller.hasClients) return 0;
    // BookRecordTabView가 선택된 탭의 위치만 연결한다.
    final position = controller.positions.first;
    if (!position.hasContentDimensions) return 0;
    return position.maxScrollExtent.clamp(0, double.infinity);
  }

  @override
  Widget build(BuildContext context) {
    return NestedScrollView(
      key: _scrollKey,
      physics: _ContentSizedHeaderPhysics(
        remainingContentExtent: _remainingContentExtent,
      ),
      headerSliverBuilder: widget.headerSliverBuilder,
      body: widget.body,
    );
  }
}

class _ContentSizedHeaderPhysics extends ClampingScrollPhysics {
  const _ContentSizedHeaderPhysics({
    required this.remainingContentExtent,
    super.parent,
  });

  final double Function() remainingContentExtent;

  @override
  _ContentSizedHeaderPhysics applyTo(ScrollPhysics? ancestor) {
    return _ContentSizedHeaderPhysics(
      remainingContentExtent: remainingContentExtent,
      parent: buildParent(ancestor),
    );
  }

  double _maxExtent(ScrollMetrics position) {
    // 헤더가 접힌 만큼 본문 viewport가 커지므로, 남은 본문 길이까지만
    // 헤더를 접으면 콘텐츠 뒤에 빈 스크롤 영역을 만들지 않는다.
    return (position.pixels + remainingContentExtent()).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
  }

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    final maxExtent = _maxExtent(position);
    if (value > position.pixels && value > maxExtent) {
      return value - maxExtent.clamp(position.pixels, double.infinity);
    }
    return super.applyBoundaryConditions(position, value);
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    return super.createBallisticSimulation(
      position.copyWith(maxScrollExtent: _maxExtent(position)),
      velocity,
    );
  }
}

/// 화면 밖 탭의 위치가 NestedScrollView의 스크롤 계산에 섞이지 않게 한다.
class BookRecordTabView extends StatelessWidget {
  const BookRecordTabView({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return TabBarView(
      children: [
        for (var index = 0; index < children.length; index++)
          _TabScrollScope(index: index, child: children[index]),
      ],
    );
  }
}

class _TabScrollScope extends StatefulWidget {
  const _TabScrollScope({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_TabScrollScope> createState() => _TabScrollScopeState();
}

class _TabScrollScopeState extends State<_TabScrollScope> {
  final _scrollController = _TabScrollController();
  TabController? _tabController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tabController?.removeListener(_updateConnection);
    _tabController = DefaultTabController.of(context);
    _tabController!.addListener(_updateConnection);
    _updateConnection();
  }

  @override
  void didUpdateWidget(covariant _TabScrollScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateConnection();
  }

  void _updateConnection() {
    _scrollController.updateConnection(
      PrimaryScrollController.of(context),
      active: _tabController!.index == widget.index,
    );
  }

  @override
  void dispose() {
    _tabController?.removeListener(_updateConnection);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PrimaryScrollController(
      controller: _scrollController,
      automaticallyInheritForPlatforms: TargetPlatform.values.toSet(),
      child: widget.child,
    );
  }
}

class _TabScrollController extends ScrollController {
  ScrollController? _nestedController;
  bool _active = false;

  void updateConnection(ScrollController controller, {required bool active}) {
    if (_nestedController == controller && _active == active) return;

    if (_active) {
      for (final position in positions) {
        // 이전 탭의 관성 스크롤이 새 탭으로 이어지지 않도록 중단한다.
        if (position is ScrollActivityDelegate) {
          (position as ScrollActivityDelegate).goIdle();
        }
        _nestedController!.detach(position);
      }
    }
    _nestedController = controller;
    _active = active;
    if (_active) {
      for (final position in positions) {
        controller.attach(position);
      }
    }
  }

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    // 위치 객체를 그대로 보존해야 탭별 위치와 헤더의 연동이 유지된다.
    return _nestedController!.createScrollPosition(
      physics,
      context,
      oldPosition,
    );
  }

  @override
  void attach(ScrollPosition position) {
    super.attach(position);
    if (_active) _nestedController!.attach(position);
  }

  @override
  void detach(ScrollPosition position) {
    if (_active) _nestedController!.detach(position);
    super.detach(position);
  }
}
