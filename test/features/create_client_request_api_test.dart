import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bbbook/core/network/api_client.dart';
import 'package:bbbook/features/book_detail/data/book_detail_api.dart';
import 'package:bbbook/features/book_note/data/book_note_api.dart';
import 'package:bbbook/features/book_note/models/book_note.dart';
import 'package:bbbook/features/book_search/data/book_search_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const clientRequestId = '22222222-2222-4222-8222-222222222222';

  test('선행 동기화가 멈춰도 대기 상한 후 원래 요청을 전송한다', () async {
    final adapter = _CaptureAdapter({'success': true, 'data': {}});
    final client = ApiClient(
      baseUrl: 'https://example.test',
      recordSyncWait: Duration.zero,
    );
    client.dio.httpClientAdapter = adapter;
    final sync = Completer<void>();
    client.prepareRecordSync = () => sync.future;
    await client.dio.get<dynamic>(
      '/api/me/books/exists',
      options: ApiClient.recordDependentOptions(),
    );
    expect(adapter.options?.path, '/api/me/books/exists');
    expect(sync.isCompleted, isFalse);
    sync.complete();
  });

  test('자동 재시도는 백오프를 지키고 명시적 재시도는 즉시 요청한다', () async {
    final adapter = _CaptureAdapter({'success': false})..statusCode = 503;
    final client = _client(adapter);
    var authRetryRequested = false;
    client.configureAuth(
      readAccessToken: () => null,
      refreshAccessToken: () async => null,
      onUnauthorized: () async {},
      onUserRetry: () => authRetryRequested = true,
    );
    await expectLater(
      client.dio.get<dynamic>('/api/me'),
      throwsA(isA<DioException>()),
    );
    adapter.statusCode = 200;
    await expectLater(
      client.dio.get<dynamic>('/api/me'),
      throwsA(isA<DioException>()),
    );
    expect(adapter.requestCount, 1);
    client.requestUserRetry();
    await client.dio.get<dynamic>('/api/me');
    expect(adapter.requestCount, 2);
    expect(authRetryRequested, isTrue);
  });

  test('기록 의존 요청은 인증과 선행 동기화가 끝난 뒤 전송한다', () async {
    final adapter = _CaptureAdapter({'success': true, 'data': {}});
    final client = _client(adapter);
    final order = <String>[];
    client.configureAuth(
      readAccessToken: () => 'test-token',
      refreshAccessToken: () async => 'test-token',
      onUnauthorized: () async {},
      prepareSession: () async => order.add('auth'),
    );
    client.prepareRecordSync = () async {
      expect(adapter.options, isNull);
      order.add('sync');
    };
    await client.dio.get<dynamic>(
      '/api/me/books/exists',
      options: ApiClient.recordDependentOptions(),
    );
    expect(order, ['auth', 'sync']);
    expect(adapter.options?.headers['Authorization'], 'Bearer test-token');
  });

  test('동기화 내부 요청은 다시 선행 동기화를 기다리지 않는다', () async {
    final adapter = _CaptureAdapter({'success': true, 'data': []});
    final client = _client(adapter);
    var syncCount = 0;
    client.prepareRecordSync = () async {
      syncCount++;
      await client.dio.get<dynamic>('/api/me/books/sync');
    };
    await client.dio.get<dynamic>(
      '/api/me/books/exists',
      options: ApiClient.recordDependentOptions(),
    );
    expect(syncCount, 1);
    expect(adapter.options?.path, '/api/me/books/exists');
  });

  test('선행 동기화 중 계정이 바뀌면 원래 요청을 전송하지 않는다', () async {
    final adapter = _CaptureAdapter({'success': true, 'data': {}});
    final client = _client(adapter);
    client.prepareRecordSync = () async => client.invalidateSession();
    await expectLater(
      client.dio.get<dynamic>(
        '/api/me/books/exists',
        options: ApiClient.recordDependentOptions(),
      ),
      throwsA(isA<DioException>()),
    );
    expect(adapter.options, isNull);
  });

  test('일반 책 CREATE JSON에 clientRequestId를 전달하고 created=false도 파싱한다', () async {
    final adapter = _CaptureAdapter(_bookResponse(created: false));
    final api = BookDetailApi(apiClient: _client(adapter));

    final result = await api.addToBookshelf(
      isbn13: '9781234567890',
      status: 'READING',
      clientRequestId: clientRequestId,
    );

    expect(adapter.options?.path, '/api/me/books');
    expect(
      adapter.options?.data,
      containsPair('clientRequestId', clientRequestId),
    );
    expect(result.userBookId, 91);
    expect(result.created, isFalse);
  });

  test('커스텀 책 CREATE의 JSON과 multipart data에 clientRequestId를 전달한다', () async {
    final jsonAdapter = _CaptureAdapter(_bookResponse(created: true));
    final jsonApi = BookSearchApi(apiClient: _client(jsonAdapter));
    await jsonApi.postCustomBook(
      title: '직접 등록',
      status: 'READING',
      clientRequestId: clientRequestId,
    );
    expect(
      jsonAdapter.options?.data,
      containsPair('clientRequestId', clientRequestId),
    );

    final tempDirectory = await Directory.systemTemp.createTemp(
      'bbbook-create-api-test-',
    );
    final thumbnail = File('${tempDirectory.path}/cover.jpg');
    await thumbnail.writeAsBytes(const [1, 2, 3]);
    addTearDown(() => tempDirectory.delete(recursive: true));

    final multipartAdapter = _CaptureAdapter(_bookResponse(created: false));
    final multipartApi = BookSearchApi(apiClient: _client(multipartAdapter));
    await multipartApi.postCustomBook(
      title: '직접 등록',
      thumbnailFile: thumbnail,
      status: 'READING',
      clientRequestId: clientRequestId,
    );
    expect(multipartAdapter.requestBody, contains('name="data"'));
    expect(multipartAdapter.requestBody, contains('"clientRequestId"'));
    expect(multipartAdapter.requestBody, contains(clientRequestId));
    expect(multipartAdapter.requestBody, contains('name="thumbnail"'));
  });

  test('일반 메모 CREATE JSON에 clientRequestId를 전달한다', () async {
    final adapter = _CaptureAdapter(_noteMemoResponse(memoType: 'SUMMARY'));
    final api = BookNoteApi(apiClient: _client(adapter));

    await api.postNoteMemo(
      userBookId: 91,
      noteId: 12,
      memoType: BookNoteMemoType.summary,
      startPage: 1,
      endPage: 2,
      content: '내용',
      isImportant: false,
      clientRequestId: clientRequestId,
    );

    expect(adapter.options?.path, '/api/me/books/91/notes/memos');
    expect(
      adapter.options?.data,
      containsPair('clientRequestId', clientRequestId),
    );
  });

  test('PHOTO 메모 CREATE multipart field에 clientRequestId를 전달한다', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'bbbook-photo-api-test-',
    );
    final photo = File('${tempDirectory.path}/photo.jpg');
    await photo.writeAsBytes(const [1, 2, 3]);
    addTearDown(() => tempDirectory.delete(recursive: true));

    final adapter = _CaptureAdapter(_noteMemoResponse(memoType: 'PHOTO'));
    final api = BookNoteApi(apiClient: _client(adapter));
    await api.postPhotoNoteMemo(
      userBookId: 91,
      noteId: null,
      startPage: null,
      endPage: null,
      content: '사진',
      isImportant: true,
      file: photo,
      clientRequestId: clientRequestId,
    );

    expect(adapter.options?.path, '/api/me/books/91/notes/memos/photo');
    expect(adapter.requestBody, contains('name="clientRequestId"'));
    expect(adapter.requestBody, contains(clientRequestId));
    expect(adapter.requestBody, contains('name="file"'));
  });
}

