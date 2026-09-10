import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bbbook/features/bookshelf/models/book_status.dart';
import 'package:bbbook/features/external_record_import/data/book_juk_importer.dart';
import 'package:bbbook/features/external_record_import/models/external_import_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const importer = BookJukImporter();

  test('실제 북적북적 샘플의 책과 다중 행 메모를 분석한다', () async {
    final sample = Directory('docs/ex-reference')
        .listSync()
        .whereType<File>()
        .singleWhere((file) => file.path.split('/').last.startsWith('bookit_'));
    final result = importer.parseBytes(await sample.readAsBytes());

    expect(result.source, ExternalImportSource.bookJuk);
    expect(result.discoveredBookCount, 4);
    expect(result.books, hasLength(4));
    expect(result.skippedItemCount, 0);
    expect(result.books.map((book) => book.status), [
      BookStatus.finished,
      BookStatus.finished,
      BookStatus.reading,
      BookStatus.wantToRead,
    ]);
    final oldMan = result.books.singleWhere((book) => book.title == '노인과 바다');
    expect(oldMan.notes, hasLength(2));
    expect(oldMan.notes.last.content, contains('제품명 : 멀티 인덱스테이프'));
    expect(oldMan.notes.last.content, contains('\n전화번호'));
    expect(oldMan.finishedAt, DateTime(2026, 4, 21));
  });

  test('컬럼 순서와 무관하게 메모N을 숫자 순서로 가져온다', () {
    final custom = '''"메모3","독서상태","출판사","제목","저자","메모1"
"셋째","읽고 있는 책","출판","제목","저자","첫째\n둘째"
''';
    final result = importer.parseBytes(Uint8List.fromList(utf8.encode(custom)));
    expect(result.books.single.notes.map((note) => note.content), [
      '첫째\n둘째',
      '셋째',
    ]);
  });

  test('핵심 헤더가 없는 CSV를 북적북적으로 오인하지 않는다', () {
    expect(
      () => importer.parseBytes(
        Uint8List.fromList(utf8.encode('title,author\nA,B')),
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
}
