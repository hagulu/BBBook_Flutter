import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../book_record/models/record_labels.dart';
import '../../../book_record/screens/widgets/icon_option_selector.dart';
import '../../../book_record/screens/widgets/record_dialog_shell.dart';
import '../../../book_record/screens/widgets/star_rating.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// "다 읽음" 서재 담기 시 입력하는 완독 옵션(book-detail.md: 출처/난이도/
/// 완독일/별점/한줄평). 책 기록 화면의 [FinishConfirmResult](난이도/별점/
/// 한줄평만 다룸)와는 요구 항목이 달라 별도 위젯으로 둔다 — 공유 다이얼로그를
/// 확장하면 책 기록 화면 동작까지 바뀌게 된다.
class FinishOptionsResult {
  const FinishOptionsResult({
    this.sourceType,
    this.difficulty,
    this.finishedAt,
    this.myRating,
    this.shortReview,
  });

  final BookSourceType? sourceType;
  final DifficultyLevel? difficulty;

  /// null이면 서버가 `X-Timezone` 기준 오늘 날짜로 자동 설정한다(api-doc).
  final DateTime? finishedAt;

  /// 0점(별 선택 안 함)이면 "평가 안 함"으로 보고 요청에서 생략한다.
  final double? myRating;
  final String? shortReview;
}

Future<FinishOptionsResult?> showFinishOptionsDialog(BuildContext context) {
  return showModalBottomSheet<FinishOptionsResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const _FinishOptionsDialog(),
  );
}

class _FinishOptionsDialog extends StatefulWidget {
  const _FinishOptionsDialog();

  @override
  State<_FinishOptionsDialog> createState() => _FinishOptionsDialogState();
}

class _FinishOptionsDialogState extends State<_FinishOptionsDialog> {
  final _reviewController = TextEditingController();
  double _rating = 0;
  DifficultyLevel? _difficulty;
  BookSourceType? _sourceType;
  DateTime? _finishedAt;

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  Future<void> _pickFinishedAt() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _finishedAt ?? now,
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: '완독일 선택',
    );
    if (picked != null) setState(() => _finishedAt = picked);
  }

  String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  @override
  Widget build(BuildContext context) {
    return RecordDialogShell(
      title: '완독 정보',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '별점과 한줄평을 남겨보세요.',
            style: TextStyle(fontSize: 13, color: AppColors.tertiaryText),
          ),
          const SizedBox(height: 12),
          Center(
            child: StarRatingInput(
              rating: _rating,
              onChanged: (v) => setState(() => _rating = v),
            ),
          ),
          const SizedBox(height: 12),
          IconOptionSelector<BookSourceType>(
            options: [
              for (final source in BookSourceType.values)
                IconOption(value: source, icon: source.icon, label: source.label),
            ],
            selected: _sourceType,
            onSelected: (v) =>
                setState(() => _sourceType = v == _sourceType ? null : v),
          ),
          const SizedBox(height: 12),
          IconOptionSelector<DifficultyLevel>(
            options: [
              for (final level in DifficultyLevel.values)
                IconOption(
                  value: level,
                  icon: level.icon,
                  label: level.label,
                  iconSize: 22,
                ),
            ],
            selected: _difficulty,
            onSelected: (v) =>
                setState(() => _difficulty = v == _difficulty ? null : v),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickFinishedAt,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
              decoration: BoxDecoration(
                color: AppColors.inputBackground,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    PhosphorIconsRegular.calendarCheck,
                    size: 16,
                    color: AppColors.mutedIcon,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _finishedAt == null ? '완독일: 오늘' : '완독일: ${_formatDate(_finishedAt!)}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.bodyText,
                      ),
                    ),
                  ),
                  const Icon(
                    PhosphorIconsRegular.caretDown,
                    size: 14,
                    color: AppColors.mutedIcon,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reviewController,
            maxLength: 2000,
            maxLines: 3,
            decoration: const InputDecoration(
              isDense: true,
              hintText: '한줄평을 남겨보세요',
              counterText: '',
            ),
          ),
        ],
      ),
      buttons: [
        RecordDialogButton(
          label: '완독 등록',
          onPressed: () => Navigator.of(context).pop(
            FinishOptionsResult(
              sourceType: _sourceType,
              difficulty: _difficulty,
              finishedAt: _finishedAt,
              myRating: _rating == 0 ? null : _rating,
              shortReview: _reviewController.text.trim().isEmpty
                  ? null
                  : _reviewController.text.trim(),
            ),
          ),
        ),
      ],
    );
  }
}
