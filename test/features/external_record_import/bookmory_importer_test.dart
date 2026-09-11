import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:bbbook/features/bookshelf/models/book_status.dart';
import 'package:bbbook/features/external_record_import/data/bookmory_importer.dart';
import 'package:bbbook/features/external_record_import/models/external_import_models.dart';
import 'package:bbbook/features/external_record_import/services/external_import_snapshot_builder.dart';
import 'package:bbbook/features/server_storage_migration/data/record_import_validation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  const importer = BookmoryImporter();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('실제 북모리 샘플의 SQLite 책, 재독, 평가, 메모를 분석한다', () async {
    final sample = Directory('docs/ex-reference')
        .listSync()
        .whereType<File>()
        .singleWhere((file) => file.path.endsWith('.bookmory'));
    final result = await importer.parseFile(sample);

    expect(result.source, ExternalImportSource.bookmory);
    expect(result.discoveredBookCount, 3);
    expect(result.books, hasLength(3));
    expect(result.noteCount, 3);
    expect(result.books.expand((book) => book.tags), isEmpty);

    final littlePrince = result.books.singleWhere(
      (book) => book.title == '어린 왕자',
    );
    expect(littlePrince.status, BookStatus.reading);
    expect(littlePrince.currentPage, 72);
    expect(littlePrince.totalPages, 148);
    expect(littlePrince.rereadCount, 1);
    expect(littlePrince.rating, 3.5);
    expect(littlePrince.shortReview, '좋읔책');
    expect(littlePrince.finishedAt, isNotNull);

    final frankenstein = result.books.singleWhere(
      (book) => book.title == '프랑켄슈타인',
    );
    expect(frankenstein.notes.map((note) => note.type).toSet(), {
      ExternalNoteType.summary,
      ExternalNoteType.quote,
      ExternalNoteType.thought,
    });
    expect(frankenstein.notes.first.content, '- 좋았서');
    expect(frankenstein.notes.first.startPage, 15);
    expect(frankenstein.notes.first.endPage, 15);

    final snapshot = const ExternalImportSnapshotBuilder().build(result);
    expect(snapshot.tags, isEmpty);
    expect(snapshot.tagMaps, isEmpty);
    expect(
      validateRecordImportSnapshot(
        books: snapshot.books,
        notes: snapshot.notes,
        memos: snapshot.noteMemos,
        reflections: snapshot.reflections,
        tags: snapshot.tags,
        tagMaps: snapshot.tagMaps,
      ),
      isNull,
    );
  });

  test('Quill Delta의 줄바꿈과 목록 내용을 plain text로 보존한다', () {
    const delta =
        '[{"insert":"첫째"},{"insert":"\\n","attributes":{"list":"bullet"}},'
        '{"insert":"둘째\\n셋째\\n"}]';
    expect(BookmoryImporter.quillDeltaToPlainText(delta), '- 첫째\n둘째\n셋째');
  });

  test('Zip Slip 경로가 포함된 파일을 거부한다', () async {
    final archive = Archive()
      ..add(ArchiveFile.bytes('../new_bookmory.db', [1, 2, 3]));
    final bytes = ZipEncoder().encode(archive);
    expect(
      () => importer.parseBytes(Uint8List.fromList(bytes)),
      throwsA(
        isA<ExternalImportException>().having(
          (error) => error.reason,
          'reason',
          'bookmory_unsafe_path',
        ),
      ),
    );
  });

  test('new_bookmory.db가 없는 ZIP을 거부한다', () async {
    final archive = Archive()
      ..add(ArchiveFile.string('shared_preferences.json', '{}'));
    final bytes = ZipEncoder().encode(archive);
    expect(
      () => importer.parseBytes(Uint8List.fromList(bytes)),
      throwsA(
        isA<ExternalImportException>().having(
          (error) => error.reason,
          'reason',
          'bookmory_database_missing',
        ),
      ),
    );
  });
}
