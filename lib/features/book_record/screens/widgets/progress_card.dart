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
                    fontSize: 15,
                  ),
                ),
            ],
          ),
          if (totalPages != null && totalPages > 0)
            Slider(
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
        ],
      ),
    );
  }
}
