import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as path;

import '../data/book_juk_importer.dart';
import '../data/bookmory_importer.dart';
import '../data/finished_csv_importer.dart';
import '../models/external_import_models.dart';

class ExternalImportFileAnalyzer {
  const ExternalImportFileAnalyzer({
    this.bookJukImporter = const BookJukImporter(),
    this.bookmoryImporter = const BookmoryImporter(),
    this.finishedCsvImporter = const FinishedCsvImporter(),
  });

  static const maxCsvBytes = 64 * 1024 * 1024;

  final BookJukImporter bookJukImporter;
  final BookmoryImporter bookmoryImporter;
  final FinishedCsvImporter finishedCsvImporter;

  Future<ExternalImportParseResult> analyze(
    ExternalImportFileReference reference,
  ) async {
    if (reference.platformErrorMessage != null) {
      throw ExternalImportException(
        reference.platformErrorMessage!,
        reason: 'shared_file_copy_failed',
      );
    }
    final file = File(reference.path);
    if (!await file.exists()) {
      throw const ExternalImportException(
        '공유받은 파일을 찾지 못했어요. 다시 선택해 주세요.',
        reason: 'file_missing',
      );
    }
    final extension = path.extension(reference.displayName).toLowerCase();
    if (reference.expectedSource == ExternalImportSource.finishedCsv) {
      if (extension != '.csv') {
        throw const ExternalImportException(
          'CSV 파일만 가져올 수 있어요.',
          reason: 'unsupported_extension',
        );
      }
      final bytes = await _readCsvBytes(file);
      final importer = finishedCsvImporter;
      // 행이 많은 CSV도 파일 선택 직후 화면이 멈추지 않도록 파싱·행 검증은
      // 별도 isolate에서 한다.
      return Isolate.run(() => importer.parseBytes(bytes));
    }
    switch (extension) {
      case '.bookmory':
        return bookmoryImporter.parseFile(file);
      case '.csv':
        return bookJukImporter.parseBytes(await _readCsvBytes(file));
      default:
        throw const ExternalImportException(
          '지원하지 않는 파일이에요. CSV 또는 BOOKMORY 파일을 선택해 주세요.',
          reason: 'unsupported_extension',
        );
    }
  }

  Future<Uint8List> _readCsvBytes(File file) async {
    final length = await file.length();
    if (length <= 0 || length > maxCsvBytes) {
      throw const ExternalImportException(
        'CSV 파일 크기가 너무 크거나 비어 있어요.',
        reason: 'csv_file_size',
      );
    }
    return file.readAsBytes();
  }
}
