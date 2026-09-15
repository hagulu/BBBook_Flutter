import 'dart:convert';
import 'dart:typed_data';

import 'package:bbbook/core/network/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// 계정 없이 쓰는 사용자의 서버 조회 규칙 테스트.
///
/// 세션 준비([ApiClient.configureAuth]의 `prepareSession`)는 계정이 없으면
/// 항상 실패한다. 그 실패가
/// - 인증이 필요 없는 공개 조회까지 막으면 완료 조건("공개 서버 콘텐츠 조회
///   가능")이 깨지고,
/// - 반대로 인증이 필요한 요청을 막지 못하면 익명 요청이 서버에서 401을 받아
///   인증 우회 시도가 된다.
///
/// 토큰이 있는 로그인 사용자에게는 공개 조회에도 토큰이 실려야 `isMine`/
/// `likedByMe`가 내 기준으로 내려온다(api-doc의 `Authorization ... (선택)`).
void main() {
  /// 계정이 없는 상태. 어떤 요청이든 세션을 준비할 수 없다.
  ApiClient withoutAccount(_CaptureAdapter adapter) {
    final client = ApiClient(baseUrl: 'https://example.test');
    client.dio.httpClientAdapter = adapter;
    client.configureAuth(
      readAccessToken: () => null,
      refreshAccessToken: () async =>
          throw DioException(requestOptions: RequestOptions()),
      onUnauthorized: () async {},
      prepareSession: () async => throw StateError('로그인이 필요한 기능입니다.'),
    );
    return client;
  }

  ApiClient loggedIn(_CaptureAdapter adapter) {
    final client = ApiClient(baseUrl: 'https://example.test');
    client.dio.httpClientAdapter = adapter;
    client.configureAuth(
      readAccessToken: () => 'test-token',
      refreshAccessToken: () async => 'test-token',
      onUnauthorized: () async {},
      prepareSession: () async {},
    );
    return client;
  }

  const publicGetPaths = <String>[
    '/api/books/categories',
    '/api/books/options',
    '/api/notices',
    '/api/notices/3',
    '/api/books',
    '/api/books/9781234567890',
    '/api/books/9781234567890/reviews',
    '/api/books/9781234567890/reflections',
    '/api/books/9781234567890/discussions',
    '/api/books/9781234567890/community-preview',
    '/api/books/9781234567890/community-counts',
    '/api/discussions/12',
    '/api/discussions/12/answers',
    '/api/reflections/34',
  ];

  for (final path in publicGetPaths) {
    test('계정이 없어도 공개 조회는 그대로 전송한다: $path', () async {
      final adapter = _CaptureAdapter();
      await withoutAccount(adapter).dio.get<dynamic>(path);

      expect(adapter.options?.path, path);
      expect(adapter.options?.headers.containsKey('Authorization'), isFalse);
    });
  }

  const authRequiredPaths = <String>[
    '/api/me/books',
    '/api/me/books/exists',
    '/api/me/profile',
    '/api/me/records',
  ];

  for (final path in authRequiredPaths) {
    test('계정이 없으면 인증이 필요한 요청은 보내지 않는다: $path', () async {
      final adapter = _CaptureAdapter();

      await expectLater(
        withoutAccount(adapter).dio.get<dynamic>(path),
        throwsA(isA<DioException>()),
      );
      expect(adapter.options, isNull);
    });
  }

  test('공개 조회라도 쓰기(POST)는 세션을 요구한다', () async {
    final adapter = _CaptureAdapter();

    await expectLater(
      withoutAccount(adapter).dio.post<dynamic>(
        '/api/books/9781234567890/reviews',
        data: const {'content': '좋아요'},
      ),
      throwsA(isA<DioException>()),
    );
    expect(adapter.options, isNull);
  });

  test('세션 준비가 실패하면 남은 토큰을 붙이지 않고 익명으로 보낸다', () async {
    // 로그아웃이 시작돼 상태가 비워지기 전(`_changingSession`) 공개 조회가
    // 나가는 창. 이전 계정 토큰이 실리면 isMine/likedByMe가 그 계정 기준으로
    // 내려와 로그아웃 후 캐시에 남는다.
    final adapter = _CaptureAdapter();
    final client = ApiClient(baseUrl: 'https://example.test');
    client.dio.httpClientAdapter = adapter;
    client.configureAuth(
      readAccessToken: () => 'stale-token',
      refreshAccessToken: () async => 'stale-token',
      onUnauthorized: () async {},
      prepareSession: () async => throw StateError('로그인 상태가 변경되었습니다.'),
    );

    await client.dio.get<dynamic>('/api/discussions/12');

    expect(adapter.options?.path, '/api/discussions/12');
    expect(adapter.options?.headers.containsKey('Authorization'), isFalse);
  });

  test('로그인 사용자의 공개 조회에는 토큰을 실어 보낸다', () async {
    final adapter = _CaptureAdapter();

    await loggedIn(adapter).dio.get<dynamic>('/api/discussions/12');

    expect(adapter.options?.headers['Authorization'], 'Bearer test-token');
  });

  test('사용자와 무관한 조회에는 토큰을 붙이지 않는다', () async {
    final adapter = _CaptureAdapter();
    final client = loggedIn(adapter);

    await client.dio.get<dynamic>('/api/books/categories');
    expect(adapter.options?.headers.containsKey('Authorization'), isFalse);

    await client.dio.get<dynamic>('/api/books/options');
    expect(adapter.options?.headers.containsKey('Authorization'), isFalse);

    await client.dio.get<dynamic>('/api/notices');
    expect(adapter.options?.headers.containsKey('Authorization'), isFalse);
  });
}

class _CaptureAdapter implements HttpClientAdapter {
  RequestOptions? options;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    this.options = options;
    return ResponseBody.fromString(
      jsonEncode(const {'success': true, 'data': <String, dynamic>{}}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
