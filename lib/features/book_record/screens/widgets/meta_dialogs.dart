import 'package:calendar_date_picker2/calendar_date_picker2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/network/patch_field.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_confirm.dart';
import '../../../bookshelf/models/book_status.dart';
import '../../models/record_labels.dart';
import 'icon_option_selector.dart';
import 'pill_option.dart';
import '../../../../shared/widgets/record_dialog_shell.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// 독서 상태 선택 팝업. 정사각형 카드를 고르면 바로 그 상태를 반환하며 닫힌다.
Future<BookStatus?> showReadingStatusDialog(
  BuildContext context, {
  required BookStatus initialStatus,
}) {
  return showModalBottomSheet<BookStatus>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => RecordDialogShell(
      title: '독서 상태',
      content: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1,
        children: [
          for (final status in BookStatus.values)
            _StatusCard(
              status: status,
              selected: status == initialStatus,
              onTap: () => Navigator.of(context).pop(status),
            ),
        ],
      ),
    ),
  );
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.status,
    required this.selected,
    required this.onTap,
  });

  final BookStatus status;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: status.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accentSurface.withValues(alpha: 0.35)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.accentForeground : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                status.icon,
                size: 28,
                color: selected
                    ? AppColors.accentForeground
                    : AppColors.controlInactive,
              ),
              const SizedBox(height: 8),
              Flexible(
                child: Text(
                  status.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                    color: selected
                        ? AppColors.accentForeground
                        : AppColors.textBody,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// [showSourcePlatformDialog] 결과. [platformName]이 null이면 요청에서
/// 생략(변경 없음), `PatchField.clear()`면 명시적 null로 지운다. 종이책을
/// 선택하면 이전에 설정된 플랫폼이 있든 없든 항상 `.clear()`가 담긴다(서버가
/// sourceType=PAPER_BOOK일 때 platformName을 강제로 null 처리하지만, 그
/// 자동 정리에 기대지 않고 여기서도 명시적으로 지운다).
/// [displayTotalPages]는 전자책 전체 쪽수 override — null이면 변경 없음,
/// `PatchField.clear()`면 삭제(종이책 기준 쪽수로 되돌아감), `.value(n)`이면
/// 그 값으로 설정. 전자책이 아닌 형태를 선택했는데 기존에 override가
/// 설정돼 있었다면 자동으로 `.clear()`가 담긴다(그러지 않으면 화면에서는
/// 사라진 것처럼 보이는 값이 진행률·완독 상한 계산에는 계속 쓰인다).
class SourcePlatformResult {
  const SourcePlatformResult({
    required this.sourceType,
    this.platformName,
    this.displayTotalPages,
  });

  final BookSourceType sourceType;
  final PatchField<String>? platformName;
  final PatchField<int>? displayTotalPages;
}

/// 출처(종이책/전자책/오디오북) 및 플랫폼 선택 팝업. 전자책을 고르면 전자책
/// 전체 쪽수(선택 사항) 입력 필드가 함께 나온다 — 설정하면 그 값을 기준으로
/// 진행률을 계산하고(`displayTotalPages ?? statsTotalPages`), 비워두면 종이책
/// 기준 쪽수로 fallback한다. 종이책 기준 쪽수 자체는 이 팝업에서 바꾸지 않는다.
///
/// [initialCurrentPage]는 전자책 쪽수 입력값 검증에 쓴다 — 새로 입력한
/// 값이 현재 읽은 쪽수보다 작으면 `PATCH .../book-info`가 400으로 거부되므로
/// (api-doc), 저장 전에 이 팝업 안에서 미리 막는다.
Future<SourcePlatformResult?> showSourcePlatformDialog(
  BuildContext context, {
  required BookSourceType? initialSource,
  required String? initialPlatform,
  required Map<String, List<String>> platformOptions,
  int? initialDisplayTotalPages,
  required int initialCurrentPage,
}) {
  return showModalBottomSheet<SourcePlatformResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _SourcePlatformDialog(
      initialSource: initialSource,
      initialPlatform: initialPlatform,
      platformOptions: platformOptions,
      initialDisplayTotalPages: initialDisplayTotalPages,
      initialCurrentPage: initialCurrentPage,
    ),
  );
}

const _kCustomPlatformLabel = '직접 입력';
const _kUnsetPlatformLabel = '미설정';

class _SourcePlatformDialog extends StatefulWidget {
  const _SourcePlatformDialog({
    required this.initialSource,
    required this.initialPlatform,
    required this.platformOptions,
    this.initialDisplayTotalPages,
    required this.initialCurrentPage,
  });

  final BookSourceType? initialSource;
  final String? initialPlatform;
  final Map<String, List<String>> platformOptions;
  final int? initialDisplayTotalPages;
  final int initialCurrentPage;

  @override
  State<_SourcePlatformDialog> createState() => _SourcePlatformDialogState();
}

class _SourcePlatformDialogState extends State<_SourcePlatformDialog> {
  late BookSourceType? _source = widget.initialSource;

  // 기존 플랫폼명이 옵션 목록에 없으면(과거에 직접 입력한 값) '직접 입력'
  // 칩을 미리 선택해두고 입력창에 그 값을 채워, 다이얼로그를 다시 열었을 때
  // 값이 사라진 것처럼 보이지 않게 한다.
  late String? _selectedPlatform = _isKnownPlatform()
      ? widget.initialPlatform
      : (_hasCustomInitialPlatform ? _kCustomPlatformLabel : null);
  late final _customController = TextEditingController(
    text: _hasCustomInitialPlatform ? widget.initialPlatform! : '',
  );
  late final _ebookPagesController = TextEditingController(
    text: widget.initialDisplayTotalPages?.toString() ?? '',
  );
  String? _ebookPagesError;

  bool _isKnownPlatform() {
    final key = widget.initialSource?.platformOptionsKey;
    if (key == null || widget.initialPlatform == null) return false;
    return (widget.platformOptions[key] ?? const []).contains(
      widget.initialPlatform,
    );
  }

  bool get _hasCustomInitialPlatform {
    final platform = widget.initialPlatform;
    if (widget.initialSource?.platformOptionsKey == null ||
        platform == null ||
        platform.isEmpty) {
      return false;
    }
    return !_isKnownPlatform();
  }

  @override
  void dispose() {
    _customController.dispose();
    _ebookPagesController.dispose();
    super.dispose();
  }

  List<String> get _platforms {
    final key = _source?.platformOptionsKey;
    if (key == null) return const [];
    return widget.platformOptions[key] ?? const [];
  }

  bool get _isCustomSelected => _selectedPlatform == _kCustomPlatformLabel;

  bool get _isEbookSelected => _source == BookSourceType.ebook;

  void _save() {
    final source = _source;
    if (source == null) return;
    if (_ebookPagesError != null) setState(() => _ebookPagesError = null);

    PatchField<String>? platformName;
    if (source.platformOptionsKey != null) {
      if (_selectedPlatform == _kUnsetPlatformLabel) {
        // '미설정' 선택: 명시적 null을 보내야 기존 값이 지워진다. 아무것도
        // 보내지 않으면(생략) "변경 없음"으로 해석돼 기존 값이 남고, 빈
        // 문자열을 보내면 삭제가 아니라 빈 값이 저장된다(api-doc).
        platformName = const PatchField.clear();
      } else if (_isCustomSelected) {
        final custom = _customController.text.trim();
        // 직접 입력을 비운 채 저장하면 "지움"으로 본다.
        platformName = custom.isEmpty
            ? const PatchField.clear()
            : PatchField.value(custom);
      } else if (_selectedPlatform != null) {
        platformName = PatchField.value(_selectedPlatform!);
      } else if (source != widget.initialSource) {
        // 출처를 바꿨는데 새 플랫폼을 아직 고르지 않았다: 생략하면 이전
        // 출처의 플랫폼명이 그대로 남으므로 명시적으로 지운다.
        platformName = const PatchField.clear();
      }
    } else {
      // 종이책은 플랫폼 개념이 없다 — 메인 기록 PATCH는 sourceType이
      // PAPER_BOOK이면 platformName을 값과 무관하게 강제로 null 처리하지만
      // (api-me-books-userBookId-patch.md), 그 자동 정리에 기대지 않고
      // 여기서도 항상 명시적으로 지워 요청 의도를 분명히 한다.
      platformName = const PatchField.clear();
    }

    PatchField<int>? displayTotalPages;
    if (_isEbookSelected) {
      final text = _ebookPagesController.text.trim();
      final parsed = text.isEmpty ? null : int.tryParse(text);
      if (text.isEmpty) {
        // 비워둔 채 저장 — 기존에 설정된 값이 있었을 때만 명시적으로 지운다.
        if (widget.initialDisplayTotalPages != null) {
          displayTotalPages = const PatchField.clear();
        }
      } else if (parsed != null &&
          _source == widget.initialSource &&
          parsed < widget.initialCurrentPage) {
        // 현재 읽은 쪽수보다 작은 값은 저장 요청 자체가 400으로 거부된다
        // (api-me-books-userBookId-book-info-patch.md) — 요청을 보내기 전에
        // 여기서 미리 막는다. 출처 자체를 바꾸는 경우(전자책을 유지하는
        // 게 아니라 다른 출처에서 전자책으로 전환)는 저장 시
        // `BookItem.normalizedCurrentPageForSourceChange`가 진행 기록을
        // 0으로 초기화하므로(사용자에게는 출처 선택 시점에 미리 경고) 이
        // 비교 자체가 필요 없다 — 어떤 총쪽수를 입력해도 항상 유효하다.
        setState(() {
          _ebookPagesError = '현재 읽은 쪽수(${widget.initialCurrentPage}쪽)보다 작을 수 없어요.';
        });
        return;
      } else if (parsed != null && parsed != widget.initialDisplayTotalPages) {
        displayTotalPages = PatchField.value(parsed);
      }
    } else if (widget.initialDisplayTotalPages != null) {
      // 전자책이 아닌 형태로 바꾸면 남아있는 전자책 쪽수 override를 함께
      // 지운다 — 그러지 않으면 화면에서만 사라진 것처럼 보이고 진행률·완독
      // 상한 계산에는 계속 쓰인다.
      displayTotalPages = const PatchField.clear();
    }

    Navigator.of(context).pop(
      SourcePlatformResult(
        sourceType: source,
        platformName: platformName,
        displayTotalPages: displayTotalPages,
      ),
    );
  }

  /// 출처 선택. 이미 진행 기록이 있는 책의 출처를 실제로 바꾸면(초기 출처와
  /// 다르고 [widget.initialCurrentPage]가 0보다 크면) 저장 시 진행 기록이
  /// 0으로 초기화된다(쪽수 ↔ 퍼센트는 단위가 달라 자동 환산하지 않는다 —
  /// `BookItem.normalizedCurrentPageForSourceChange`) — 선택하는 이 시점에
  /// 한 번만 경고 확인을 받고, 취소하면 선택을 되돌린다. 플랫폼이 필요
  /// 없는 출처(종이책)는 확인(또는 애초에 경고가 필요 없으면 곧바로) 후
  /// 바로 저장하고 닫는다.
  Future<void> _selectSource(BookSourceType source) async {
    if (source != widget.initialSource && widget.initialCurrentPage > 0) {
      final confirmed = await AppConfirm.show(
        context,
        title: '출처 변경',
        message: '출처를 바꾸면 현재 읽은 기록이 0으로 초기화됩니다. 계속할까요?',
        confirmText: '변경',
        destructive: true,
      );
      if (!confirmed || !mounted) return;
    }
    setState(() {
      _source = source;
      _selectedPlatform = null;
    });
    if (source.platformOptionsKey == null) _save();
  }

  /// 플랫폼 선택. '직접 입력'을 고르면 입력창을 펼치기만 하고, 전자책은
  /// 쪽수 입력을 이어서 받아야 하므로 "저장" 버튼을 눌러야 닫힌다. 그 외
  /// (오디오북)는 플랫폼을 고르면 바로 저장하고 닫는다.
  void _selectPlatform(String platform) {
    setState(() => _selectedPlatform = platform);
    if (platform != _kCustomPlatformLabel && !_isEbookSelected) _save();
  }

  @override
  Widget build(BuildContext context) {
    return RecordDialogShell(
      title: '출처',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconOptionSelector<BookSourceType>(
            options: [
              for (final source in BookSourceType.values)
                IconOption(
                  value: source,
                  icon: source.icon,
                  label: source.label,
                ),
            ],
            selected: _source,
            onSelected: _selectSource,
          ),
          if (_source?.platformOptionsKey != null) ...[
            const SizedBox(height: 16),
            const Text(
              '플랫폼',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                PillOption(
                  label: _kUnsetPlatformLabel,
                  selected: _selectedPlatform == _kUnsetPlatformLabel,
                  onTap: () => _selectPlatform(_kUnsetPlatformLabel),
                ),
                for (final platform in _platforms)
                  PillOption(
                    label: platform,
                    selected: _selectedPlatform == platform,
                    onTap: () => _selectPlatform(platform),
                  ),
              ],
            ),
            if (_isCustomSelected) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _customController,
                maxLength: 50,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '플랫폼명을 입력하세요',
                  counterText: '',
                  prefixIcon: Icon(PhosphorIconsRegular.pencil, size: 18),
                ),
              ),
            ],
          ],
          if (_isEbookSelected) ...[
            const SizedBox(height: 16),
            const Text(
              '전자책 전체 쪽수',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _ebookPagesController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) {
                if (_ebookPagesError != null) {
                  setState(() => _ebookPagesError = null);
                }
              },
              decoration: const InputDecoration(
                isDense: true,
                hintText: '선택 사항 — 비워두면 종이책 기준 쪽수를 사용해요',
                counterText: '',
              ),
            ),
            if (_ebookPagesError != null) ...[
              const SizedBox(height: 6),
              Text(
                _ebookPagesError!,
                style: const TextStyle(color: AppColors.error, fontSize: 12),
              ),
            ],
          ],
        ],
      ),
      buttons: _isCustomSelected || _isEbookSelected
          ? [RecordDialogButton(label: '저장', onPressed: _save)]
          : const [],
    );
  }
}

