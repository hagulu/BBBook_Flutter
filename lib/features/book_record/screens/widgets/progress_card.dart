import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../bookshelf/models/book_item.dart';
import '../../providers/book_record_providers.dart';
import 'record_section_card.dart';

/// 읽는 중/멈춤 상태에서만 노출되는 진행률 카드.
///
/// 진행률 바(Slider)는 표시 전용이며 드래그로 수정할 수 없다. 쪽수 입력은
/// 포커스를 얻으면 기존 값을 플레이스홀더로 보여주고 입력창은 비워, 지우지
/// 않고 바로 새 값을 입력할 수 있게 한다. 포커스 중에는 키보드 위에 증감
/// 버튼 툴바를 오버레이로 띄운다.
///
/// 저장 시점이 두 가지다: 증감 버튼은 누르는 즉시 적용/저장되고, 직접
/// 입력한 값은 키보드의 완료(제출) 액션을 눌렀을 때만 적용된다(커스텀
/// 완료 버튼은 키보드 자체의 완료 액션과 중복이라 두지 않는다) — 입력
/// 중 완료를 누르지 않고 포커스를 잃으면 마지막으로 적용된 값으로
/// 되돌린다.
class ProgressCard extends ConsumerStatefulWidget {
  const ProgressCard({super.key, required this.userBookId, required this.book});

  final int userBookId;
  final BookItem book;

  @override
  ConsumerState<ProgressCard> createState() => _ProgressCardState();
}

class _ProgressCardState extends ConsumerState<ProgressCard> {
  static const List<(String, int)> _steps = [
    ('-', -1),
    ('+', 1),
    ('+10', 10),
    ('+30', 30),
    ('+100', 100),
  ];

  late final _pageController = TextEditingController(
    text: '${widget.book.currentPage}',
  );
  final _pageFocus = FocusNode();
  late double _sliderValue = widget.book.currentPage.toDouble();
  // 마지막으로 실제 적용(저장 요청)된 값. widget.book.currentPage는 로컬
  // 저장이 반영되기 전까지 한 프레임 뒤처질 수 있어, 포커스 아웃 시
  // 되돌릴 기준값은 이 필드로 별도 관리한다.
  late int _committedPage = widget.book.currentPage;
  String? _pageHint;
  OverlayEntry? _toolbarEntry;