ApiClient _client(_CaptureAdapter adapter) {
  final client = ApiClient(baseUrl: 'https://example.test');
  client.dio.httpClientAdapter = adapter;
  return client;
}

Map<String, dynamic> _bookResponse({required bool created}) {
  return {
    'success': true,
    'data': {
      'userBookId': 91,
      'bookId': 7,
      'isbn13': '9781234567890',
      'title': '책',
      'author': '저자',
      'publisher': '출판사',
      'totalPages': 320,
      'coverImageUrl': null,
      'status': 'READING',
      'created': created,
    },
  };
}

Map<String, dynamic> _noteMemoResponse({required String memoType}) {
  return {
    'success': true,
    'data': {
      'id': 101,
      'noteId': 12,
      'memoType': memoType,
      'startPage': null,
      'endPage': null,
      'content': '내용',
      'imageUrl': memoType == 'PHOTO' ? 'https://example.com/photo.jpg' : null,
      'isImportant': false,
      'sortOrder': 0,
      'createdAt': '2026-08-19T00:00:00Z',
    },
  };
}

class _CaptureAdapter implements HttpClientAdapter {
  _CaptureAdapter(this.response);

  final Map<String, dynamic> response;
  int statusCode = 200;
  int requestCount = 0;
  RequestOptions? options;
  String requestBody = '';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    this.options = options;
    requestCount++;
    if (requestStream != null) {
      final bytes = await requestStream.fold<List<int>>(
        <int>[],
        (all, chunk) => all..addAll(chunk),
      );
      requestBody = latin1.decode(bytes);
    }
    return ResponseBody.fromString(
      jsonEncode(response),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
