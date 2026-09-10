import 'dart:io';

import 'package:bbbook/features/external_record_import/models/external_import_models.dart';
import 'package:bbbook/features/external_record_import/services/external_import_file_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const analyzer = ExternalImportFileAnalyzer();

  test('csv 확장자여도 북적북적 핵심 헤더가 없으면 거부한다', () async {
    final directory = await Directory.systemTemp.createTemp('bbbook_csv_test_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/bookit_fake.csv');
    await file.writeAsString('title,author\nA,B');

    await expectLater(
      analyzer.analyze(
        ExternalImportFileReference(
          path: file.path,
          displayName: 'bookit_fake.csv',
        ),
      ),
      throwsA(
        isA<ExternalImportException>().having(
          (error) => error.reason,
          'reason',
          'csv_headers_not_supported',
        ),
      ),
    );
  });

  test('지원하지 않는 확장자는 내용과 무관하게 거부한다', () async {
    final directory = await Directory.systemTemp.createTemp('bbbook_txt_test_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/bookit.txt');
    await file.writeAsString('제목,저자,출판사,독서상태');

    await expectLater(
      analyzer.analyze(
        ExternalImportFileReference(path: file.path, displayName: 'bookit.txt'),
      ),
      throwsA(
        isA<ExternalImportException>().having(
          (error) => error.reason,
          'reason',
          'unsupported_extension',
        ),
      ),
    );
  });
}
