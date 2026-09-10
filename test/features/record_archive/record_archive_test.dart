import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' hide ArchiveException;
import 'package:bbbook/core/storage/local_image_store.dart';
import 'package:bbbook/features/bookshelf/data/bookshelf_database.dart';
import 'package:bbbook/features/bookshelf/data/bookshelf_dao.dart';
import 'package:bbbook/features/bookshelf/models/user_book_create_result.dart';
import 'package:bbbook/features/record_archive/data/record_archive_dao.dart';
import 'package:bbbook/features/record_archive/models/record_archive.dart';
import 'package:bbbook/features/record_archive/services/archive_html.dart';
import 'package:bbbook/features/record_archive/services/record_archive_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const date = '2026-09-10T01:00:00Z';
final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII=',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Database db;
  late Map<String, LocalImageStore> stores;
  late RecordArchiveService service;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    root = await Directory.systemTemp.createTemp('record_archive_test_');
    await databaseFactory.setDatabasesPath(root.path);
    db = await BookshelfDatabase.instance();
    stores = {
      for (final kind in ['memo', 'reflection', 'cover'])
        kind: LocalImageStore(
          directoryName: '${kind}_images',
          logLabel: '테스트',
          resolveRoot: () async => root,
          downloader: (_) async => throw const SocketException('offline'),
        ),
    };
    service = RecordArchiveService(
      stores: stores,
      temporaryDirectory: () async => root,
    );
  });
  Future<void> clear() async {
    for (final table in [
      'book_note_memo',
      'book_note',
      'book_reflection',
      'reflection_image_local',
      'user_book_tag_map',
      'tag',
      'user_book',
      'sync_meta',
      'book_category',
      'storage_mode',
    ]) {
      await db.delete(table);
    }
    for (final store in stores.values) {
      await store.clear();
    }
  }

  setUp(clear);
  tearDownAll(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  Future<void> seed() async {
    await db.insert('book_category', {
      'id': 23,
      'code': 'NOVEL',
      'name': '소설',
      'color_hex': '#ffffff',
      'sort_order': 0,
    });
    await db.insert('user_book', {
      'user_book_id': 101,
      'server_id': 201,
      'isbn13': '9781234567890',
      'title': '1984 / "책"',
      'author': '조지, 오웰',
      'publisher': '출판사',
      'category': '소설',
      'display_category_id': 23,
      'stats_total_pages': 300,
      'display_total_pages': 350,
      'status': 'READING',
      'current_page': 35,
      'my_rating': 4.5,
      'short_review': '첫 줄\n"두 번째", 줄',
      'is_masterpiece': 1,
      'want_to_reread': 1,
      'reread_count': 2,
      'difficulty': 'NORMAL',
      'source_type': 'PAPER_BOOK',
      'platform_name': '종이',
      'discovery_source': '친구',
      'started_at': date,
      'finished_at': null,
      'created_at': date,
      'updated_at': date,
    });
    await db.insert('tag', {
      'id': 9,
      'name': '고전',
      'created_at': date,
      'updated_at': date,
    });
    await db.insert('tag', {
      'id': 10,
      'name': '디스토피아',
      'created_at': date,
      'updated_at': date,
    });
    await db.insert('tag', {
      'id': 11,
      'name': '미연결 태그',
      'created_at': date,
      'updated_at': date,
    });
    for (final id in [9, 10]) {
      await db.insert('user_book_tag_map', {
        'id': id,
        'user_book_id': 101,
        'tag_id': id,
        'created_at': date,
        'updated_at': date,
      });
    }
    for (final id in [31, 32]) {
      await db.insert('book_note', {
        'id': id,
        'owner_user_id': 7,
        'user_book_id': 101,
        'title': '1장 / 메모',
        'created_at': date,
        'updated_at': date,
      });
    }
    final dir = await stores['memo']!.ensureDirectory();
    await File('${dir.path}/source.png').writeAsBytes(png);
    final refDir = await stores['reflection']!.ensureDirectory();
    await File('${refDir.path}/source.png').writeAsBytes(png);
    for (final entry in [
      (41, 'THOUGHT', 2),
      (42, 'QUOTE', 1),
      (43, 'SUMMARY', 0),
      (44, 'PHOTO', 3),
    ]) {
      await db.insert('book_note_memo', {
        'id': entry.$1,
        'note_id': 31,
        'memo_type': entry.$2,
        'content': '${entry.$2} ::hl[[강조]] <script>bad</script>',
        'start_page': 32,
        'end_page': 35,
        'sort_order': entry.$3,
        'is_important': 1,
        'local_image_path': entry.$2 == 'PHOTO'
            ? 'memo_images/source.png'
            : null,
        'created_at': date,
        'updated_at': date,
      });
    }
    await db.insert('book_reflection', {
      'id': 51,
      'owner_user_id': 7,
      'user_book_id': 101,
      'reflection_type': 'USER_WRITTEN',
      'title': '감시와 자유',
      'content_json': jsonEncode({
        'ops': [
          {
            'insert': '감시',
            'attributes': {'bold': true},
          },
          {
            'insert': '\n',
            'attributes': {'header': 2},
          },
          {'insert': '첫 항목'},
          {
            'insert': '\n',
            'attributes': {'list': 'ordered'},
          },
          {'insert': '인용문'},
          {
            'insert': '\n',
            'attributes': {'blockquote': true},
          },
          {
            'insert': {'image': 'reflection_images/source.png'},
          },
          {'insert': '\n'},
        ],
      }),
      'content_text': '감시\n첫 항목\n인용문',
      'is_public': 1,
      'created_at': date,
      'updated_at': date,
    });
  }

  Future<Uint8List> exported() async =>
      (await service.exportRecords(7)).file.readAsBytes();
  Map<String, dynamic> manifest(Uint8List bytes) =>
      jsonDecode(
            utf8.decode(
              ZipDecoder()
                  .decodeBytes(bytes)
                  .findFile('bookkureomi.json')!
                  .content,
            ),
          )
          as Map<String, dynamic>;
  Uint8List pack(
    Map<String, dynamic>? json, {
    Map<String, List<int>> files = const {},
  }) {
    final archive = Archive();
    if (json != null) {
      final bytes = utf8.encode(jsonEncode(json));
      archive.addFile(ArchiveFile('bookkureomi.json', bytes.length, bytes));
    }
    for (final e in files.entries) {
      archive.addFile(ArchiveFile(e.key, e.value.length, e.value));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  test('ZIP에 CSV, 노트 HTML, 독후감 서식과 공유 이미지 및 버전 DTO를 담는다', () async {
    await seed();
    final bytes = await exported();
    final archive = ZipDecoder().decodeBytes(bytes);
    final json = manifest(bytes);
    expect(json['backupVersion'], 1);
    expect(jsonEncode(json), isNot(contains('server_id')));
    expect(jsonEncode(json), isNot(contains('user_book_id')));
    expect(jsonEncode(json), isNot(contains('source.png')));
    final csv = utf8.decode(archive.findFile('books.csv')!.content);
    expect(archive.findFile('books.csv')!.content.take(3), [239, 187, 191]);
    expect(csv, contains('"고전|디스토피아"'));
    expect(csv, contains('"첫 줄\n""두 번째"", 줄"'));
    final notes = archive.files
        .where((f) => f.name.startsWith('notes/'))
        .toList();
    expect(notes, hasLength(2));
    expect(notes.any((f) => f.name.endsWith('(2).html')), isTrue);
    final html = utf8.decode(notes.first.content);
    expect(html.indexOf('책 내용'), lessThan(html.indexOf('발췌')));
    expect(html.indexOf('발췌'), lessThan(html.indexOf('내 생각')));
    expect(html, contains('32~35쪽'));
    expect(html, contains('<mark>강조</mark>'));
    expect(html, contains('&lt;script&gt;'));
    expect(html, contains('../../images/memo_'));
    final reflection = utf8.decode(
      archive.files
          .singleWhere((f) => f.name.startsWith('reflections/'))
          .content,
    );
    expect(reflection, contains('<strong>감시</strong>'));
    expect(reflection, contains('<ol>'));
    expect(reflection, contains('<blockquote'));
    expect(reflection, contains('../images/reflection_'));
    expect(
      archive.files.where((f) => f.name.startsWith('images/')),
      hasLength(2),
    );
    expect(() => RecordArchive.parse(jsonEncode(json)), returnsNormally);
  });

  for (final mode in ['local', 'server']) {
    test('$mode 모드: 새 ID/관계/서식/이미지 복원 및 같은 ZIP 재가져오기 멱등성', () async {
      await seed();
      final bytes = await exported();
      await clear();
      await db.insert('storage_mode', {
        'id': 1,
        'mode': mode,
        'updated_at': date,
      });
      await service.importRecords(bytes, 7);
      final books = await db.query('user_book');
      expect(books, hasLength(1));
      final book = books.single;
      expect(book['user_book_id'], isNegative);
      expect(book['server_id'], isNull);
      expect(book['is_dirty'], 1);
      expect(book['current_page'], 35);
      expect(
        (await const BookshelfDao().getDirtyRecord(
          book['user_book_id'] as int,
        ))!.changedFields,
        contains('wantToReread'),
      );
      final notes = await db.query('book_note');
      expect(notes, hasLength(2));
      expect(
        notes.every((n) => n['user_book_id'] == book['user_book_id']),
        isTrue,
      );
      final memos = await db.query('book_note_memo');
      expect(memos, hasLength(4));
      final photo = memos.singleWhere((m) => m['memo_type'] == 'PHOTO');
      final photoFile = await stores['memo']!.resolve(
        photo['local_image_path'] as String,
      );
      expect(await photoFile!.readAsBytes(), png);
      expect(photo['image_url'], isNull);
      final reflection = (await db.query('book_reflection')).single;
      expect(
        reflection['content_json'],
        contains('reflection_images/archive_'),
      );
      expect(reflection['content_json'], isNot(contains('images/reflection_')));
      expect(await db.query('tag'), hasLength(3));
      expect(await db.query('user_book_tag_map'), hasLength(2));
      final imageNames = await stores['reflection']!.listFileNames();
      await service.importRecords(bytes, 7);
      expect(await db.query('user_book'), hasLength(1));
      expect(await db.query('book_note'), hasLength(2));
      expect(await db.query('book_note_memo'), hasLength(4));
      expect(await db.query('book_reflection'), hasLength(1));
      expect(await stores['reflection']!.listFileNames(), imageNames);
    });
  }

  test('이미지 확보 실패는 내보내기를 중단하지 않고 JSON/HTML에서도 해당 참조를 제거한다', () async {
    await seed();
    await stores['memo']!.clear();
    await stores['reflection']!.clear();
    final result = await service.exportRecords(7);
    expect(result.missingImages, 2);
    final bytes = await result.file.readAsBytes();
    expect(jsonEncode(manifest(bytes)), isNot(contains('source.png')));
    await clear();
    await service.importRecords(bytes, 7);
    expect(await db.query('book_note_memo'), hasLength(4));
  });

  test('같은 ISBN은 기존 책에 연결하고 표지를 유지한다', () async {
    await seed();
    final bytes = await exported();
    await clear();
    await db.insert('user_book', {
      'user_book_id': 90,
      'server_id': 400,
      'isbn13': '9781234567890',
      'title': '기존',
      'cover_image_url': 'https://example.com/keep.png',
      'status': 'READING',
      'created_at': date,
      'updated_at': date,
    });
    await service.importRecords(bytes, 7);
    final book = (await db.query('user_book')).single;
    expect(book['user_book_id'], 90);
    expect(book['title'], '1984 / "책"');
    expect(book['cover_image_url'], 'https://example.com/keep.png');
    expect(
      (await db.query('book_note')).every((n) => n['user_book_id'] == 90),
      isTrue,
    );
  });

  test('DB 쓰기 실패 시 모든 행과 준비한 이미지 파일을 롤백한다', () async {
    await seed();
    final bytes = await exported();
    await clear();
    await db.execute(
      "CREATE TRIGGER reject_reflection BEFORE INSERT ON book_reflection BEGIN SELECT RAISE(ABORT, 'test'); END",
    );
    try {
      await expectLater(
        service.importRecords(bytes, 7),
        throwsA(isA<DatabaseException>()),
      );
      for (final table in [
        'user_book',
        'tag',
        'user_book_tag_map',
        'book_note',
        'book_note_memo',
        'book_reflection',
      ]) {
        expect(await db.query(table), isEmpty);
      }
      for (final store in stores.values) {
        expect(await store.listFileNames(), isEmpty);
      }
    } finally {
      await db.execute('DROP TRIGGER reject_reflection');
    }
  });

  test('JSON 없음, 미래 버전, 잘못된 관계와 ZIP 경로를 거부한다', () async {
    await expectLater(
      service.importRecords(pack(null), 7),
      throwsA(isA<ArchiveException>()),
    );
    await expectLater(
      service.importRecords(pack({'backupVersion': 99}), 7),
      throwsA(isA<ArchiveException>()),
    );
    await seed();
    final json = manifest(await exported());
    json['notes'][0]['bookId'] = 'missing';
    await expectLater(
      service.importRecords(pack(json), 7),
      throwsA(isA<ArchiveException>()),
    );
    await expectLater(
      service.importRecords(
        pack(
          null,
          files: {
            '../escape': [1],
          },
        ),
        7,
      ),
      throwsA(isA<ArchiveException>()),
    );
  });

  test('참조 이미지가 없는 ZIP은 DB 반영 전에 실패한다', () async {
    await seed();
    final json = manifest(await exported());
    await clear();
    await expectLater(
      service.importRecords(pack(json), 7),
      throwsA(isA<ArchiveException>()),
    );
    expect(await db.query('user_book'), isEmpty);
  });

  test('파일명 특수문자·긴 한글·예약어·대소문자 중복을 안전하게 처리한다', () {
    final names = ArchiveNames();
    expect(names.take(' /\\:*?"<>| '), isNot(contains('/')));
    expect(names.take('CON'), '_CON');
    expect(names.take('책'), '책');
    expect(names.take('책'), '책 (2)');
    expect(names.take('A'), 'A');
    expect(names.take('a'), 'a (2)');
    expect(names.take('가' * 500).runes.length, 60);
    expect(names.take('..'), '제목 없음');
  });

  test('레거시 Tiptap 제목·문단·강조·이미지를 HTML로 변환한다', () {
    final html = reflectionHtml({
      'type': 'doc',
      'content': [
        {
          'type': 'heading',
          'attrs': {'level': 2},
          'content': [
            {'type': 'text', 'text': '제목'},
          ],
        },
        {
          'type': 'paragraph',
          'content': [
            {
              'type': 'text',
              'text': '굵게',
              'marks': [
                {'type': 'bold'},
              ],
            },
          ],
        },
        {
          'type': 'image',
          'attrs': {'src': 'images/reflection_1.png'},
        },
      ],
    }, null);
    expect(html, contains('<h2'));
    expect(html, contains('<strong>굵게</strong>'));
    expect(html, contains('../images/reflection_1.png'));
  });

  test('표지 복원 후 CREATE 응답이 원래 책 정보와 후속 dirty 필드를 지우지 않는다', () async {
    await seed();
    final directory = await stores['cover']!.ensureDirectory();
    await File('${directory.path}/cover.png').writeAsBytes(png);
    await db.update('user_book', {
      'isbn13': null,
      'cover_image_url': 'cover_images/cover.png',
    });
    final bytes = await exported();
    await clear();
    await service.importRecords(bytes, 7);
    var book = (await db.query('user_book')).single;
    final cover = await stores['cover']!.resolve(
      book['cover_image_url'] as String,
    );
    expect(await cover!.readAsBytes(), png);
    expect(
      (await const BookshelfDao().getDirtyRecord(
        book['user_book_id'] as int,
      ))!.changedFields,
      contains(bookCoverDirtyField),
    );
    await const BookshelfDao().confirmCreate(
      localId: book['user_book_id'] as int,
      capturedUpdatedAt: DateTime.parse(book['updated_at'] as String),
      response: const UserBookCreateResult(
        userBookId: 600,
        bookId: null,
        isbn13: null,
        title: '서버 응답',
        author: null,
        publisher: null,
        statsTotalPages: 300,
        displayTotalPages: null,
        coverImageUrl: null,
        status: 'READING',
        created: true,
      ),
    );
    book = (await db.query('user_book')).single;
    expect(book['server_id'], 600);
    expect(book['is_dirty'], 1);
    expect(book['display_total_pages'], 350);
    expect(book['title'], '1984 / "책"');
    expect(book['cover_image_url'], contains('cover_images/archive_'));
  });

  test('로컬 사본이 없으면 기존 캐시를 우선 사용하고 서버 이미지도 확보한다', () async {
    await seed();
    final photo = (await db.query(
      'book_note_memo',
      where: "memo_type='PHOTO'",
    )).single;
    await db.update(
      'book_note_memo',
      {'local_image_path': null, 'image_url': 'https://example.com/photo.png'},
      where: 'id=?',
      whereArgs: [photo['id']],
    );
    var downloads = 0;
    final remoteStore = LocalImageStore(
      directoryName: 'remote_images',
      logLabel: '테스트',
      resolveRoot: () async => root,
      downloader: (_) async {
        downloads++;
        return png;
      },
    );
    final cache = File('${root.path}/cache.png');
    await cache.writeAsBytes(png);
    var cached = true;
    final remoteService = RecordArchiveService(
      stores: {...stores, 'memo': remoteStore},
      temporaryDirectory: () async => root,
      cachedImage: (_, _) async => cached ? cache : null,
    );
    expect((await remoteService.exportRecords(7)).missingImages, 0);
    expect(downloads, 0);
    cached = false;
    expect((await remoteService.exportRecords(7)).missingImages, 0);
    expect(downloads, 1);
    await remoteStore.clear();
  });

  test('이미지 복사 중 실패해도 앞서 복사한 파일을 정리하고 DB는 비워 둔다', () async {
    await seed();
    final bytes = await exported();
    await clear();
    final failedStore = LocalImageStore(
      directoryName: 'failed',
      logLabel: '테스트',
      resolveRoot: () async => throw const FileSystemException('test'),
    );
    final failedService = RecordArchiveService(
      stores: {...stores, 'reflection': failedStore},
    );
    await expectLater(
      failedService.importRecords(bytes, 7),
      throwsA(isA<FileSystemException>()),
    );
    expect(await db.query('user_book'), isEmpty);
    expect(await stores['memo']!.listFileNames(), isEmpty);
  });

  test('세션 변경 시 DB 가져오기를 시작하지 않는다', () async {
    await seed();
    final records = RecordArchive.parse(jsonEncode(manifest(await exported())));
    await clear();
    await expectLater(
      RecordArchiveDao().restore(records, 7, {}, sessionValid: () => false),
      throwsA(isA<ArchiveException>()),
    );
    expect(await db.query('user_book'), isEmpty);
  });
}