/// 난이도 선택 팝업. [initialDifficulty]는 로컬에 저장된 API 값(EASY 등)이고,
/// 반환값도 API 값이다 — 화면 표시용 한글 라벨과는 [DifficultyLevel]에서만
/// 변환한다(저장값에 한글이 섞이지 않도록).
Future<String?> showDifficultyDialog(
  BuildContext context, {
  required String? initialDifficulty,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => RecordDialogShell(
      title: '난이도',
      content: IconOptionSelector<DifficultyLevel>(
        options: [
          for (final level in DifficultyLevel.values)
            IconOption(
              value: level,
              icon: level.icon,
              label: level.label,
              iconSize: 22,
            ),
        ],
        selected: DifficultyLevel.fromApiValue(initialDifficulty),
        onSelected: (level) => Navigator.of(context).pop(level.apiValue),
      ),
    ),
  );
}

/// 알게 된 경로(자유 텍스트, 최대 50자) 입력 팝업. 저장을 누르면 trim된
/// 텍스트를, 취소/배경 닫기면 null을 반환한다. 입력을 비운 채 저장하면 빈
/// 문자열이 돌아오고, 호출부가 그것을 "지움"(명시적 null)으로 옮긴다 —
/// 빈 문자열을 그대로 보내면 서버는 삭제가 아니라 빈 값으로 저장한다.
Future<String?> showDiscoverySourceDialog(
  BuildContext context, {
  required String? initialValue,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _DiscoverySourceDialog(initialValue: initialValue),
  );
}

