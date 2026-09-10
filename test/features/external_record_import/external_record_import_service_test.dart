import 'package:bbbook/features/bookshelf/models/book_status.dart';
import 'package:bbbook/features/external_record_import/models/external_import_models.dart';
import 'package:bbbook/features/external_record_import/providers/external_import_providers.dart';
import 'package:bbbook/features/external_record_import/services/external_record_import_service.dart';
import 'package:bbbook/features/server_storage_migration/models/record_import_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ExternalImportParseResult input() => const ExternalImportParseResult(
    source: ExternalImportSource.bookJuk,
    discoveredBookCount: 1,
    skippedItemCount: 0,
    warningCount: 0,
    books: [
      ExternalBookImportItem(
        source: ExternalImportSource.bookJuk,
        sourceBookId: '1',
        title: '책',
        status: BookStatus.finished,
        currentPage: 0,
        rereadCount: 1,
        notes: [],
        tags: [],
      ),
    ],
  );

  test('기존 Import 세션의 start/items/complete 순서로 저장한다', () async {
    final gateway = _FakeGateway();
    final progress = <ExternalImportProgress>[];
    await ExternalRecordImportService(
      api: gateway,
    ).run(input(), onProgress: progress.add);

    expect(gateway.calls, ['start', 'items:1', 'complete:1']);
    expect(gateway.completedCounts?.bookCount, 1);
    expect(progress.last.ratio, 1);
  });

  test('남아 있는 미완료 세션은 취소하고 새 세션으로 시작한다', () async {
    final gateway = _FakeGateway(firstImportedCount: 2);
    await ExternalRecordImportService(api: gateway).run(input());

    expect(gateway.calls, [
      'start',
      'cancel:1',
      'start',
      'items:2',
      'complete:2',
    ]);
  });

  test('업로드 실패 시 세션 취소를 시도하고 사용자 오류로 변환한다', () async {
    final gateway = _FakeGateway(failUpload: true);
    await expectLater(
      () => ExternalRecordImportService(api: gateway).run(input()),
      throwsA(isA<ExternalImportException>()),
    );
    expect(gateway.calls, ['start', 'items:1', 'cancel:1']);
  });

  test('실행 잠금은 한 가져오기만 허용하고 소유자만 해제할 수 있다', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final lock = container.read(externalImportExecutionLockProvider.notifier);
    final first = Object();
    final second = Object();

    expect(lock.tryAcquire(userId: 10, owner: first), isTrue);
    expect(container.read(externalImportExecutionLockProvider), 10);
    expect(lock.tryAcquire(userId: 10, owner: second), isFalse);

    lock.release(second);
    expect(container.read(externalImportExecutionLockProvider), 10);
    lock.release(first);
    expect(container.read(externalImportExecutionLockProvider), isNull);
    expect(lock.tryAcquire(userId: 10, owner: second), isTrue);
  });
}

class _FakeGateway implements ExternalRecordImportGateway {
  _FakeGateway({this.firstImportedCount = 0, this.failUpload = false});

  final int firstImportedCount;
  final bool failUpload;
  final List<String> calls = [];
  RecordImportCounts? completedCounts;
  var starts = 0;

  @override
  Future<RecordImportSession> start() async {
    starts++;
    calls.add('start');
    return RecordImportSession(
      importId: starts,
      status: 'IN_PROGRESS',
      importedCount: starts == 1 ? firstImportedCount : 0,
      maxChunkItemCount: 500,
      createdAt: DateTime.utc(2026, 9, 10),
    );
  }

  @override
  Future<RecordImportChunkResult> uploadItems(
    int importId,
    Map<String, dynamic> payload,
  ) async {
    calls.add('items:$importId');
    if (failUpload) {
      throw const RecordImportException(
        'failed',
        kind: RecordImportFailureKind.requestFailed,
      );
    }
    return RecordImportChunkResult(
      books: const [],
      notes: const [],
      noteMemos: const [],
      reflections: const [],
      tags: const [],
      tagMaps: const [],
      importedCount: (payload['books'] as List<dynamic>).length,
    );
  }

  @override
  Future<void> complete(int importId, RecordImportCounts counts) async {
    calls.add('complete:$importId');
    completedCounts = counts;
  }

  @override
  Future<void> cancel(int importId) async {
    calls.add('cancel:$importId');
  }
}
