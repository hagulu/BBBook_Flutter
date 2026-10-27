import 'package:bbbook/core/storage/local_image_store.dart';
import 'package:bbbook/features/storage_mode/services/local_storage_migration_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 서버 → 로컬 저장 이전의 순서와 중단 조건 테스트.
///
/// 이 서비스에서 틀리면 되돌릴 수 없는 사고가 난다 — 서버 기록을 먼저 지운
/// 뒤 중단되면 로컬 원본까지 다음 동기화가 지우고, 반대로 받지 못한
/// 이미지가 있는데 삭제까지 진행하면 그 이미지를 영영 잃는다.
void main() {
  test('최신 기록과 이미지를 받은 뒤 모드 전환 후 서버를 삭제한다', () async {
    final steps = _FakeSteps();
    final stages = <LocalStorageMigrationStage>[];
    final result = await LocalStorageMigrationService(
      steps,
    ).run(onProgress: (state) => stages.add(state.stage));
    expect(result.stage, LocalStorageMigrationStage.completed);
    expect(steps.calls, [
      'syncAllRecords',
      'applyLatestRecords',
      'downloadAllImages',
      'countMissingLocalImages',
      'switchToLocalMode',
      'deleteServerRecords',
      'markServerRecordsDeleted',
    ]);
    expect(stages.first, LocalStorageMigrationStage.syncingRecords);
  });

  test('최신 기록 수신 실패 후 거절하면 아무것도 바꾸지 않는다', () async {
    final steps = _FakeSteps(failOn: 'syncAllRecords');
    String? asked;
    final result = await LocalStorageMigrationService(steps).run(
      confirmProceed: (message) async {
        asked = message;
        return false;
      },
    );
    expect(asked, isNotNull);
    expect(result.stage, LocalStorageMigrationStage.idle);
    expect(steps.calls, ['syncAllRecords']);
  });

  test('최신 기록 수신 실패 후 승인하면 그대로 전환한다', () async {
    final steps = _FakeSteps(failOn: 'syncAllRecords');
    final result = await LocalStorageMigrationService(
      steps,
    ).run(confirmProceed: (_) async => true);
    expect(result.stage, LocalStorageMigrationStage.completed);
    expect(steps.calls, [
      'syncAllRecords',
      'downloadAllImages',
      'countMissingLocalImages',
      'switchToLocalMode',
      'deleteServerRecords',
      'markServerRecordsDeleted',
    ]);
  });

  test('받지 못한 이미지가 남았는데 거절하면 아무것도 바꾸지 않는다', () async {
    final steps = _FakeSteps(missingAfterDownload: 2);
    String? asked;
    final result = await LocalStorageMigrationService(steps).run(
      confirmProceed: (message) async {
        asked = message;
        return false;
      },
    );
    expect(asked, contains('2장'));
    expect(result.stage, LocalStorageMigrationStage.idle);
    expect(steps.calls, [
      'syncAllRecords',
      'applyLatestRecords',
      'downloadAllImages',
      'countMissingLocalImages',
    ]);
  });

  test('받지 못한 이미지가 남았어도 승인하면 그대로 전환한다', () async {
    final steps = _FakeSteps(missingAfterDownload: 2);
    final result = await LocalStorageMigrationService(
      steps,
    ).run(confirmProceed: (_) async => true);
    expect(result.stage, LocalStorageMigrationStage.completed);
    expect(steps.calls.last, 'markServerRecordsDeleted');
  });

  test('모드 전환 실패 시 서버를 삭제하지 않는다', () async {
    final steps = _FakeSteps(failOn: 'switchToLocalMode');
    final result = await LocalStorageMigrationService(steps).run();
    expect(result.stage, LocalStorageMigrationStage.failed);
    expect(steps.calls, [
      'syncAllRecords',
      'applyLatestRecords',
      'downloadAllImages',
      'countMissingLocalImages',
      'switchToLocalMode',
    ]);
  });

  test('서버 삭제 실패 시 정리 미완료로 남긴다', () async {
    final steps = _FakeSteps(failOn: 'deleteServerRecords');
    final result = await LocalStorageMigrationService(steps).run();
    expect(result.stage, LocalStorageMigrationStage.failed);
    expect(result.failureMessage, contains('서버 기록 정리'));
    expect(steps.calls, [
      'syncAllRecords',
      'applyLatestRecords',
      'downloadAllImages',
      'countMissingLocalImages',
      'switchToLocalMode',
      'deleteServerRecords',
    ]);
  });

  test('받은 기록의 exportedAt으로 서버를 정리한다', () async {
    final steps = _FakeSteps();
    await LocalStorageMigrationService(steps).run();
    expect(steps.switchedExportedAt, 'export-1');
    expect(steps.deletedWith, ['export-1']);
  });

  test('최신 기록 없이 승인하면 exportedAt 없이 정리한다', () async {
    final steps = _FakeSteps(failOn: 'syncAllRecords');
    await LocalStorageMigrationService(
      steps,
    ).run(confirmProceed: (_) async => true);
    expect(steps.deletedWith, [null]);
  });

  test('그 사이 바뀐 기록이 있으면 다시 받아 새 exportedAt으로 정리한다', () async {
    final steps = _FakeSteps(changedOnDelete: 1);
    final result = await LocalStorageMigrationService(steps).run();
    expect(result.stage, LocalStorageMigrationStage.completed);
    expect(steps.calls.sublist(5), [
      'deleteServerRecords',
      'applyLatestRecords',
      'downloadAllImages',
      'countMissingLocalImages',
      'updateExportedAt',
      'deleteServerRecords',
      'markServerRecordsDeleted',
    ]);
    expect(steps.deletedWith, ['export-1', 'export-2']);
    expect(steps.updatedExportedAt, 'export-2');
  });

  test('다시 받은 기록의 이미지 누락을 거절하면 정리 기준을 바꾸지 않는다', () async {
    // 전환 전에는 누락이 없고, 다시 받은 기록에서만 이미지가 빠진다.
    final steps = _FakeSteps(changedOnDelete: 1, missingByCall: [0, 1]);
    String? asked;
    final result = await LocalStorageMigrationService(steps).run(
      confirmProceed: (message) async {
        asked = message;
        return false;
      },
    );
    expect(asked, contains('1장'));
    expect(result.stage, LocalStorageMigrationStage.failed);
    expect(result.failureMessage, contains('서버 기록 정리'));
    expect(steps.calls, isNot(contains('updateExportedAt')));
    expect(steps.deletedWith, ['export-1']);
  });

  test('기록이 계속 바뀌면 지우지 않고 정리 미완료로 남긴다', () async {
    final steps = _FakeSteps(changedOnDelete: 10);
    final result = await LocalStorageMigrationService(steps).run();
    expect(result.stage, LocalStorageMigrationStage.failed);
    expect(result.failureMessage, contains('서버 기록을 정리하지 못했습니다'));
    expect(steps.deletedWith, ['export-1', 'export-2', 'export-3']);
    expect(steps.calls, isNot(contains('markServerRecordsDeleted')));
  });

  group('남은 서버 기록 정리 재시도', () {
    test('이미지를 이어 받은 뒤 남겨 둔 exportedAt으로 정리한다', () async {
      final steps = _FakeSteps(pending: 'export-saved');
      final result = await LocalStorageMigrationService(
        steps,
      ).retryServerCleanup();
      expect(result, ServerCleanupResult.cleaned);
      expect(steps.calls, [
        'downloadAllImages',
        'countMissingLocalImages',
        'deleteServerRecords',
        'markServerRecordsDeleted',
      ]);
      expect(steps.deletedWith, ['export-saved']);
    });

    test('받지 못한 이미지가 남으면 서버를 지우지 않는다', () async {
      final steps = _FakeSteps(missingAfterDownload: 2);
      final result = await LocalStorageMigrationService(
        steps,
      ).retryServerCleanup();
      expect(result, ServerCleanupResult.missingImages);
      expect(steps.deletedWith, isEmpty);
    });

    test('이미지 누락을 승인하면 다시 받지 않고 정리한다', () async {
      final steps = _FakeSteps(
        missingAfterDownload: 2,
        pending: 'export-saved',
      );
      final result = await LocalStorageMigrationService(
        steps,
      ).retryServerCleanup(ignoreMissingImages: true);
      expect(result, ServerCleanupResult.cleaned);
      expect(steps.calls, isNot(contains('downloadAllImages')));
      expect(steps.deletedWith, ['export-saved']);
    });

    test('바뀐 기록이 있으면 서버 값을 다시 반영하지 않고 알린다', () async {
      final steps = _FakeSteps(changedOnDelete: 1, pending: 'export-saved');
      final result = await LocalStorageMigrationService(
        steps,
      ).retryServerCleanup();
      expect(result, ServerCleanupResult.changedSinceExport);
      expect(steps.calls, isNot(contains('applyLatestRecords')));
      expect(steps.calls, isNot(contains('markServerRecordsDeleted')));
    });

    test('바뀐 기록까지 지우기로 승인하면 exportedAt 없이 정리한다', () async {
      final steps = _FakeSteps(pending: 'export-saved');
      final result = await LocalStorageMigrationService(steps)
          .retryServerCleanup(
            ignoreMissingImages: true,
            ignoreChangedRecords: true,
          );
      expect(result, ServerCleanupResult.cleaned);
      expect(steps.deletedWith, [null]);
    });
  });
}

