import 'dart:convert';
import 'dart:typed_data';

import 'dart:io';

import 'package:bbbook/core/network/api_client.dart';
import 'package:bbbook/core/network/api_exception.dart';
import 'package:bbbook/features/book_detail/data/book_detail_api.dart';
import 'package:bbbook/features/book_note/data/book_note_dao.dart';
import 'package:bbbook/features/book_note/models/book_note.dart';
import 'package:bbbook/features/book_record/data/book_record_api.dart';
import 'package:bbbook/features/book_search/data/book_search_api.dart';
import 'package:bbbook/features/bookshelf/data/bookshelf_api.dart';
import 'package:bbbook/features/bookshelf/data/bookshelf_dao.dart';
import 'package:bbbook/features/bookshelf/data/bookshelf_database.dart';
import 'package:bbbook/features/bookshelf/data/bookshelf_repository.dart';
import 'package:bbbook/features/bookshelf/models/book_item.dart';
import 'package:bbbook/features/bookshelf/models/book_status.dart';
import 'package:bbbook/features/bookshelf/models/user_book_create_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:dio/dio.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // 테스트 파일은 병렬 실행되므로 파일마다 별도 DB 경로를 쓴다(같은
    // `bookshelf.db`를 공유하면 서로의 setUp이 남의 데이터를 지운다).
    final databaseDirectory = await Directory.systemTemp.createTemp(
      'bookshelf_test',
    );
    await databaseFactory.setDatabasesPath(databaseDirectory.path);
    final databasePath = path.join(databaseDirectory.path, 'bookshelf.db');
    await databaseFactory.deleteDatabase(databasePath);
    await BookshelfDatabase.instance();
  });

  setUp(() async {
    final db = await BookshelfDatabase.instance();
    await db.transaction((txn) async {
      await txn.delete('book_note_memo');
      await txn.delete('book_note');
      await txn.delete('user_book_tag_map');
      await txn.delete('tag');
      await txn.delete('user_book');
      await txn.delete('sync_meta');
    });
  });

  test('user_book CREATE UUID와 로컬 PK를 응답 재처리까지 보존한다', () async {
    const dao = BookshelfDao();
    const clientRequestId = '11111111-1111-4111-8111-111111111111';
    final now = DateTime.utc(2026, 8, 19);

    final local = await dao.insertLocalCreate(
      BookItem(
        userBookId: 0,
        clientRequestId: clientRequestId,
        isbn13: '9781234567890',
        title: '로컬 책',
        status: BookStatus.reading,
        currentPage: 0,
        isMasterpiece: false,
        rereadCount: 0,
        tags: const [],
        createdAt: now,
        updatedAt: now,
      ),
    );

    expect(local.userBookId, isNegative);
    expect(local.serverId, isNull);
    expect(local.clientRequestId, clientRequestId);
    final firstRetry = await dao.getDirtyRecord(local.userBookId);
    final secondRetry = await dao.getDirtyRecord(local.userBookId);
    expect(firstRetry?.item.clientRequestId, clientRequestId);
    expect(secondRetry?.item.clientRequestId, clientRequestId);

    await dao.confirmCreate(
      localId: local.userBookId,
      capturedUpdatedAt: local.updatedAt,
      response: const UserBookCreateResult(
        userBookId: 91,
        bookId: 7,
        isbn13: '9781234567890',
        title: '서버 책',
        author: '저자',
        publisher: '출판사',
        statsTotalPages: 320,
        displayTotalPages: null,
        coverImageUrl: 'https://example.com/cover.jpg',
        status: 'READING',
        created: false,
      ),
    );

    final confirmed = await dao.getById(local.userBookId);
    expect(confirmed?.userBookId, local.userBookId);
    expect(confirmed?.serverId, 91);
    expect(confirmed?.clientRequestId, clientRequestId);
    expect(confirmed?.title, '서버 책');
    expect(await dao.getDirtyRecord(local.userBookId), isNull);
  });

  test('일반/PHOTO 메모는 로컬 생성 UUID를 dirty 재조회 후에도 유지한다', () async {
    const dao = BookNoteDao();
    final note = await dao.createNote(
      ownerUserId: 3,
      userBookId: 10,
      title: null,
    );
    final summary = await dao.createNoteMemo(
      ownerUserId: 3,
      userBookId: 10,
      noteId: note.id,
      draft: const BookNoteMemoDraft(
        type: BookNoteMemoType.summary,
        content: '요약',
      ),
      localImagePath: null,
    );
    final photo = await dao.createNoteMemo(
      ownerUserId: 3,
      userBookId: 10,
      noteId: note.id,
      draft: const BookNoteMemoDraft(
        type: BookNoteMemoType.photo,
        content: '사진',
      ),
      localImagePath: 'memo_images/photo.jpg',
    );

    expect(summary.clientRequestId, matches(_uuidPattern));
    expect(photo.clientRequestId, matches(_uuidPattern));
    expect(photo.clientRequestId, isNot(summary.clientRequestId));

    final firstRetry = await dao.getDirtyMemosForNote(note.id);
    final secondRetry = await dao.getDirtyMemosForNote(note.id);
    expect(
      firstRetry.map((memo) => memo.clientRequestId),
      secondRetry.map((memo) => memo.clientRequestId),
    );

    await dao.confirmNoteMemoSynced(
      localId: summary.id,
      serverId: 101,
      capturedUpdatedAt: summary.updatedAt,
      memoType: summary.type,
      startPage: summary.startPage,
      endPage: summary.endPage,
      content: summary.content,
      imageUrl: null,
      isImportant: summary.isImportant,
      sortOrder: 0,
    );
    await dao.confirmNoteMemoSynced(
      localId: photo.id,
      serverId: 102,
      capturedUpdatedAt: photo.updatedAt,
      memoType: photo.type,
      startPage: photo.startPage,
      endPage: photo.endPage,
      content: photo.content,
      imageUrl: 'https://example.com/photo.jpg',
      isImportant: photo.isImportant,
      sortOrder: 1,
    );

    final detail = await dao.findDetail(
      ownerUserId: 3,
      userBookId: 10,
      noteId: note.id,
    );
    final confirmedByLocalId = {
      for (final memo in detail!.memos) memo.id: memo,
    };
    expect(
      confirmedByLocalId[summary.id]?.clientRequestId,
      summary.clientRequestId,
    );
    expect(confirmedByLocalId[summary.id]?.serverId, 101);
    expect(
      confirmedByLocalId[photo.id]?.clientRequestId,
      photo.clientRequestId,
    );
    expect(confirmedByLocalId[photo.id]?.serverId, 102);
    expect(await dao.getDirtyMemosForNote(note.id), isEmpty);
  });

  test('user_book CREATE 응답 유실 재시도는 DB에 저장된 같은 UUID를 전송한다', () async {
    final adapter = _RetryCreateAdapter();
    var now = DateTime.utc(2026, 9, 8);
    final client = ApiClient(baseUrl: 'https://example.test', now: () => now);
    client.dio.httpClientAdapter = adapter;
    final repository = BookshelfRepository(
      api: BookshelfApi(apiClient: client),
      recordApi: BookRecordApi(apiClient: client),
      bookDetailApi: BookDetailApi(apiClient: client),
      bookSearchApi: BookSearchApi(apiClient: client),
    );

    final local = await repository.createIsbnBook(
      isbn13: '9781234567890',
      title: '재시도 책',
      status: BookStatus.reading,
    );
    await repository.runSerializedForBook(local.userBookId, () async {});
    // 재시도 제한 중에는 추가 요청이 나가지 않는다.
    await repository.pushDirtyRecord(local.userBookId);
    expect(adapter.clientRequestIds, hasLength(1));
    now = now.add(const Duration(seconds: 16));
    await repository.pushDirtyRecord(local.userBookId);

    expect(adapter.clientRequestIds, hasLength(2));
    expect(adapter.clientRequestIds[0], local.clientRequestId);
    expect(adapter.clientRequestIds[1], local.clientRequestId);
    final confirmed = await repository.getById(local.userBookId);
    expect(confirmed?.serverId, 91);
    expect(confirmed?.clientRequestId, local.clientRequestId);
  });

  test('CREATE 확정 후 오래된 로컬 객체를 upsert해도 server_id를 보존한다', () async {
    const dao = BookshelfDao();
    final now = DateTime.utc(2026, 8, 19);
    final local = await dao.insertLocalCreate(
      BookItem(
        userBookId: 0,
        clientRequestId: '33333333-3333-4333-8333-333333333333',
        isbn13: '9781111111111',
        title: '로컬 제목',
        status: BookStatus.reading,
        currentPage: 0,
        isMasterpiece: false,
        rereadCount: 0,
        tags: const [],
        createdAt: now,
        updatedAt: now,
      ),
    );
    await dao.confirmCreate(
      localId: local.userBookId,
      capturedUpdatedAt: local.updatedAt,
      response: const UserBookCreateResult(
        userBookId: 92,
        bookId: 8,
        isbn13: '9781111111111',
        title: '서버 제목',
        author: null,
        publisher: null,
        statsTotalPages: null,
        displayTotalPages: null,
        coverImageUrl: null,
        status: 'READING',
        created: true,
      ),
    );

    await dao.upsertOne(
      local.copyWithTags(
        const [],
        updatedAt: now.add(const Duration(seconds: 1)),
      ),
    );

    expect((await dao.getById(local.userBookId))?.serverId, 92);
  });

  test('서버가 CREATE를 거부해도 이미 저장 완료한 로컬 기록은 보존한다', () async {
    final client = ApiClient(baseUrl: 'https://example.test');
    final adapter = _ErrorCreateAdapter(statusCode: 404);
    client.dio.httpClientAdapter = adapter;
    final repository = BookshelfRepository(
      api: BookshelfApi(apiClient: client),
      recordApi: BookRecordApi(apiClient: client),
      bookDetailApi: BookDetailApi(apiClient: client),
      bookSearchApi: BookSearchApi(apiClient: client),
    );

    final local = await repository.createIsbnBook(
      isbn13: '9782222222222',
      title: '없는 책',
      status: BookStatus.reading,
    );
    await repository.pushDirtyRecord(local.userBookId);
    expect(adapter.requestCount, 1);
    expect(await const BookshelfDao().hasRetryableChanges(), isFalse);
    await const BookshelfDao().resetRetryDelays();
    await repository.pushDirtyRecord(local.userBookId);
    expect(adapter.requestCount, 2);
    expect(await const BookshelfDao().getByIsbn13('9782222222222'), isNotNull);
    expect(
      await const BookshelfDao().getDirtyRecord(local.userBookId),
      isNotNull,
    );
  });

  test('CREATE 응답 유실 후 삭제하면 동일 UUID로 복구한 서버 책까지 삭제한다', () async {
    var now = DateTime.utc(2026, 9, 8);
    final adapter = _RetryCreateAdapter();
    final client = ApiClient(baseUrl: 'https://example.test', now: () => now);
    client.dio.httpClientAdapter = adapter;
    final repository = BookshelfRepository(
      api: BookshelfApi(apiClient: client),
      recordApi: BookRecordApi(apiClient: client),
      bookDetailApi: BookDetailApi(apiClient: client),
      bookSearchApi: BookSearchApi(apiClient: client),
    );
    final local = await repository.createIsbnBook(
      isbn13: '9781234567890',
      title: '삭제할 책',
      status: BookStatus.reading,
    );
    await repository.runSerializedForBook(local.userBookId, () async {});
    await const BookshelfDao().deleteOne(
      local.userBookId,
      queueServerDelete: true,
    );
    now = now.add(const Duration(seconds: 16));
    await repository.pushDirtyRecord(local.userBookId);
    expect(adapter.clientRequestIds, [
      local.clientRequestId,
      local.clientRequestId,
    ]);
    expect(adapter.deletedPaths, ['/api/me/books/91']);
    expect(await repository.getById(local.userBookId), isNull);
    expect(await const BookshelfDao().getDirtyRecord(local.userBookId), isNull);
  });

  test('이미 로컬에 있는 ISBN은 요청 상태를 무시하지 않고 409로 알린다', () async {
    const dao = BookshelfDao();
    final now = DateTime.utc(2026, 8, 19);
    await dao.insertLocalCreate(
      BookItem(
        userBookId: 0,
        clientRequestId: '44444444-4444-4444-8444-444444444444',
        isbn13: '9783333333333',
        title: '기존 책',
        status: BookStatus.reading,
        currentPage: 0,
        isMasterpiece: false,
        rereadCount: 0,
        tags: const [],
        createdAt: now,
        updatedAt: now,
      ),
    );
    final client = ApiClient(baseUrl: 'https://example.test');
    client.dio.httpClientAdapter = _ErrorCreateAdapter(statusCode: 500);
    final repository = BookshelfRepository(
      api: BookshelfApi(apiClient: client),
      recordApi: BookRecordApi(apiClient: client),
      bookDetailApi: BookDetailApi(apiClient: client),
      bookSearchApi: BookSearchApi(apiClient: client),
    );

    await expectLater(
      repository.createIsbnBook(
        isbn13: '9783333333333',
        title: '기존 책',
        status: BookStatus.finished,
      ),
      throwsA(
        isA<ApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          409,
        ),
      ),
    );
    expect(
      (await dao.getByIsbn13('9783333333333'))?.status,
      BookStatus.reading,
    );
  });
}

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

class _RetryCreateAdapter implements HttpClientAdapter {
  final List<String?> clientRequestIds = [];
  final List<String> deletedPaths = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'DELETE') {
      deletedPaths.add(options.path);
      return ResponseBody.fromString(
        '{"success":true}',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    final data = options.data as Map<String, dynamic>;
    clientRequestIds.add(data['clientRequestId'] as String?);
    if (clientRequestIds.length == 1) {
      return ResponseBody.fromString(
        jsonEncode({'success': false, 'message': 'response_lost'}),
        503,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode({
        'success': true,
        'data': {
          'userBookId': 91,
          'bookId': 7,
          'isbn13': '9781234567890',
          'title': '재시도 책',
          'author': null,
          'publisher': null,
          'statsTotalPages': null,
          'displayTotalPages': null,
          'coverImageUrl': null,
          'status': 'READING',
          'created': false,
        },
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _ErrorCreateAdapter implements HttpClientAdapter {
  _ErrorCreateAdapter({required this.statusCode});

  final int statusCode;
  int requestCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestCount++;
    return ResponseBody.fromString(
      jsonEncode({'success': false, 'message': '책을 찾을 수 없습니다.'}),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
