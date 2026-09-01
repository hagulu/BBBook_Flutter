import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../models/record_labels.dart';
import 'icon_option_selector.dart';
import '../../../../shared/widgets/record_dialog_shell.dart';
import 'star_rating.dart';
import 'want_to_reread_toggle.dart';

/// "다 읽음" 전환 확인 팝업의 결과.
class FinishConfirmResult {
  const FinishConfirmResult({
    required this.wantToReread,
    this.difficulty,
    this.myRating,
    this.shortReview,
  });

  final bool wantToReread;
  final String? difficulty;

  /// 0점(별 선택 안 함)이면 "평가 안 함"으로 보고 PATCH 요청에서 생략한다.
  final double? myRating;
  final String? shortReview;
}

/// 완독 확인 팝업(또 볼래요/난이도/별점/한줄평 입력). 확인을 누르면
/// [FinishConfirmResult]를 반환하고, 배경 클릭/취소로 닫으면 null을 반환한다.
Future<FinishConfirmResult?> showFinishConfirmDialog(
  BuildContext context, {
  bool initialWantToReread = false,
}) {
  return showModalBottomSheet<FinishConfirmResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) =>
        _FinishConfirmDialog(initialWantToReread: initialWantToReread),
  );
}

class _FinishConfirmDialog extends StatefulWidget {
  const _FinishConfirmDialog({required this.initialWantToReread});

  final bool initialWantToReread;

  @override
  State<_FinishConfirmDialog> createState() => _FinishConfirmDialogState();
}

class _FinishConfirmDialogState extends State<_FinishConfirmDialog> {
  final _reviewController = TextEditingController();
  double _rating = 0;
  DifficultyLevel? _difficulty;
  late bool _wantToReread = widget.initialWantToReread;

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RecordDialogShell(
      title: '다 읽었어요!',
      titleTrailing: WantToRereadToggle(
        value: _wantToReread,
        onChanged: (v) => setState(() => _wantToReread = v),
        compact: true,
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          const SizedBox(height: 16),
          const Text(
            '별점과 한줄평을 남겨보세요.',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          Center(
            child: StarRatingInput(
              rating: _rating,
              onChanged: (v) => setState(() => _rating = v),
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
          label: '완독 처리',
          onPressed: () => Navigator.of(context).pop(
            FinishConfirmResult(
              wantToReread: _wantToReread,
              difficulty: _difficulty?.apiValue,
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
