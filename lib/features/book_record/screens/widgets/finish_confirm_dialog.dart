import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/record_dialog_shell.dart';
import '../../../bookshelf/models/book_item.dart';
import '../../models/record_labels.dart';
import 'icon_option_selector.dart';
import 'meta_dialogs.dart';
import 'star_rating.dart';

/// 완독 확인 팝업의 결과. 이미 값이 있어 팝업에서 다시 묻지 않은 항목은
/// null로 남아 [RecordPatch] 변환 시 자연스럽게 생략(기존 값 유지)된다.
class FinishConfirmResult {
  const FinishConfirmResult({
    required this.wantToReread,
    required this.isMasterpiece,
    this.sourceType,
    this.difficulty,
    this.myRating,
    this.shortReview,
    this.finishedAt,
  });

  final bool wantToReread;
  final bool isMasterpiece;
  final BookSourceType? sourceType;
  final String? difficulty;

  /// 0점(별 선택 안 함)이면 "평가 안 함"으로 보고 요청에서 생략한다.
  final double? myRating;
  final String? shortReview;

  /// 완독일 필드를 노출한 호출부([showFinishConfirmDialog]의
  /// `showFinishedAt: true`)에서만 값이 채워질 수 있다. null이면 "오늘"을
  /// 뜻한다(서버가 자동으로 오늘 날짜를 채운다).
  final DateTime? finishedAt;
}

/// [book]을 기준으로 완독 팝업을 띄울 때 이미 채워진 항목만 물어봐도 되는지
/// 판단한다. 출처/난이도/평가(별점·한줄평)가 모두 이미 있으면 물어볼 게
/// 없다는 뜻 — 이때는 팝업 없이 바로 완독 처리해야 한다(호출부 책임).
bool finishConfirmNeedsDialog(BookItem book) {
  final hasSource = BookSourceType.fromApiValue(book.sourceType) != null;
  final hasDifficulty = DifficultyLevel.fromApiValue(book.difficulty) != null;
  return !hasSource || !hasDifficulty || !hasRatingOrReview(book);
}

/// 별점·한줄평은 팝업에서 하나로 묶어 보여준다 — 둘 중 하나라도 이미 있으면
/// "이미 평가한 책"으로 보고 둘 다 다시 묻지 않는다(별점만 있고 한줄평이
/// 없다고 해서 한줄평 입력만 남겨두지 않는다).
bool hasRatingOrReview(BookItem book) =>
    book.myRating != null ||
    (book.shortReview != null && book.shortReview!.isNotEmpty);

/// 완독 확인 팝업(완독일·명작/또 볼래·출처·난이도·별점·한줄평 입력). 책
/// 기록 상세(이미 있는 기록을 완독 처리)와 책 검색 상세·직접 등록(아직
/// 서재에 없는 책을 완독 상태로 새로 담기)이 이 하나의 위젯을 공유한다 —
/// 두 흐름은 "무엇을 이미 알고 있는지"만 다르므로, 호출부가 `show*` 플래그로
/// 각 항목의 노출 여부를 결정한다.
///
/// - 책 기록 상세: 이미 값이 있는 항목(출처/난이도/평가)은 물어보지 않는다.
///   완독일은 이 팝업에서 정하지 않으면(기본 "오늘") 서버가 오늘 날짜로
///   채운다 — [MetaSummaryCard]로도 나중에 따로 고칠 수 있다.
/// - 책 검색 상세/직접 등록: 아직 서재에 없는 새 책이라 출처/난이도/평가가
///   모두 비어 있어 항상 물어본다.
///
/// 확인을 누르면 [FinishConfirmResult]를 반환하고, 배경 클릭/취소로 닫으면
/// null을 반환한다.
///
/// 명작은 창작 API가 아직 받지 않아 새 책 등록 흐름에서는 생성 직후 별도
/// PATCH로 반영한다(호출부 책임 — `book_detail_screen.dart`/
/// `custom_book_dialog.dart` 참고). 이 팝업 자체는 어느 흐름에서든 항상
/// 명작 토글을 보여준다.
Future<FinishConfirmResult?> showFinishConfirmDialog(
  BuildContext context, {
  required bool showSource,
  required bool showDifficulty,
  required bool showRatingReview,
  bool showFinishedAt = false,
  bool initialWantToReread = false,
  bool initialIsMasterpiece = false,
}) {
  return showModalBottomSheet<FinishConfirmResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _FinishConfirmDialog(
      showSource: showSource,
      showDifficulty: showDifficulty,
      showRatingReview: showRatingReview,
      showFinishedAt: showFinishedAt,
      initialWantToReread: initialWantToReread,
      initialIsMasterpiece: initialIsMasterpiece,
    ),
  );
}

class _FinishConfirmDialog extends StatefulWidget {
  const _FinishConfirmDialog({
    required this.showSource,
    required this.showDifficulty,
    required this.showRatingReview,
    required this.showFinishedAt,
    required this.initialWantToReread,
    required this.initialIsMasterpiece,
  });

  final bool showSource;
  final bool showDifficulty;
  final bool showRatingReview;
  final bool showFinishedAt;
  final bool initialWantToReread;
  final bool initialIsMasterpiece;

  @override
  State<_FinishConfirmDialog> createState() => _FinishConfirmDialogState();
}

