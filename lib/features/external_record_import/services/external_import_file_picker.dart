import 'package:file_picker/file_picker.dart';

import '../models/external_import_models.dart';

class ExternalImportFilePicker {
  const ExternalImportFilePicker._();

  static Future<ExternalImportFileReference?> pick() async {
    final file = await FilePicker.pickFile(
      // Android 문서 선택기는 비표준 확장자(bookmory)를 MIME 타입으로
      // 변환하지 못해 custom 필터 사용 시 정상 파일도 비활성화한다. 파일은
      // 모두 선택할 수 있게 열고, 선택 직후 analyzer가 확장자와 내부 형식을
      // 검증한다.
      type: FileType.any,
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
