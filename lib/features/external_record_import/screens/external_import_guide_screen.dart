import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_alert.dart';
import '../../../shared/widgets/app_bar_title.dart';
import '../../storage_mode/data/storage_mode_store.dart';
import '../../storage_mode/providers/storage_mode_providers.dart';
import '../models/external_import_models.dart';
import '../services/external_import_file_picker.dart';
import 'external_import_screen.dart';

/// 다른 독서 서비스 기록 가져오기 안내 화면. 지원 서비스별 파일 형식과
/// 가져오는 기록을 보여주고, 파일을 고르면 분석 화면([ExternalImportScreen])으로 넘긴다.
class ExternalImportGuideScreen extends ConsumerWidget {
  const ExternalImportGuideScreen({super.key});

  Future<void> _pickFile(BuildContext context) async {
    try {
      final file = await ExternalImportFilePicker.pick();
      if (file == null || !context.mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => ExternalImportScreen(file: file)),
      );
    } on ExternalImportException catch (error) {
      developer.log('[외부 파일 선택] result=FAIL reason=${error.reason}');
      if (!context.mounted) return;
      await AppAlert.show(
        context,
        title: '파일을 열 수 없어요',
        message: error.userMessage,
      );
    } catch (_) {
      developer.log('[외부 파일 선택] result=FAIL reason=platform_error');
      if (!context.mounted) return;
      await AppAlert.show(
        context,
        title: '파일을 열 수 없어요',
        message: '파일 선택을 완료하지 못했어요. 다시 시도해 주세요.',
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    // 가져오기는 서버 Import 세션을 쓰므로 동기화가 꺼져 있으면 파일 선택·분석
    // 전에 막는다. 실행 시점의 저장 모드 검사(startImport)는 그대로 유지한다.
    final syncOff =
        ref.watch(storageModeProvider).valueOrNull == StorageMode.local;
    return Scaffold(
      backgroundColor: colors.pageBackground,
      appBar: AppBar(
        title: const AppBarTitle('다른 서비스 기록 가져오기'),
        backgroundColor: colors.pageBackground,
        foregroundColor: colors.textStrong,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            '각 앱에서 내보낸 파일을 선택해 주세요.',
            style: TextStyle(
              color: colors.textStrong,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '앱의 내보내기 기능으로 받은 파일만 가져올 수 있어요.',
            style: TextStyle(color: colors.textMuted, fontSize: 13),
          ),
          if (syncOff) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surfaceSubtle,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      PhosphorIconsRegular.warningCircle,
                      size: 16,
                      color: colors.error,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '동기화가 꺼져 있어 가져올 수 없어요. 설정에서 기록 동기화를 켜 주세요.',
                      style: TextStyle(color: colors.textBody, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: syncOff ? null : () => _pickFile(context),
            icon: const Icon(PhosphorIconsRegular.folderOpen, size: 18),
            label: const Text('파일 선택'),
          ),
          const SizedBox(height: 20),
          for (final source in ExternalImportSource.values) ...[
            _SourceCard(source: source),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  PhosphorIconsRegular.info,
                  size: 15,
                  color: colors.textMuted,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '각 앱의 업데이트에 따라 일시적으로 가져오지 못할 수 있어요.',
                  style: TextStyle(color: colors.textMuted, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({required this.source});

  final ExternalImportSource source;

  String get _fileExtension => switch (source) {
    ExternalImportSource.bookJuk => '.csv',
    ExternalImportSource.bookmory => '.bookmory',
  };

  /// 각 파서(`BookJukImporter`/`BookmoryImporter`)가 실제로 읽는 필드 기준.
  List<({String label, String detail})> get _importedFields => switch (source) {
    ExternalImportSource.bookJuk => const [
      (label: '책 정보', detail: '제목, 저자, 출판사'),
      (label: '독서 기록', detail: '독서 상태, 시작일, 완독일'),
      (label: '메모', detail: '메모 전체(요약 메모로 저장)'),
    ],
    ExternalImportSource.bookmory => const [
      (label: '책 정보', detail: '제목, 저자·번역자, 출판사, ISBN, 표지, 책 형태'),
      (label: '독서 기록', detail: '독서 상태, 시작일, 완독일, 읽은 쪽수, 완독 횟수'),
      (label: '평가', detail: '마지막 완독의 별점, 한줄평'),
      (label: '메모', detail: '요약·발췌·생각 메모와 쪽수'),
    ],
  };

  String get _excludedFields => switch (source) {
    ExternalImportSource.bookJuk => 'ISBN, 표지, 쪽수, 별점, 태그',
    ExternalImportSource.bookmory => '태그',
  };

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  source.label,
                  style: TextStyle(
                    color: colors.textStrong,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: colors.accentSurface,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  _fileExtension,
                  style: TextStyle(
                    color: colors.accentForeground,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final field in _importedFields)
            _FieldRow(label: field.label, detail: field.detail),
          _FieldRow(label: '제외', detail: _excludedFields, muted: true),
        ],
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.label,
    required this.detail,
    this.muted = false,
  });

  final String label;
  final String detail;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text.rich(
        TextSpan(
          text: label,
          style: TextStyle(
            color: muted ? colors.textMuted : colors.textStrong,
            fontWeight: FontWeight.w600,
          ),
          children: [
            TextSpan(
              text: ' ($detail)',
              style: TextStyle(
                color: colors.textMuted,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        style: const TextStyle(fontSize: 13, height: 1.4),
      ),
    );
  }
}
