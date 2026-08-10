import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../bookshelf/models/book_item.dart';
import '../../providers/book_record_providers.dart';
import 'record_section_card.dart';

/// 읽는 중/멈춤 상태에서만 노출되는 진행률 카드. 페이지 입력은 포커스 아웃,
/// 슬라이더는 놓을 때(`onChangeEnd`)만 저장한다(book-record.md 기준).
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

  @override
  void initState() {
    super.initState();
    _pageFocus.addListener(() {
      if (!_pageFocus.hasFocus) _submitPageText();
    });
  }

  @override
  void didUpdateWidget(covariant ProgressCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.book.currentPage != oldWidget.book.currentPage &&
        !_pageFocus.hasFocus) {
      _pageController.text = '${widget.book.currentPage}';
      _sliderValue = widget.book.currentPage.toDouble();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _pageFocus.dispose();
    super.dispose();
  }

  int get _maxPage => widget.book.totalPages ?? 0;

  void _submitPageText() {
    final parsed = int.tryParse(_pageController.text.trim());
    if (parsed == null) {
      _pageController.text = '${widget.book.currentPage}';
      return;
    }
    final clamped = _maxPage > 0
        ? parsed.clamp(0, _maxPage)
        : parsed.clamp(0, 1 << 31);
    _pageController.text = '$clamped';
    setState(() => _sliderValue = clamped.toDouble());
    _save(clamped);
  }

  Future<void> _save(int page) async {
    if (page == widget.book.currentPage) return;
    try {
      await ref
          .read(bookRecordControllerProvider(widget.userBookId).notifier)
          .updateRecord(currentPage: page);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
        setState(() {
          _pageController.text = '${widget.book.currentPage}';
          _sliderValue = widget.book.currentPage.toDouble();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalPages = widget.book.totalPages;
    final ratio = widget.book.progressRatio;

    return RecordSectionCard(
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
                    fontWeight: FontWeight.bold,
                    color: AppColors.titleText,
                  ),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onSubmitted: (_) => _pageFocus.unfocus(),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              if (totalPages != null)
                Text(
                  ' / $totalPages쪽',
                  style: const TextStyle(color: AppColors.tertiaryText),
                ),
              const Spacer(),
              if (ratio != null)
                Text(
                  '${(ratio * 100).round()}%',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
            ],
          ),
          if (totalPages != null && totalPages > 0) const SizedBox(height: 12),
          if (totalPages != null && totalPages > 0)
            SizedBox(
              // Slider의 기본 세로 여백이 overlay 크기 기준이라 overlay를
              // 줄이면 터치 영역도 함께 줄어든다 — 높이를 고정해 최소
              // 조작 영역(48)을 보장한다.
              height: 48,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 8,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 16,
                  ),
                ),
                child: Slider(
                  // 트랙 좌우 기본 여백(thumb/overlay 크기 기준)을 없애
                  // 위 Row(쪽수/퍼센트)와 폭을 맞춘다 — 음수 Padding 대신
                  // Slider가 공식 지원하는 padding으로 처리한다.
                  padding: EdgeInsets.zero,
                  value: _sliderValue.clamp(0, totalPages.toDouble()),
                  min: 0,
                  max: totalPages.toDouble(),
                  activeColor: AppColors.primary,
                  onChanged: (v) => setState(() {
                    _sliderValue = v;
                    _pageController.text = '${v.round()}';
                  }),
                  onChangeEnd: (v) => _save(v.round()),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
