import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bbbook/core/network/api_client.dart';
import 'package:bbbook/features/book_detail/data/book_detail_api.dart';
import 'package:bbbook/features/book_record/data/book_record_api.dart';
import 'package:bbbook/features/book_search/data/book_search_api.dart';
import 'package:bbbook/features/bookshelf/data/bookshelf_api.dart';
import 'package:bbbook/features/bookshelf/data/bookshelf_dao.dart';
import 'package:bbbook/features/bookshelf/data/bookshelf_database.dart';
import 'package:bbbook/features/bookshelf/data/bookshelf_repository.dart';
import 'package:bbbook/features/bookshelf/models/book_item.dart';
import 'package:bbbook/features/bookshelf/models/book_status.dart';
import 'package:bbbook/features/bookshelf/models/user_book_create_result.dart';
import 'package:bbbook/features/record_sync/data/record_sync_api.dart';
import 'package:bbbook/features/tag/data/tag_api.dart';
import 'package:bbbook/features/tag/data/tag_dao.dart';
import 'package:bbbook/features/tag/data/tag_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// [TagRepository]의 로컬 우선 추가/삭제 → push 흐름 테스트.
///
/// `POST .../tags`/`DELETE .../tags/:id`가 dirty push를 어떻게 확정/유지
/// 하는지, 오프라인에서 생성 후 바로 삭제한 매핑이 네트워크 호출 없이
/// 정리되는지를 검증한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const tagDao = TagDao();
  const bookshelfDao = BookshelfDao();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final databaseDirectory = await Directory.systemTemp.createTemp(
      'bookshelf_tag_repo_test',
    );
    await databaseFactory.setDatabasesPath(databaseDirectory.path);
    final databasePath = path.join(databaseDirectory.path, 'bookshelf.db');
    await databaseFactory.deleteDatabase(databasePath);
    await BookshelfDatabase.instance();
  });

  setUp(() async {
    final db = await BookshelfDatabase.instance();
    await db.transaction((txn) async {
      await txn.delete('user_book_tag_map');
      await txn.delete('tag');
      await txn.delete('user_book');
      await txn.delete('sync_meta');
    });
  });

  Future<int> createSyncedBook({
    required String clientRequestId,
    required String isbn13,
    required int serverUserBookId,
  }) async {
    final now = DateTime.utc(2026, 9, 1);
    final local = await bookshelfDao.insertLocalCreate(
      BookItem(
        userBookId: 0,
        clientRequestId: clientRequestId,
        isbn13: isbn13,
        title: '태그 push 테스트 책',
        status: BookStatus.reading,
        currentPage: 0,
        isMasterpiece: false,
        rereadCount: 0,
        tags: const [],
        createdAt: now,
        updatedAt: now,
      ),
    );
    await bookshelfDao.confirmCreate(
      localId: local.userBookId,
      capturedUpdatedAt: local.updatedAt,
      response: UserBookCreateResult(
        userBookId: serverUserBookId,
        bookId: serverUserBookId,
        isbn13: isbn13,
        title: '서버 책',
        author: null,
        publisher: null,
        statsTotalPages: null,
        displayTotalPages: null,
        coverImageUrl: null,
        status: 'READING',
        created: false,
      ),
    );
    return local.userBookId;
  }

  TagRepository buildRepository(HttpClientAdapter adapter) {
    final client = ApiClient(baseUrl: 'https://example.test');
    client.dio.httpClientAdapter = adapter;
    final bookshelfRepository = BookshelfRepository(
      api: BookshelfApi(apiClient: client),
      recordApi: BookRecordApi(apiClient: client),
      bookDetailApi: BookDetailApi(apiClient: client),
      bookSearchApi: BookSearchApi(apiClient: client),
    );
    return TagRepository(
      api: TagApi(apiClient: client),
      recordSyncApi: RecordSyncApi(client),
      bookshelfRepository: bookshelfRepository,
      dao: tagDao,
    );
  }

  test('오프라인 추가는 즉시 로컬에 반영되고, 이후 push가 성공하면 dirty가 풀린다', () async {
    final userBookId = await createSyncedBook(
      clientRequestId: '30000000-0000-4000-8000-000000000001',
      isbn13: '9781000000001',
      serverUserBookId: 701,
    );
    final requests = <String>[];
    final repository = buildRepository(
      _RoutingAdapter(
        onPostTag: (path, data) {
          requests.add(path);
          return _jsonResponse(200, {'id': 5001, 'name': data['name']});
        },
      ),
    );

    await repository.addTag(userBookId: userBookId, name: '몰입');
    // addTag는 로컬 반영까지만 기다린다 — push는 백그라운드다.
    final mappingsRightAfter = await tagDao.getDirtyMappingLocalIds();
    expect(mappingsRightAfter, isNotEmpty);

    // pushMapping 체인이 끝날 때까지 명시적으로 기다린다(테스트 결정성용).
    await repository.pushAllDirty();

    expect(requests, ['/api/me/books/701/tags']);
    expect(await tagDao.getDirtyMappingLocalIds(), isEmpty);
    final mappingId = mappingsRightAfter.single;
    final mapping = await tagDao.getMappingByLocalId(mappingId);
    final tag = await tagDao.getTagByLocalId(mapping!.tagId);
    expect(tag!.serverId, 5001);
    expect(tag.name, '몰입');
  });

  test('한 번도 push되지 않은 태그를 오프라인에서 바로 삭제하면 네트워크 호출 없이 정리된다', () async {
    final userBookId = await createSyncedBook(
      clientRequestId: '30000000-0000-4000-8000-000000000002',
      isbn13: '9781000000002',
      serverUserBookId: 702,
    );
    var deleteCalled = false;
    var postCalled = false;
    final repository = buildRepository(
      _RoutingAdapter(
        onPostTag: (path, data) {
          postCalled = true;
          return _jsonResponse(200, {'id': 5002, 'name': data['name']});
        },
        onDeleteTag: (path) {
          deleteCalled = true;
          return _jsonResponse(200, {'data': null});
        },
      ),
    );

    final mappingId = await tagDao.addTagLocal(userBookId: userBookId, name: '충동');
    final tagLocalId = (await tagDao.getMappingByLocalId(mappingId))!.tagId;
    await repository.removeTag(userBookId: userBookId, tagLocalId: tagLocalId);
    await repository.pushAllDirty();

    expect(postCalled, isFalse, reason: '한 번도 push되지 않은 태그는 서버가 알 필요가 없다');
    expect(deleteCalled, isFalse);
    expect(await tagDao.getMappingByLocalId(mappingId), isNull);
  });

  test('이미 서버에 반영된 태그를 삭제하면 DELETE가 호출되고 성공 시 로컬에서 정리된다', () async {
    final userBookId = await createSyncedBook(
      clientRequestId: '30000000-0000-4000-8000-000000000003',
      isbn13: '9781000000003',
      serverUserBookId: 703,
    );
    final deletedPaths = <String>[];
    final repository = buildRepository(
      _RoutingAdapter(
        onPostTag: (path, data) => _jsonResponse(200, {
          'id': 5003,
          'name': data['name'],
        }),
        onDeleteTag: (path) {
          deletedPaths.add(path);
          return _jsonResponse(200, {'data': null});
        },
      ),
    );

    final mappingId = await tagDao.addTagLocal(userBookId: userBookId, name: '여운');
    await repository.pushAllDirty();
    final tagLocalId = (await tagDao.getMappingByLocalId(mappingId))!.tagId;
    expect((await tagDao.getTagByLocalId(tagLocalId))!.serverId, 5003);

    await repository.removeTag(userBookId: userBookId, tagLocalId: tagLocalId);
    await repository.pushAllDirty();

    expect(deletedPaths, ['/api/me/books/703/tags/5003']);
    expect(await tagDao.getMappingByLocalId(mappingId), isNull);
  });

  test('매핑 생성 push가 409를 받으면 dirty를 유지하고 예외 없이 넘어간다', () async {
    final userBookId = await createSyncedBook(
      clientRequestId: '30000000-0000-4000-8000-000000000004',
      isbn13: '9781000000004',
      serverUserBookId: 704,
    );
    final repository = buildRepository(
      _RoutingAdapter(
        onPostTag: (path, data) => _jsonResponse(409, {
          'success': false,
          'message': '이미 추가된 태그입니다.',
        }),
      ),
    );

    final mappingId = await tagDao.addTagLocal(userBookId: userBookId, name: '재도전');
    await repository.pushAllDirty();

    final mapping = await tagDao.getMappingByLocalId(mappingId);
    expect(mapping, isNotNull);
    expect(mapping!.isDirty, isTrue, reason: '정확한 서버 tagId는 곧 이어질 증분 동기화가 채운다');
  });
}

ResponseBody _jsonResponse(int statusCode, Map<String, dynamic> data) {
  final body = data.containsKey('success')
      ? data
      : {'success': true, 'data': data};
  return ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

typedef _PostHandler =
    ResponseBody Function(String path, Map<String, dynamic> data);
typedef _DeleteHandler = ResponseBody Function(String path);

class _RoutingAdapter implements HttpClientAdapter {
  _RoutingAdapter({this.onPostTag, this.onDeleteTag});

  final _PostHandler? onPostTag;
  final _DeleteHandler? onDeleteTag;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'POST' && options.path.contains('/tags')) {
      return onPostTag!(options.path, options.data as Map<String, dynamic>);
    }
    if (options.method == 'DELETE' && options.path.contains('/tags/')) {
      return onDeleteTag!(options.path);
    }
    throw StateError('Unexpected request: ${options.method} ${options.path}');
  }

  @override
  void close({bool force = false}) {}
}
