import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bbbook/core/network/api_client.dart';
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

/// 로컬 출처·책 정보 저장이 네트워크를 기다리지 않고, 부분 전송 실패에도
/// 최신 입력값과 미전송 변경을 유지하는지 검증한다.
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

  late BookshelfRepository syncRepository;

  BookRecordRepository buildRepository(HttpClientAdapter adapter) {
    final client = ApiClient(baseUrl: 'https://example.test');
    client.dio.httpClientAdapter = adapter;
    final bookshelfRepository = BookshelfRepository(
      api: BookshelfApi(apiClient: client),
      recordApi: BookRecordApi(apiClient: client),
      bookDetailApi: BookDetailApi(apiClient: client),
      bookSearchApi: BookSearchApi(apiClient: client),
    );
    syncRepository = bookshelfRepository;
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

  test('book-info PATCH가 실패해도 출처와 쪽수 모두 로컬에 남는다', () async {
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
      onBookInfoPatch: (data) =>
          _jsonResponse(500, {'success': false, 'message': '서버 오류'}),
    );
    final repository = buildRepository(adapter);

    final result = await repository.updateSourceType(
      501,
      sourceType: 'EBOOK',
      platformName: null,
      displayTotalPages: PatchField.value(400),
    );

    expect(result.error, isNull);
    expect(result.item.sourceType, 'EBOOK');
    expect(result.item.currentPage, 0);
    expect(result.item.displayTotalPages, 400);
    await syncRepository.pushDirtyRecord(501);

    // 화면 상태뿐 아니라 로컬 DB에도 첫 단계 결과가 그대로 남아야 한다 —
    // 두 번째 요청 실패로 이미 성공한 변경까지 사라지면 DB와 화면이
    // 어긋난다.
    final persisted = await const BookshelfDao().getById(501);
    expect(persisted?.sourceType, 'EBOOK');
    expect(persisted?.currentPage, 0);
    expect(persisted?.displayTotalPages, 400);
    expect(
      (await const BookshelfDao().getDirtyRecord(501))?.changedFields,
      contains(bookInfoDirtyField),
    );
  });

  test('이전 미전송 편집과 출처 변경을 함께 보내고 책 정보를 이어서 보낸다', () async {
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
        expect(data['myRating'], 4.5);
        expect(data['sourceType'], 'AUDIO_BOOK');
        expect(data['currentPage'], 0);
        callOrder.add('record');
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

    expect(result.error, isNull);
    expect(result.item.sourceType, 'AUDIO_BOOK');
    await syncRepository.pushDirtyRecord(502);
    expect(callOrder, ['record', 'bookInfo']);

    final persisted = await dao.getById(502);
    expect(persisted?.sourceType, 'AUDIO_BOOK');
    expect(persisted?.myRating, 4.5);
    expect(await dao.getDirtyRecord(502), isNull);
  });

  test('책 정보 저장은 서버 응답이 멈춰도 로컬 결과를 반환한다', () async {
    await seedSyncedBook(userBookId: 503, currentPage: 10);
    final response = Completer<ResponseBody>();
    final requested = Completer<void>();
    final repository = buildRepository(
      _RoutingAdapter(
        onRecordPatch: (_) => throw StateError('정보만 수정할 때 기록 PATCH는 불필요'),
        onBookInfoPatch: (_) {
          requested.complete();
          return response.future;
        },
      ),
    );
    final updated = await repository.updateBookInfo(
      503,
      title: '오프라인 수정',
      statsTotalPages: 400,
    );
    expect(updated.title, '오프라인 수정');
    expect((await const BookshelfDao().getById(503))?.title, '오프라인 수정');
    await requested.future;
    response.complete(
      _jsonResponse(503, {'success': false, 'message': '일시 오류'}),
    );
    await syncRepository.pushDirtyRecord(503);
    expect(
      (await const BookshelfDao().getDirtyRecord(503))?.item.title,
      '오프라인 수정',
    );
  });

  test('서버 삭제 실패와 관계없이 책은 로컬 목록에서 즉시 사라진다', () async {
    await seedSyncedBook(userBookId: 504, currentPage: 10);
    final repository = buildRepository(
      _RoutingAdapter(
        onRecordPatch: (_) => throw StateError('삭제 중 기록 PATCH 금지'),
        onBookInfoPatch: (_) => throw StateError('삭제 중 정보 PATCH 금지'),
      ),
    );
    await repository.deleteBook(504);
    expect(await const BookshelfDao().getById(504), isNull);
    await syncRepository.pushDirtyRecord(504);
    expect((await const BookshelfDao().pendingOperation(504)).deleted, isTrue);
    expect(await const BookshelfDao().getDirtyRecord(504), isNotNull);
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

typedef _RouteHandler =
    FutureOr<ResponseBody> Function(Map<String, dynamic> data);

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
    if (options.method == 'DELETE') {
      return _jsonResponse(503, {'success': false, 'message': '일시 오류'});
    }
    final data = options.data as Map<String, dynamic>;
    if (options.path.contains('/book-info')) {
      return onBookInfoPatch(data);
    }
    return onRecordPatch(data);
  }

  @override
  void close({bool force = false}) {}
}
