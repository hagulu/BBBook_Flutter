import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bbbook/core/network/api_client.dart';
import 'package:bbbook/core/network/api_exception.dart';
import 'package:bbbook/core/network/patch_field.dart';
import 'package:bbbook/features/book_detail/data/book_detail_api.dart';
import 'package:bbbook/features/book_record/data/book_record_api.dart';
import 'package:bbbook/features/book_record/data/book_record_repository.dart';
import 'package:bbbook/features/book_search/data/book_search_api.dart';
import 'package:bbbook/features/bookshelf/data/bookshelf_api.dart';
import 'package:bbbook/features/bookshelf/data/bookshelf_dao.dart';
import 'package:bbbook/features/bookshelf/data/bookshelf_database.dart';
import 'package:bbbook/features/bookshelf/data/bookshelf_repository.dart';
import 'package:bbbook/features/bookshelf/models/book_item.dart';
import 'package:bbbook/features/bookshelf/models/book_status.dart';
import 'package:bbbook/features/bookshelf/models/record_patch.dart';
import 'package:bbbook/features/record_sync/data/record_sync_api.dart';
import 'package:bbbook/features/tag/data/tag_api.dart';
import 'package:bbbook/features/tag/data/tag_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// [BookRecordRepository.updateSourceType]의 두 서버 API 조합 저장이
/// (1) 이 책의 기존 dirty push와 경합하지 않고 순서대로 실행되는지,
/// (2) 두 번째 요청(book-info)이 실패해도 이미 성공한 첫 번째 요청(기록
/// PATCH) 결과를 잃지 않는지 검증한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
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
      await txn.delete('user_book_tag_map');
      await txn.delete('tag');
      await txn.delete('user_book');
      await txn.delete('sync_meta');
    });
  });

  BookRecordRepository buildRepository(HttpClientAdapter adapter) {
    final client = ApiClient(baseUrl: 'https://example.test');
    client.dio.httpClientAdapter = adapter;
    final bookshelfRepository = BookshelfRepository(
      api: BookshelfApi(apiClient: client),
      recordApi: BookRecordApi(apiClient: client),
      bookDetailApi: BookDetailApi(apiClient: client),
      bookSearchApi: BookSearchApi(apiClient: client),
    );
    return BookRecordRepository(
      api: BookRecordApi(apiClient: client),
      bookshelfRepository: bookshelfRepository,
      tagRepository: TagRepository(
        api: TagApi(apiClient: client),
        recordSyncApi: RecordSyncApi(client),
        bookshelfRepository: bookshelfRepository,
      ),
    );
  }

  Future<void> seedSyncedBook({
    required int userBookId,
    required int currentPage,
    String sourceType = 'PAPER_BOOK',
  }) async {
    const dao = BookshelfDao();
    final now = DateTime.utc(2026, 9, 1);
    await dao.reconcile([
      BookItem(
        userBookId: userBookId,
        serverId: userBookId,
        title: '책',
        statsTotalPages: 300,
        status: BookStatus.reading,
        currentPage: currentPage,
        isMasterpiece: false,
        sourceType: sourceType,
        rereadCount: 0,
        tags: const [],
        createdAt: now,
        updatedAt: now,
      ),
    ], now);
  }

  test('book-info PATCH가 실패해도 이미 성공한 출처 변경은 로컬에 남는다', () async {
    await seedSyncedBook(userBookId: 501, currentPage: 120);
    final adapter = _RoutingAdapter(
      onRecordPatch: (data) => _jsonResponse(200, {
        'userBookId': 501,
        'title': '책',
        'statsTotalPages': 300,
        'displayTotalPages': null,
        'status': 'READING',
        'currentPage': 0,
        'isMasterpiece': false,
        'sourceType': 'EBOOK',
        'rereadCount': 0,
        'updatedAt': '2026-09-01T01:00:00Z',
      }),
      onBookInfoPatch: (data) => _jsonResponse(500, {
        'success': false,
        'message': '서버 오류',
      }),
    );
    final repository = buildRepository(adapter);

    final result = await repository.updateSourceType(
      501,
      sourceType: 'EBOOK',
      platformName: null,
      displayTotalPages: PatchField.value(400),
    );

    expect(result.error, isA<ApiException>());
    expect(result.error?.statusCode, 500);
    expect(result.item.sourceType, 'EBOOK');
    expect(result.item.currentPage, 0);

    // 화면 상태뿐 아니라 로컬 DB에도 첫 단계 결과가 그대로 남아야 한다 —
    // 두 번째 요청 실패로 이미 성공한 변경까지 사라지면 DB와 화면이
    // 어긋난다.
    final persisted = await const BookshelfDao().getById(501);
    expect(persisted?.sourceType, 'EBOOK');
    expect(persisted?.currentPage, 0);
  });

  test('이 책의 기존 dirty 편집을 먼저 push한 뒤에 출처 변경을 보낸다', () async {
    await seedSyncedBook(userBookId: 502, currentPage: 50, sourceType: 'EBOOK');
    const dao = BookshelfDao();
    final current = await dao.getById(502);
    // 오프라인에서 평점을 먼저 매겼다고 가정한다(아직 서버에 반영 못 함).
    final dirty = current!.copyWithRecord(
      const RecordPatch(myRating: PatchField.value(4.5)),
      updatedAt: DateTime.utc(2026, 9, 1, 0, 30),
    );
    await dao.applyLocalEdit(dirty, changedFields: {RecordPatch.fieldMyRating});
    expect((await dao.getDirtyRecord(502)) != null, isTrue);

    final callOrder = <String>[];
    final adapter = _RoutingAdapter(
      onRecordPatch: (data) {
        if (data.containsKey('myRating')) {
          callOrder.add('rating');
          return _jsonResponse(200, {
            'userBookId': 502,
            'title': '책',
            'statsTotalPages': 300,
            'displayTotalPages': null,
            'status': 'READING',
            'currentPage': 50,
            'isMasterpiece': false,
            'sourceType': 'EBOOK',
            'myRating': 4.5,
            'rereadCount': 0,
            'updatedAt': '2026-09-01T00:31:00Z',
          });
        }
        callOrder.add('sourceType');
        return _jsonResponse(200, {
          'userBookId': 502,
          'title': '책',
          'statsTotalPages': 300,
          'displayTotalPages': null,
          'status': 'READING',
          'currentPage': 0,
          'isMasterpiece': false,
          'sourceType': 'AUDIO_BOOK',
          'myRating': 4.5,
          'rereadCount': 0,
          'updatedAt': '2026-09-01T00:32:00Z',
        });
      },
      onBookInfoPatch: (data) {
        callOrder.add('bookInfo');
        return _jsonResponse(200, {
          'userBookId': 502,
          'title': '책',
          'statsTotalPages': 300,
          'displayTotalPages': null,
          'status': 'READING',
          'currentPage': 0,
          'isMasterpiece': false,
          'sourceType': 'AUDIO_BOOK',
          'myRating': 4.5,
          'rereadCount': 0,
          'updatedAt': '2026-09-01T00:33:00Z',
        });
      },
    );
    final repository = buildRepository(adapter);

    final result = await repository.updateSourceType(
      502,
      sourceType: 'AUDIO_BOOK',
      platformName: null,
      displayTotalPages: const PatchField.clear(),
    );

    expect(callOrder, ['rating', 'sourceType', 'bookInfo']);
    expect(result.error, isNull);
    expect(result.item.sourceType, 'AUDIO_BOOK');

    final persisted = await dao.getById(502);
    expect(persisted?.sourceType, 'AUDIO_BOOK');
    expect(persisted?.myRating, 4.5);
    expect(await dao.getDirtyRecord(502), isNull);
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

typedef _RouteHandler = ResponseBody Function(Map<String, dynamic> data);

class _RoutingAdapter implements HttpClientAdapter {
  _RoutingAdapter({required this.onRecordPatch, required this.onBookInfoPatch});

  final _RouteHandler onRecordPatch;
  final _RouteHandler onBookInfoPatch;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final data = options.data as Map<String, dynamic>;
    if (options.path.contains('/book-info')) {
      return onBookInfoPatch(data);
    }
    return onRecordPatch(data);
  }

  @override
  void close({bool force = false}) {}
}
