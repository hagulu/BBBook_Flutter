import 'package:file_picker/file_picker.dart';

import '../models/external_import_models.dart';

class ExternalImportFilePicker {
  const ExternalImportFilePicker._();

  static Future<ExternalImportFileReference?> pick() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'bookmory'],
    );
    if (file == null) return null;
    final filePath = file.path;
    if (filePath == null || filePath.isEmpty) {
      throw const ExternalImportException(
        '선택한 파일을 읽을 수 없어요.',
        reason: 'picked_file_path_missing',
      );
    }
    return ExternalImportFileReference(path: filePath, displayName: file.name);
  }
}