class _FinishConfirmDialogState extends State<_FinishConfirmDialog> {
  final _reviewController = TextEditingController();
  final _reviewFocus = FocusNode();
  final _scrollController = ScrollController();
  double _rating = 0;
  DifficultyLevel? _difficulty;
  BookSourceType? _sourceType;
  DateTime? _finishedAt;
  late bool _wantToReread = widget.initialWantToReread;
  late bool _isMasterpiece = widget.initialIsMasterpiece;

  @override
  void initState() {
    super.initState();
    _reviewFocus.addListener(_onReviewFocusChanged);
  }

  // 한줄평은 시트 맨 아래 필드라, 기본 스크롤-포커스 동작(가려진 영역만
  // 딱 맞게 끌어올리는 ensureVisible)에 맡기면 저장 버튼과 애매하게 걸친
  // 위치에서 멈춘다. 포커스를 얻으면 그냥 시트를 끝까지 스크롤해 버튼까지
  // 함께 보이게 한다. 키보드가 다 올라온 뒤 최종 레이아웃 기준으로
  // 스크롤해야 끝까지 갈 수 있어, 플랫폼 키보드 애니메이션 시간만큼
  // 기다렸다가 스크롤한다(포커스 직후 한 프레임만으로는 키보드가 아직
  // 다 안 올라와 maxScrollExtent가 최종값이 아니다).
  void _onReviewFocusChanged() {
    if (!_reviewFocus.hasFocus) return;
    Future.delayed(const Duration(milliseconds: 260), () {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _reviewFocus.removeListener(_onReviewFocusChanged);
    _reviewController.dispose();
    _reviewFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _pickFinishedAt() async {
    final now = DateTime.now();
    final result = await showReadingDateDialog(
      context,
      // 아직 안 골랐어도 오늘을 기본 선택값으로 보여준다 — 매번 오늘
      // 날짜를 달력에서 다시 찾아 탭하지 않아도 되게 한다.
      initialDate: _finishedAt ?? now,
      lastDate: now,
      isStartedAt: false,
      canClear: false,
    );
    final picked = result?.date;
    if (picked != null && mounted) setState(() => _finishedAt = picked);
  }

  String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  @override
  Widget build(BuildContext context) {
    final sections = <Widget>[
      if (widget.showFinishedAt)
        Align(
          alignment: Alignment.centerLeft,
          child: InkWell(
            onTap: _pickFinishedAt,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 11,
              ),
              decoration: BoxDecoration(
                color: AppColors.surfaceSubtle,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    PhosphorIconsRegular.calendarCheck,
                    size: 16,
                    color: AppColors.controlInactive,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _finishedAt == null
                        ? '완독일: 오늘'
                        : '완독일: ${_formatDate(_finishedAt!)}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textBody,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    PhosphorIconsRegular.caretDown,
                    size: 14,
                    color: AppColors.controlInactive,
                  ),
                ],
              ),
            ),
          ),
        ),
      Row(
        children: [
          Expanded(
            child: BoolIconOption(
              label: '명작',
              value: _isMasterpiece,
              filledIcon: PhosphorIconsFill.crown,
              regularIcon: PhosphorIconsRegular.crown,
              activeColor: AppColors.highlightGold,
              onChanged: (v) => setState(() => _isMasterpiece = v),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: BoolIconOption(
              // 다른 완독 관련 위젯(WantToRereadToggle)과 같은 반말 라벨 —
              // "내가 나에게 남기는 기록" 원칙을 유지한다.
              label: '또 볼래',
              value: _wantToReread,
              filledIcon: PhosphorIconsFill.repeat,
              regularIcon: PhosphorIconsRegular.repeat,
              activeColor: AppColors.error,
              onChanged: (v) => setState(() => _wantToReread = v),
            ),
          ),
        ],
      ),
      if (widget.showSource)
        IconOptionSelector<BookSourceType>(
          options: [
            for (final source in BookSourceType.values)
              IconOption(
                value: source,
                icon: source.icon,
                label: source.label,
              ),
          ],
          selected: _sourceType,
          onSelected: (v) =>
              setState(() => _sourceType = v == _sourceType ? null : v),
        ),
      if (widget.showDifficulty)
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
      if (widget.showRatingReview)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
              focusNode: _reviewFocus,
              maxLength: 150,
              maxLines: 3,
              decoration: const InputDecoration(
                isDense: true,
                hintText: '한줄평을 남겨보세요',
                counterStyle: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
    ];

    return RecordDialogShell(
      title: '완독',
      scrollController: _scrollController,
      titleTrailing: const Text(
        '모두 선택 사항이에요. 원하는 항목만 골라주세요.',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: AppColors.textMuted,
        ),
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            sections[i],
          ],
        ],
      ),
      buttons: [
        RecordDialogButton(
          label: '저장',
          onPressed: () => Navigator.of(context).pop(
            FinishConfirmResult(
              wantToReread: _wantToReread,
              isMasterpiece: _isMasterpiece,
              sourceType: _sourceType,
              difficulty: _difficulty?.apiValue,
              myRating: _rating == 0 ? null : _rating,
              shortReview: _reviewController.text.trim().isEmpty
                  ? null
                  : _reviewController.text.trim(),
              finishedAt: _finishedAt,
            ),
          ),
        ),
      ],
    );
  }
}
