import 'package:calendar_date_picker2/calendar_date_picker2.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
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
/// 생략한다(실물책 선택 시 서버가 platformName을 자동으로 null 처리하므로
/// 별도 전송이 필요 없다).
class SourcePlatformResult {
  const SourcePlatformResult({required this.sourceType, this.platformName});

  final BookSourceType sourceType;
  final String? platformName;
}

/// 출처(실물책/전자책/오디오북) 및 플랫폼 선택 팝업.
Future<SourcePlatformResult?> showSourcePlatformDialog(
  BuildContext context, {
  required BookSourceType? initialSource,
  required String? initialPlatform,
  required Map<String, List<String>> platformOptions,
}) {
  return showModalBottomSheet<SourcePlatformResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _SourcePlatformDialog(
      initialSource: initialSource,
      initialPlatform: initialPlatform,
      platformOptions: platformOptions,
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
  });

  final BookSourceType? initialSource;
  final String? initialPlatform;
  final Map<String, List<String>> platformOptions;

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
    super.dispose();
  }

  List<String> get _platforms {
    final key = _source?.platformOptionsKey;
    if (key == null) return const [];
    return widget.platformOptions[key] ?? const [];
  }

  bool get _isCustomSelected => _selectedPlatform == _kCustomPlatformLabel;

  void _save() {
    final source = _source;
    if (source == null) return;

    String? platformName;
    if (source.platformOptionsKey != null) {
      if (_selectedPlatform == _kUnsetPlatformLabel) {
        // '미설정' 선택: 문서상 빈 문자열을 보내야 null로 저장된다(명시적
        // 삭제). null을 그대로 보내면 "변경 없음"으로 해석돼 기존 값이 남는다.
        platformName = '';
      } else if (_isCustomSelected) {
        final custom = _customController.text.trim();
        platformName = custom.isEmpty ? null : custom;
      } else if (_selectedPlatform != null) {
        platformName = _selectedPlatform;
      } else if (source != widget.initialSource) {
        // 출처를 바꿨는데 새 플랫폼을 아직 고르지 않았다: platformName을
        // null(=변경 없음)로 보내면 이전 출처의 플랫폼명이 그대로 남는다.
        // 빈 문자열을 보내 명시적으로 지운다(문서 기준 빈 문자열 → null 저장).
        platformName = '';
      }
    }
    Navigator.of(
      context,
    ).pop(SourcePlatformResult(sourceType: source, platformName: platformName));
  }

  /// 출처 선택. 플랫폼이 필요 없는 출처(실물책)는 바로 저장하고 닫는다.
  void _selectSource(BookSourceType source) {
    setState(() {
      _source = source;
      _selectedPlatform = null;
    });
    if (source.platformOptionsKey == null) _save();
  }

  /// 플랫폼 선택. '직접 입력'을 고르면 입력창을 펼치기만 하고, 그 외에는
  /// 바로 저장하고 닫는다.
  void _selectPlatform(String platform) {
    setState(() => _selectedPlatform = platform);
    if (platform != _kCustomPlatformLabel) _save();
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
        ],
      ),
      buttons: _isCustomSelected
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
/// 텍스트를 반환하고, 비어 있으면 취소와 동일하게 null을 반환한다(빈
/// 문자열로 지우고 싶다면 지운 채로 저장 — 서버가 빈 문자열을 null로 저장).
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
Future<ReadingDateResult?> showReadingDateDialog(
  BuildContext context, {
  required DateTime? initialDate,
  required DateTime lastDate,
  required bool isStartedAt,
}) {
  return showModalBottomSheet<ReadingDateResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _ReadingDateDialog(
      title: isStartedAt ? '시작일 선택' : '완독일 선택',
      initialDate: initialDate,
      lastDate: lastDate,
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
  });

  final String title;
  final DateTime? initialDate;
  final DateTime lastDate;

  @override
  Widget build(BuildContext context) {
    return RecordDialogShell(
      title: title,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (initialDate != null) ...[
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
