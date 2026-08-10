import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../bookshelf/models/book_status.dart';
import '../../models/record_labels.dart';
import 'icon_option_selector.dart';
import 'pill_option.dart';
import 'record_dialog_shell.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// 독서 상태 선택 팝업. 정사각형 카드를 고르면 바로 그 상태를 반환하며 닫힌다.
Future<BookStatus?> showReadingStatusDialog(
  BuildContext context, {
  required BookStatus initialStatus,
}) {
  return showDialog<BookStatus>(
    context: context,
    builder: (context) => RecordDialogShell(
      icon: PhosphorIconsRegular.listChecks,
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
      buttons: [
        RecordDialogButton(
          label: '취소',
          style: RecordDialogButtonStyle.neutral,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
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
                ? AppColors.accentLight.withValues(alpha: 0.35)
                : AppColors.cardBackground,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                status.icon,
                size: 28,
                color: selected ? AppColors.primary : AppColors.mutedIcon,
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
                    color: selected ? AppColors.primary : AppColors.bodyText,
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
  return showDialog<SourcePlatformResult>(
    context: context,
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

  @override
  Widget build(BuildContext context) {
    return RecordDialogShell(
      icon: PhosphorIconsRegular.stack,
      title: '출처 / 플랫폼',
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
            onSelected: (source) => setState(() {
              _source = source;
              _selectedPlatform = null;
            }),
          ),
          if (_source?.platformOptionsKey != null) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (widget.initialPlatform != null &&
                    widget.initialPlatform!.isNotEmpty)
                  PillOption(
                    label: _kUnsetPlatformLabel,
                    icon: PhosphorIconsRegular.minusCircle,
                    selected: _selectedPlatform == _kUnsetPlatformLabel,
                    onTap: () => setState(
                      () => _selectedPlatform = _kUnsetPlatformLabel,
                    ),
                  ),
                for (final platform in _platforms)
                  PillOption(
                    label: platform,
                    selected: _selectedPlatform == platform,
                    onTap: () => setState(() => _selectedPlatform = platform),
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
      buttons: [
        RecordDialogButton(
          label: '취소',
          style: RecordDialogButtonStyle.neutral,
          onPressed: () => Navigator.of(context).pop(),
        ),
        RecordDialogButton(
          label: '저장',
          onPressed: _source == null ? null : _save,
        ),
      ],
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
  return showDialog<String>(
    context: context,
    builder: (context) => RecordDialogShell(
      icon: PhosphorIconsRegular.gauge,
      title: '난이도',
      content: IconOptionSelector<DifficultyLevel>(
        options: [
          for (final level in DifficultyLevel.values)
            IconOption(value: level, icon: level.icon, label: level.label),
        ],
        selected: DifficultyLevel.fromApiValue(initialDifficulty),
        onSelected: (level) => Navigator.of(context).pop(level.apiValue),
      ),
      buttons: [
        RecordDialogButton(
          label: '취소',
          style: RecordDialogButtonStyle.neutral,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
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
  return showDialog<String>(
    context: context,
    builder: (context) => _DiscoverySourceDialog(initialValue: initialValue),
  );
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
      icon: PhosphorIconsRegular.compass,
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
          label: '취소',
          style: RecordDialogButtonStyle.neutral,
          onPressed: () => Navigator.of(context).pop(),
        ),
        RecordDialogButton(
          label: '저장',
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
        ),
      ],
    );
  }
}