  @override
  void initState() {
    super.initState();
    _pageFocus.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant ProgressCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.book.currentPage != oldWidget.book.currentPage &&
        !_pageFocus.hasFocus) {
      _committedPage = widget.book.currentPage;
      _pageController.text = '${widget.book.currentPage}';
      _sliderValue = widget.book.currentPage.toDouble();
    }
  }

  @override
  void dispose() {
    _pageFocus.removeListener(_onFocusChanged);
    _hideToolbar();
    _pageController.dispose();
    _pageFocus.dispose();
    super.dispose();
  }

  int get _maxPage => widget.book.totalPages ?? 0;

  void _onFocusChanged() {
    if (_pageFocus.hasFocus) {
      setState(() {
        _pageHint = _pageController.text;
        _pageController.clear();
      });
      _showToolbar();
    } else {
      _hideToolbar();
      // 직접 입력 중 키보드 완료(제출)를 누르지 않고 포커스를 잃으면
      // 마지막으로 적용된 값으로 되돌린다.
      setState(() {
        _pageController.text = '$_committedPage';
        _sliderValue = _committedPage.toDouble();
      });
    }
  }

  int _clamp(int page) =>
      _maxPage > 0 ? page.clamp(0, _maxPage) : page.clamp(0, 1 << 31);

  void _apply(int page) {
    // widget.book.currentPage는 저장 요청이 반영되기 전까지 한 프레임
    // 이상 뒤처질 수 있어, 변경 여부는 그 값이 아니라 직전에 로컬로
    // 적용한 _committedPage와 비교한다. 그렇지 않으면 저장이 끝나기 전에
    // 연속으로 버튼을 눌러 원래 값으로 돌아왔을 때(예: 10 → 11 저장 중
    // → 다시 10) 두 번째 요청이 "변경 없음"으로 오인되어 저장 큐에서
    // 누락될 수 있다.
    final changed = page != _committedPage;
    _committedPage = page;
    setState(() {
      _pageController.text = '$page';
      _sliderValue = page.toDouble();
    });
    if (changed) _save(page);
  }

  void _stepPage(int delta) {
    final base = int.tryParse(_pageController.text.trim()) ?? _committedPage;
    _apply(_clamp(base + delta));
  }

  void _commitPage() {
    final parsed = int.tryParse(_pageController.text.trim());
    _apply(parsed == null ? _committedPage : _clamp(parsed));
    _pageFocus.unfocus();
  }

  Future<void> _save(int page) {
    return ref
        .read(bookRecordControllerProvider(widget.userBookId).notifier)
        .updateRecord(currentPage: page);
  }

  void _showToolbar() {
    if (_toolbarEntry != null) return;
    final overlay = Overlay.of(context, rootOverlay: true);
    _toolbarEntry = OverlayEntry(
      builder: (_) => _PageStepToolbar(steps: _steps, onStep: _stepPage),
    );
    overlay.insert(_toolbarEntry!);
  }

  void _hideToolbar() {
    _toolbarEntry?.remove();
    _toolbarEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    final totalPages = widget.book.totalPages;
    final ratio = widget.book.progressRatio;

    return RecordSectionCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 56,
                child: TextField(
                  controller: _pageController,
                  focusNode: _pageFocus,
                  textAlign: TextAlign.end,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textStrong,
                  ),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onSubmitted: (_) => _commitPage(),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                    hintText: _pageHint,
                    hintStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ),
              if (totalPages != null)
                Text(
                  ' / $totalPages쪽',
                  style: const TextStyle(color: AppColors.textMuted),
                ),
              const Spacer(),
              if (ratio != null)
                Text(
                  '${(ratio * 100).round()}%',
                  style: const TextStyle(
                    color: AppColors.progressFill,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
            ],
          ),
          if (totalPages != null && totalPages > 0)
            const SizedBox(height: 6),
          if (totalPages != null && totalPages > 0)
            SizedBox(
              // 표시 전용(드래그 불가)이라 손잡이 터치 영역이 필요 없어,
              // 트랙 두께에 맞춰 세로 여백을 최소화했다.
              height: 14,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  // 표시 전용 진행률 바 — 손잡이를 없애 드래그 가능한
                  // 컨트롤처럼 보이지 않게 한다.
                  thumbShape: SliderComponentShape.noThumb,
                  overlayShape: SliderComponentShape.noOverlay,
                  activeTrackColor: AppColors.progressFill,
                  inactiveTrackColor: AppColors.border,
                  disabledActiveTrackColor: AppColors.progressFill,
                  disabledInactiveTrackColor: AppColors.border,
                ),
                child: Slider(
                  padding: EdgeInsets.zero,
                  value: _sliderValue.clamp(0, totalPages.toDouble()),
                  min: 0,
                  max: totalPages.toDouble(),
                  // onChanged를 주지 않아 수정을 막는다(표시 전용).
                  onChanged: null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 쪽수 입력 포커스 중 키보드 위에 뜨는 증감 버튼 툴바. 누르는 즉시
/// 적용/저장되며(별도 완료 확인 없음), 폭 전체에 넓게 퍼지도록 배치한다.
class _PageStepToolbar extends StatelessWidget {
  const _PageStepToolbar({required this.steps, required this.onStep});

  final List<(String, int)> steps;
  final void Function(int delta) onStep;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Positioned(
      left: 0,
      right: 0,
      bottom: bottomInset,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.pageBackground,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SafeArea(
          top: false,
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            // 평소엔 pill들이 폭 전체에 넓게 퍼지지만, 큰 글자 설정 등으로
            // 내용이 화면보다 넓어지면 오버플로 대신 가로 스크롤로
            // 자연스럽게 대응한다.
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (final step in steps)
                          _PageStepPill(
                            label: step.$1,
                            onTap: () => onStep(step.$2),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PageStepPill extends StatelessWidget {
  const _PageStepPill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceSubtle,
      shape: const StadiumBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Container(
          // 최소 터치 영역(48)을 보장한다.
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textStrong,
            ),
          ),
        ),
      ),
    );
  }
}