/// 한 줄 평(자유 텍스트, 최대 2000자) 입력 팝업. 저장을 누르면 trim된
/// 텍스트를, 취소/배경 닫기면 null을 반환한다. [showDiscoverySourceDialog]와
/// 같은 규칙으로, 입력을 비운 채 저장하면 빈 문자열이 돌아오고 호출부가
/// 그것을 "지움"(명시적 null)으로 옮긴다.
Future<String?> showShortReviewDialog(
  BuildContext context, {
  required String? initialValue,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _ShortReviewDialog(initialValue: initialValue),
  );
}

class _ShortReviewDialog extends StatefulWidget {
  const _ShortReviewDialog({required this.initialValue});

  final String? initialValue;

  @override
  State<_ShortReviewDialog> createState() => _ShortReviewDialogState();
}

class _ShortReviewDialogState extends State<_ShortReviewDialog> {
  late final _controller = TextEditingController(
    text: widget.initialValue ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RecordDialogShell(
      title: '한줄 평',
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 2000,
        maxLines: 5,
        decoration: const InputDecoration(
          isDense: true,
          hintText: '이 책에 대한 한 줄 평을 남겨보세요.',
        ),
      ),
      buttons: [
        RecordDialogButton(
          label: '저장',
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
        ),
      ],
    );
  }
}

