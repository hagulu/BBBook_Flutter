import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../bookshelf/models/book_item.dart';
import '../../../bookshelf/models/record_patch.dart';
import '../../providers/book_record_providers.dart';
import 'record_section_card.dart';

/// 읽는 중/멈춤 상태에서만 노출되는 진행률 카드.
///
/// 진행률 바(Slider)는 표시 전용이며 드래그로 수정할 수 없다. 쪽수 입력은
/// 포커스를 얻으면 기존 값을 플레이스홀더로 보여주고 입력창은 비워, 지우지
/// 않고 바로 새 값을 입력할 수 있게 한다.
///
/// 직접 입력한 값은 키보드의 완료(제출) 액션을 눌렀을 때만 적용된다.
/// 입력 중 완료를 누르지 않고 포커스를 잃으면 마지막으로 적용된 값으로
/// 되돌린다.
class ProgressCard extends ConsumerStatefulWidget {
  const ProgressCard({super.key, required this.userBookId, required this.book});

  final int userBookId;
  final BookItem book;

  @override
  ConsumerState<ProgressCard> createState() => _ProgressCardState();
}

class _ProgressCardState extends ConsumerState<ProgressCard> {
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
    _pageController.dispose();
    _pageFocus.dispose();
    super.dispose();
  }

  int get _maxPage =>
      widget.book.isAudioBook ? 100 : (widget.book.effectiveTotalPages ?? 0);

  void _onFocusChanged() {
    if (_pageFocus.hasFocus) {
      setState(() {
        _pageHint = _pageController.text;
        _pageController.clear();
      });
    } else {
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

  void _commitPage() {
    final parsed = int.tryParse(_pageController.text.trim());
    _apply(parsed == null ? _committedPage : _clamp(parsed));
    _pageFocus.unfocus();
  }

  Future<void> _save(int page) {
    return ref
        .read(bookRecordControllerProvider(widget.userBookId).notifier)
        .updateRecord(RecordPatch(currentPage: page));
  }

  @override
  Widget build(BuildContext context) {
    final isAudioBook = widget.book.isAudioBook;
    // 오디오북은 currentPage 자체가 0~100 진행률 값이라 별도 총량 표시가
    // 없다 — 페이지 기반 총쪽수는 종이책/전자책에서만 의미가 있다.
    final totalPages = isAudioBook ? null : widget.book.effectiveTotalPages;
    final ratio = widget.book.progressRatio;
    // 진행률 바에 쓸 상한. 오디오북은 항상 100(%), 그 외는 총쪽수를 알 때만.
    final showBar = isAudioBook || (totalPages != null && totalPages > 0);
    final barMax = isAudioBook ? 100 : totalPages;

    return RecordSectionCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 오디오북은 오른쪽 입력값 자체가 이미 퍼센트라(접미사 '%')
              // 왼쪽에 같은 값을 또 보여주면 중복이라 생략한다.
              if (!isAudioBook && ratio != null)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(
                    '${(ratio * 100).round()}%',
                    style: const TextStyle(
                      color: AppColors.progressFill,
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                ),
              const Spacer(),
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
              if (isAudioBook)
                const Text(
                  '%',
                  style: TextStyle(color: AppColors.textMuted),
                )
              else if (totalPages != null)
                Text(
                  ' / $totalPages쪽',
                  style: const TextStyle(color: AppColors.textMuted),
                ),
            ],
          ),
          // 오디오북은 페이지가 아니라 0~100 퍼센트 상한으로 같은 바를
          // 그대로 쓴다 — "페이지 기반 슬라이더"가 아니라 퍼센트 진행 바라
          // 오디오북에도 자연스럽다.
          if (showBar) const SizedBox(height: 6),
          if (showBar)
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
                  value: _sliderValue.clamp(0, barMax!.toDouble()),
                  min: 0,
                  max: barMax.toDouble(),
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
