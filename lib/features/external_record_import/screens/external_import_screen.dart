import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../app/main_shell_tab_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_alert.dart';
import '../../../shared/widgets/app_bar_title.dart';
import '../../../shared/widgets/app_confirm.dart';
import '../../../shared/widgets/app_loading.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../models/external_import_models.dart';
import '../providers/external_import_providers.dart';
import '../services/external_record_import_service.dart';

class ExternalImportScreen extends ConsumerStatefulWidget {
  const ExternalImportScreen({super.key, required this.file});

  final ExternalImportFileReference file;

  @override
  ConsumerState<ExternalImportScreen> createState() =>
      _ExternalImportScreenState();
}

class _ExternalImportScreenState extends ConsumerState<ExternalImportScreen> {
  var _overwriteWarningConfirmed = false;
  var _confirmingLeave = false;
  var _allowPop = false;

  Future<void> _handlePopAttempt(bool didPop) async {
    if (didPop || _confirmingLeave) return;
    final phase = ref.read(
      externalImportControllerProvider(
        widget.file,
      ).select((state) => state.phase),
    );
    if (phase != ExternalImportPhase.importing) return;
    _confirmingLeave = true;
    final confirmed = await AppConfirm.show(
      context,
      title: '가져오기 화면 닫기',
      message: '화면을 닫아도 기록 가져오기는 계속 진행돼요.',
      confirmText: '닫기',
    );
    _confirmingLeave = false;
    if (!confirmed || !mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(externalImportControllerProvider(widget.file), (previous, next) {
      if (next.phase != ExternalImportPhase.completed ||
          previous?.phase == ExternalImportPhase.completed) {
        return;
      }
      if (next.needsRefresh && next.message != null) {
        AppSnackBar.info(context, next.message!);
      }
      ref.read(mainShellTabIndexProvider.notifier).state = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        Navigator.of(
          context,
          rootNavigator: true,
        ).popUntil((route) => route.isFirst);
      });
    });
    final state = ref.watch(externalImportControllerProvider(widget.file));
    final isBusy =
        state.phase == ExternalImportPhase.analyzing ||
        state.phase == ExternalImportPhase.importing;
    return PopScope(
      canPop: state.phase != ExternalImportPhase.importing || _allowPop,
      onPopInvokedWithResult: (didPop, _) => _handlePopAttempt(didPop),
      child: AppLoadingOverlay(
        isLoading: isBusy,
        blockInteraction: false,
        child: Scaffold(
          backgroundColor: AppColors.of(context).pageBackground,
          appBar: AppBar(
            title: const AppBarTitle('다른 서비스 기록 가져오기'),
            backgroundColor: AppColors.of(context).pageBackground,
            foregroundColor: AppColors.of(context).textStrong,
          ),
          body: AbsorbPointer(
            absorbing: isBusy,
            child: _body(context, ref, state),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, ExternalImportState state) {
    switch (state.phase) {
      case ExternalImportPhase.analyzing:
        return const _CenteredMessage(
          icon: PhosphorIconsRegular.fileMagnifyingGlass,
          title: '파일을 확인하고 있어요',
          message: '기록 수에 따라 잠시 걸릴 수 있어요.',
        );
      case ExternalImportPhase.failed:
        return _CenteredMessage(
          icon: PhosphorIconsRegular.warningCircle,
          title: '파일을 가져올 수 없어요',
          message: state.message ?? '지원하지 않는 파일이에요.',
          actionLabel: '닫기',
          onAction: () => Navigator.of(context).pop(),
        );
      case ExternalImportPhase.completed:
        return const SizedBox.shrink();
      case ExternalImportPhase.ready:
      case ExternalImportPhase.importing:
        return _ImportPreview(
          state: state,
          importing: state.phase == ExternalImportPhase.importing,
          progress: state.progress,
          onToggle: (index) async {
            final alreadySelected = state.selectedBookIndexes.contains(index);
            final conflict = state.conflictingBookIndexes.contains(index);
            if (conflict && !alreadySelected && !_overwriteWarningConfirmed) {
              final confirmed = await AppConfirm.show(
                context,
                title: '기존 기록 덮어쓰기',
                message:
                    '같은 ISBN의 책이 이미 있어요. 선택하면 책 정보와 독서 '
                    '상태, 진행 페이지, 별점, 한줄평이 가져오는 기록으로 '
                    '바뀝니다. 난이도, 명작, 또 볼래요, 카테고리, 대출 정보 '
                    '등 북꾸러미에서 설정한 정보와 기존 메모·태그는 유지합니다.',
                confirmText: '덮어쓰기',
              );
              if (!confirmed || !context.mounted) return;
              _overwriteWarningConfirmed = true;
            }
            ref
                .read(externalImportControllerProvider(widget.file).notifier)
                .toggleBookSelection(index);
          },
          onImport: () async {
            final feedback = await ref
                .read(externalImportControllerProvider(widget.file).notifier)
                .startImport();
            if (feedback == null || !context.mounted) return;
            switch (feedback.type) {
              case ExternalImportFeedbackType.info:
                AppSnackBar.info(context, feedback.message);
              case ExternalImportFeedbackType.error:
                await AppAlert.show(
                  context,
                  title: '가져오지 못했어요',
                  message: feedback.message,
                );
            }
          },
        );
    }
  }
}

class _ImportPreview extends StatelessWidget {
  const _ImportPreview({
    required this.state,
    required this.importing,
    required this.progress,
    required this.onToggle,
    required this.onImport,
  });

  final ExternalImportState state;
  final bool importing;
  final ExternalImportProgress? progress;
  final Future<void> Function(int index) onToggle;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final result = state.result!;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '‘${result.source.label}’',
                        style: TextStyle(color: colors.accentForeground),
                      ),
                      const TextSpan(text: ' 기록을 찾았어요'),
                    ],
                  ),
                  style: TextStyle(color: colors.textStrong, fontSize: 20),
                ),
                if (result.source == ExternalImportSource.bookJuk) ...[
                  const SizedBox(height: 5),
                  Text(
                    'ISBN 정보가 없어 가져온 뒤 책 정보에서 ISBN 연동이 필요해요.',
                    style: TextStyle(color: colors.textBody, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  [
                    '책 ${result.books.length}권',
                    if (result.noteCount > 0) '메모 ${result.noteCount}개',
                    if (result.skippedItemCount > 0)
                      '제외 ${result.skippedItemCount}개',
                  ].join(' · '),
                  style: TextStyle(color: colors.textBody, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          sliver: DecoratedSliver(
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(14),
            ),
            sliver: SliverList.separated(
              itemCount: result.books.length,
              separatorBuilder: (context, _) => Divider(
                height: 1,
                thickness: 1,
                color: AppColors.of(context).border,
              ),
              itemBuilder: (context, index) {
                final book = result.books[index];
                return _BookSelectionTile(
                  book: book,
                  selected: state.selectedBookIndexes.contains(index),
                  conflict: state.conflictingBookIndexes.contains(index),
                  enabled: !importing,
                  onToggle: () => onToggle(index),
                );
              },
            ),
          ),
        ),
        if (importing && progress != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Column(
                children: [
                  LinearProgressIndicator(value: progress!.ratio),
                  const SizedBox(height: 6),
                  Text(
                    '${progress!.completed} / ${progress!.total}',
                    style: TextStyle(color: colors.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: ElevatedButton(
              onPressed: importing || state.selectedBookCount == 0
                  ? null
                  : onImport,
              child: Text('${state.selectedBookCount}권 가져오기'),
            ),
          ),
        ),
      ],
    );
  }
}

class _BookSelectionTile extends StatelessWidget {
  const _BookSelectionTile({
    required this.book,
    required this.selected,
    required this.conflict,
    required this.enabled,
    required this.onToggle,
  });

  final ExternalBookImportItem book;
  final bool selected;
  final bool conflict;
  final bool enabled;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final details = [
      book.author,
      book.publisher,
    ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');
    return MergeSemantics(
      child: InkWell(
        onTap: enabled ? onToggle : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: selected,
                  onChanged: enabled ? (_) => onToggle() : null,
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (conflict) ...[
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Icon(
                                  PhosphorIconsFill.warningCircle,
                                  size: 14,
                                  color: colors.error,
                                ),
                              ),
                              const SizedBox(width: 5),
                            ],
                            Expanded(
                              child: Text(
                                book.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.textStrong,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (details.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            details,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        if (book.notes.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          _CompactInfo(
                            icon: PhosphorIconsRegular.note,
                            label: '메모 ${book.notes.length}개',
                            color: colors.accentForeground,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactInfo extends StatelessWidget {
  const _CompactInfo({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: colors.accentForeground),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textStrong,
                fontSize: 21,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textBody),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