/// [showReadingDateDialog]의 결과. 날짜를 골랐으면 [date]가 채워지고
/// [cleared]는 false, "선택 해제"를 눌렀으면 [date]는 null이고 [cleared]가
/// true다 — 반환값 자체가 null(바텀시트를 그냥 닫음)인 "변경 없음"과
/// 구분하기 위해 필요하다.
class ReadingDateResult {
  const ReadingDateResult.picked(this.date) : cleared = false;

  const ReadingDateResult.cleared() : date = null, cleared = true;

  final DateTime? date;
  final bool cleared;
}

/// 시작일/완독일 선택 팝업. `calendar_date_picker2`로 달력을 바텀시트 안에
/// 그려서, 플랫폼 기본 `showDatePicker`의 별도 다이얼로그 대신 다른 선택
/// 팝업들과 같은 바텀시트 톤을 유지한다.
///
/// [canClear]가 false면 "선택 해제"를 노출하지 않는다 — 완독 상태의 완독일이
/// 그렇다. 서버는 수정 결과 status가 FINISHED이면 완독일 삭제를 무시하고
/// 기존 값(없으면 오늘)을 유지하므로(api-doc), 지울 수 있는 것처럼 보여주면
/// 눌러도 되돌아오는 조작이 된다.
Future<ReadingDateResult?> showReadingDateDialog(
  BuildContext context, {
  required DateTime? initialDate,
  required DateTime lastDate,
  required bool isStartedAt,
  bool canClear = true,
}) {
  return showModalBottomSheet<ReadingDateResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _ReadingDateDialog(
      title: isStartedAt ? '시작일 선택' : '완독일 선택',
      initialDate: initialDate,
      lastDate: lastDate,
      canClear: canClear,
    ),
  );
}