class _FakeSteps implements LocalStorageMigrationSteps {
  _FakeSteps({
    this.failOn,
    this.missingAfterDownload = 0,
    this.missingByCall = const [],
    this.changedOnDelete = 0,
    this.pending,
  });

  final LocalImageSyncReport report = const LocalImageSyncReport(stored: 1);
  final int missingAfterDownload;

  /// [countMissingLocalImages]의 호출 순서별 반환값. 모자라면
  /// [missingAfterDownload]를 쓴다.
  final List<int> missingByCall;
  var _missingCalls = 0;
  final String? failOn;

  /// 처음 이 횟수만큼의 서버 정리를 "바뀐 기록 있음"으로 거절한다.
  int changedOnDelete;
  var _exportCount = 0;
  String? switchedExportedAt;
  String? updatedExportedAt;

  /// 남겨 둔 exportedAt([pendingExportedAt]).
  final String? pending;
  final deletedWith = <String?>[];
  final int progressSteps = 0;

  final calls = <String>[];

  void _record(String name) {
    calls.add(name);
    if (failOn == name) throw StateError('$name failed');
  }

  @override
  Future<void> syncAllRecords() async => _record('syncAllRecords');

  @override
  Future<String?> applyLatestRecords() async {
    _record('applyLatestRecords');
    return 'export-${++_exportCount}';
  }

