import 'dart:io';

import 'package:path/path.dart' as path;

import '../data/book_juk_importer.dart';
import '../data/bookmory_importer.dart';
import '../models/external_import_models.dart';

class ExternalImportFileAnalyzer {
  const ExternalImportFileAnalyzer({
    this.bookJukImporter = const BookJukImporter(),
    this.bookmoryImporter = const BookmoryImporter(),
  });

  static const maxCsvBytes = 64 * 1024 * 1024;

  final BookJukImporter bookJukImporter;
  final BookmoryImporter bookmoryImporter;

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
    switch (extension) {
      case '.bookmory':
        return bookmoryImporter.parseFile(file);
      case '.csv':
        final length = await file.length();
        if (length <= 0 || length > maxCsvBytes) {
          throw const ExternalImportException(
            'CSV 파일 크기가 너무 크거나 비어 있어요.',
            reason: 'csv_file_size',
          );
        }
        return bookJukImporter.parseBytes(await file.readAsBytes());
      default:
        throw const ExternalImportException(
          '지원하지 않는 파일이에요. CSV 또는 BOOKMORY 파일을 선택해 주세요.',
          reason: 'unsupported_extension',
        );
    }
  }
}