/// 날짜를 탭하는 즉시 그 날짜로 팝업을 닫는다(별도 저장 버튼 없음 — 월/년
/// 모드 토글은 표시 월만 바꿀 뿐 [CalendarDatePicker2]가 `onValueChanged`를
/// 호출하지 않아 실수로 닫히지 않는다). 이미 설정된 날짜가 있으면 제목 아래에
/// 작은 "선택 해제" 버튼을 둬서, 실수로 고른 날짜를 되돌릴 수 있게 한다.
class _ReadingDateDialog extends StatelessWidget {
  const _ReadingDateDialog({
    required this.title,
    required this.initialDate,
    required this.lastDate,
    required this.canClear,
  });

  final String title;
  final DateTime? initialDate;
  final DateTime lastDate;
  final bool canClear;

  @override
  Widget build(BuildContext context) {
    return RecordDialogShell(
      title: title,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (initialDate != null && canClear) ...[
            Align(
              alignment: Alignment.centerRight,
              child: PillOption(
                label: '선택 해제',
                selected: false,
                onTap: () => Navigator.of(
                  context,
                ).pop(const ReadingDateResult.cleared()),
              ),
            ),
            const SizedBox(height: 8),
          ],
          _buildCalendar(context),
        ],
      ),
    );
  }

  Widget _buildCalendar(BuildContext context) {
    return CalendarDatePicker2(
      config: CalendarDatePicker2Config(
        calendarType: CalendarDatePicker2Type.single,
        firstDate: DateTime(1900),
        lastDate: lastDate,
        dynamicCalendarRows: true,
        centerAlignModePicker: true,
        // 화면에 보이는 요일/월·년 표기는 직접 한글로 고정한다 — 이제 앱이
        // 한국어 MaterialLocalizations를 제공하므로(app.dart) 패키지 기본
        // 로케일 포맷도 한글로 나오긴 하지만, 그 경로는 intl 로케일
        // 데이터가 초기화돼 있어야 한다는 전제가 있어 직접 확인하지 못했다
        // — 화면 표시만큼은 이 값으로 확실하게 고정한다(스크린 리더 안내는
        // flutter_localizations가 formatFullDate 등으로 별도 제공).
        weekdayLabels: const ['일', '월', '화', '수', '목', '금', '토'],
        modePickerTextHandler: ({required monthDate, isMonthPicker}) =>
            isMonthPicker == true
            ? '${monthDate.month}월'
            : '${monthDate.year}년',
        // 날짜를 다시 탭해도(이미 선택된 날짜 재확인) 닫히도록 허용한다 —
        // 이 시트엔 별도 저장 버튼이 없어 탭 자체가 곧 확정이라, 같은 값을
        // 다시 탭했을 때만 콜백이 안 오면 그 상태로 멈춘 것처럼 보인다.
        allowSameValueSelection: true,
        selectedDayHighlightColor: AppColors.accentFill,
        dayBorderRadius: BorderRadius.circular(10),
        yearBorderRadius: BorderRadius.circular(10),
        selectedDayTextStyle: const TextStyle(
          color: AppColors.textStrong,
          fontWeight: FontWeight.bold,
        ),
        todayTextStyle: const TextStyle(
          color: AppColors.accentForeground,
          fontWeight: FontWeight.bold,
        ),
        dayTextStyle: const TextStyle(color: AppColors.textBody),
        disabledDayTextStyle: const TextStyle(color: AppColors.controlInactive),
        weekdayLabelTextStyle: const TextStyle(
          color: AppColors.textMuted,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        controlsTextStyle: const TextStyle(
          color: AppColors.textStrong,
          fontWeight: FontWeight.bold,
          fontSize: 15,
        ),
      ),
      // 미설정이면 빈 목록을 넘긴다 — [lastDate](오늘)를 미리 선택값으로
      // 채우면, 오늘을 처음 탭했을 때 "이미 선택된 값과 같음"으로 처리돼
      // onValueChanged가 호출되지 않는다(표시 월은 그래도 오늘이 속한
      // 달로 맞춰진다 — displayedMonthDate 생략 시 기본값).
      value: initialDate != null ? [initialDate] : const [],
      onValueChanged: (dates) {
        if (dates.isEmpty) return;
        Navigator.of(context).pop(ReadingDateResult.picked(dates.first));
      },
    );
  }
}

class _DiscoverySourceDialog extends StatefulWidget {
  const _DiscoverySourceDialog({required this.initialValue});

  final String? initialValue;

  @override
  State<_DiscoverySourceDialog> createState() => _DiscoverySourceDialogState();
}

class _DiscoverySourceDialogState extends State<_DiscoverySourceDialog> {
  late final _controller = TextEditingController(
    text: widget.initialValue ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RecordDialogShell(
      title: '알게 된 경로',
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 50,
        decoration: const InputDecoration(
          isDense: true,
          hintText: '예: 친구 추천, SNS, 서점',
          counterText: '',
        ),
      ),
      buttons: [
        RecordDialogButton(
          label: '저장',
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
        ),
      ],
    );
  }
}
