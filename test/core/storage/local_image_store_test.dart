import 'dart:io';

import 'package:bbbook/core/storage/local_image_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

/// 로컬 이미지 저장소의 서비스 로직 테스트(메모 사진·독후감 이미지가
/// 공유한다). 실제 앱 지원 디렉터리와 네트워크 대신 임시 디렉터리·가짜
/// 다운로더를 주입해 검증한다.
void main() {
  late Directory root;
  late List<String> downloadedUrls;
  late LocalImageStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('local_image_store');
    downloadedUrls = [];
    store = LocalImageStore(
      directoryName: 'memo_images',
      logLabel: '메모 사진',
      resolveRoot: () async => root,
      downloader: (url) async {
        downloadedUrls.add(url);
        return List<int>.filled(8, 1);
      },
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<File> createSource(String name, {int bytes = 16}) async {
    final file = File(path.join(root.path, name));
    await file.writeAsBytes(List<int>.filled(bytes, 7));
    return file;
  }

  group('saveSelected', () {
    test('고른 사진을 저장소로 복사하고 상대 경로를 돌려준다', () async {
      final source = await createSource('picked.jpg');

      final stored = await store.saveSelected(source.path);

      expect(path.dirname(stored), store.directoryName);
      final saved = await store.resolve(stored);
      expect(await saved!.exists(), isTrue);
      expect(await saved.length(), await source.length());
      // 원본(카메라 임시 파일)은 그대로 둔다.
      expect(await source.exists(), isTrue);
    });

    test('서버가 받지 않는 형식과 5MB 초과는 저장 단계에서 막는다', () async {
      final gif = await createSource('picked.gif');
      final tooLarge = await createSource(
        'large.jpg',
        bytes: LocalImageStore.maxBytes + 1,
      );

      await expectLater(
        store.saveSelected(gif.path),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(
        store.saveSelected(tooLarge.path),
        throwsA(isA<FileSystemException>()),
      );
      expect(await store.listFileNames(), isEmpty);
    });

    test('없는 파일을 고르면 예외로 알린다', () async {
      await expectLater(
        store.saveSelected(path.join(root.path, 'missing.jpg')),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('ensureDownloaded', () {
    test('서버 사진을 한 번만 내려받고 이후에는 로컬 파일을 재사용한다', () async {
      const url = 'https://cdn.example.com/notes/9/photo-a.jpg';

      final first = await store.ensureDownloaded(url);
      final second = await store.ensureDownloaded(url);

      expect(first.status, LocalImageDownloadStatus.stored);
      expect(second.localImagePath, first.localImagePath);
      expect(downloadedUrls, hasLength(1));
      expect(
        await (await store.resolve(first.localImagePath))!.exists(),
        isTrue,
      );
    });

    test('쿼리 문자열만 다른 같은 사진은 다시 내려받지 않는다', () async {
      const base = 'https://cdn.example.com/notes/9/photo-a.jpg';

      final first = await store.ensureDownloaded(base);
      final signed = await store.ensureDownloaded('$base?sig=abc&expires=1');

      expect(signed.localImagePath, first.localImagePath);
      expect(downloadedUrls, hasLength(1));
    });

    test('오프라인 등 일시적 실패는 재시도 대상으로 남긴다', () async {
      final failing = LocalImageStore(
        directoryName: 'memo_images',
        logLabel: '메모 사진',
        resolveRoot: () async => root,
        downloader: (_) async => throw const SocketException('offline'),
      );

      final result = await failing.ensureDownloaded(
        'https://cdn.example.com/notes/9/photo-b.jpg',
      );

      expect(result.status, LocalImageDownloadStatus.failed);
      expect(result.localImagePath, isNull);
      expect(await failing.listFileNames(), isEmpty);
    });

    test('서버가 없다고 답한 사진만 영구 실패로 구분한다', () async {
      LocalImageStore respondingWith(int statusCode) {
        final requestOptions = RequestOptions(path: '/notes/9/photo.jpg');
        return LocalImageStore(
          directoryName: 'memo_images',
          logLabel: '메모 사진',
          resolveRoot: () async => root,
          downloader: (_) async => throw DioException(
            requestOptions: requestOptions,
            response: Response<void>(
              requestOptions: requestOptions,
              statusCode: statusCode,
            ),
          ),
        );
      }

      final notFound = await respondingWith(
        404,
      ).ensureDownloaded('https://cdn.example.com/notes/9/photo-c.jpg');
      // 5xx는 곧 회복될 수 있으므로 계속 재시도한다.
      final serverError = await respondingWith(
        503,
      ).ensureDownloaded('https://cdn.example.com/notes/9/photo-d.jpg');

      expect(notFound.status, LocalImageDownloadStatus.unavailable);
      expect(serverError.status, LocalImageDownloadStatus.failed);
    });
  });

  group('경로 해석', () {
    test('마이그레이션 이전 절대 경로·file:// 값도 현재 디렉터리 기준으로 읽는다', () async {
      final stored = await store.saveSelected(
        (await createSource('a.png')).path,
      );
      final fileName = store.fileNameOf(stored)!;

      final legacyAbsolute = '/var/old/Application/ABC/memo_images/$fileName';
      final legacyUri = 'file:///var/old/memo_images/$fileName';

      expect(store.fileNameOf(legacyAbsolute), fileName);
      expect((await store.resolve(legacyUri))!.path, contains(root.path));
      expect(store.resolveSync(stored)!.path, contains(root.path));
    });

    test('서버 URL과 빈 값은 로컬 파일로 해석하지 않는다', () async {
      expect(store.fileNameOf('https://cdn.example.com/a.jpg'), isNull);
      expect(store.fileNameOf(null), isNull);
      expect(store.fileNameOf(''), isNull);
    });
  });

  group('삭제와 orphan 정리', () {
    test('교체 전후가 같은 파일이면 지우지 않는다', () async {
      final stored = await store.saveSelected(
        (await createSource('b.jpg')).path,
      );

      await store.delete(stored, except: stored);
      expect(await store.listFileNames(), hasLength(1));

      await store.delete(stored);
      expect(await store.listFileNames(), isEmpty);
    });

    test('참조되지 않는 오래된 파일만 지운다', () async {
      final referenced = await store.saveSelected(
        (await createSource('keep.jpg')).path,
      );
      final orphan = await store.saveSelected(
        (await createSource('drop.jpg')).path,
      );
      final justCopied = await store.saveSelected(
        (await createSource('fresh.jpg')).path,
      );
      // 방금 복사돼 아직 DB에 기록되지 않은 파일과 구분하기 위해 유예
      // 시간을 넘긴 것처럼 수정 시각을 되돌린다.
      final aged = DateTime.now().subtract(
        LocalImageStore.pruneGrace + const Duration(minutes: 1),
      );
      (await store.resolve(referenced))!.setLastModifiedSync(aged);
      (await store.resolve(orphan))!.setLastModifiedSync(aged);

      final removed = await store.pruneOrphans([referenced]);

      expect(removed, 1);
      final remaining = await store.listFileNames();
      expect(remaining, contains(store.fileNameOf(referenced)));
      expect(remaining, contains(store.fileNameOf(justCopied)));
      expect(remaining, isNot(contains(store.fileNameOf(orphan))));
    });

    test('clear는 사진 폴더를 통째로 비운다', () async {
      await store.saveSelected((await createSource('c.jpg')).path);

      await store.clear();

      expect(await store.listFileNames(), isEmpty);
    });
  });
}
