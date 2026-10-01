import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bbbook/core/network/api_client.dart';
import 'package:bbbook/core/network/api_exception.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('USER_SANCTIONED만 사용자 재조회 콜백을 호출하고 안내한다', () async {
    final client = ApiClient(baseUrl: 'https://example.test');
    client.dio.httpClientAdapter = _ForbiddenAdapter('USER_SANCTIONED');
    var refreshCount = 0;
    client.configureAuth(
      readAccessToken: () => 'token',
      refreshAccessToken: () async => 'token',
      onUnauthorized: () async {},
      onSanctioned: () async => refreshCount++,
      prepareSession: () async {},
    );

    DioException? caught;
    try {
      await client.dio.post<dynamic>('/api/books/123/reviews');
    } on DioException catch (e) {
      caught = e;
    }

    expect(refreshCount, 1);
    expect(caught, isNotNull);
    final mapped = ApiException.sanctionedFromDio(caught!);
    expect(mapped?.errorCode, 'USER_SANCTIONED');
    expect(mapped?.message, contains('징계 기간'));
    expect(mapped?.isAuthFailure, isFalse);
  });

  test('다른 403 오류는 징계 재조회를 호출하지 않는다', () async {
    final client = ApiClient(baseUrl: 'https://example.test');
    client.dio.httpClientAdapter = _ForbiddenAdapter('FORBIDDEN');
    var refreshCount = 0;
    client.configureAuth(
      readAccessToken: () => 'token',
      refreshAccessToken: () async => 'token',
      onUnauthorized: () async {},
      onSanctioned: () async => refreshCount++,
      prepareSession: () async {},
    );

    try {
      await client.dio.post<dynamic>('/api/books/123/reviews');
    } on DioException catch (e) {
      expect(ApiException.sanctionedFromDio(e), isNull);
    }
    expect(refreshCount, 0);
  });

  test('오류 처리 중 같은 클라이언트로 /api/users/me를 재조회할 수 있다', () async {
    final client = ApiClient(baseUrl: 'https://example.test');
    client.dio.httpClientAdapter = _SanctionThenMeAdapter();
    final refreshed = Completer<void>();
    client.configureAuth(
      readAccessToken: () => 'token',
      refreshAccessToken: () async => 'token',
      onUnauthorized: () async {},
      onSanctioned: () async {
        await client.dio.get<dynamic>('/api/users/me');
        refreshed.complete();
      },
      prepareSession: () async {},
    );

    await expectLater(
      client.dio.post<dynamic>('/api/books/123/reviews'),
      throwsA(isA<DioException>()),
    );
    await refreshed.future.timeout(const Duration(seconds: 2));
  });
}

class _ForbiddenAdapter implements HttpClientAdapter {
  _ForbiddenAdapter(this.errorCode);

  final String errorCode;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode({'success': false, 'errorCode': errorCode}),
    403,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

class _SanctionThenMeAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    options.path == '/api/users/me'
        ? jsonEncode({
            'success': true,
            'data': {'id': 1},
          })
        : jsonEncode({'success': false, 'errorCode': 'USER_SANCTIONED'}),
    options.path == '/api/users/me' ? 200 : 403,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}