  @override
  Future<LocalImageSyncReport> downloadAllImages(
    void Function(int done, int total) onProgress,
  ) async {
    _record('downloadAllImages');
    for (var done = 1; done <= progressSteps; done++) {
      onProgress(done, progressSteps);
    }
    return report;
  }

  @override
  Future<int> countMissingLocalImages() async {
    _record('countMissingLocalImages');
    final call = _missingCalls++;
    return call < missingByCall.length
        ? missingByCall[call]
        : missingAfterDownload;
  }

  @override
  Future<String?> pendingExportedAt() async => pending;

  @override
  Future<void> switchToLocalMode({required String? exportedAt}) async {
    _record('switchToLocalMode');
    switchedExportedAt = exportedAt;
  }

  @override
  Future<void> updateExportedAt(String? exportedAt) async {
    _record('updateExportedAt');
    updatedExportedAt = exportedAt;
  }

  @override
  Future<void> deleteServerRecords({required String? exportedAt}) async {
    deletedWith.add(exportedAt);
    _record('deleteServerRecords');
    if (changedOnDelete > 0) {
      changedOnDelete--;
      throw const ServerRecordsChangedException();
    }
  }

  @override
  Future<void> markServerRecordsDeleted() async =>
      _record('markServerRecordsDeleted');
}
