import 'package:bbbook/core/storage/local_image_store.dart';
import 'package:bbbook/features/storage_mode/services/local_storage_migration_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 서버 → 로컬 저장 이전의 순서와 중단 조건 테스트.
///
/// 이 서비스에서 틀리면 되돌릴 수 없는 사고가 난다 — 서버 기록을 먼저 지운
/// 뒤 중단되면 로컬 원본까지 다음 동기화가 지우고, 반대로 받지 못한
/// 이미지가 있는데 삭제까지 진행하면 그 이미지를 영영 잃는다.
void main() {
  test('검증까지 통과하면 모드 전환을 먼저 기록한 뒤 서버 기록을 지운다', () async {
    final steps = _FakeSteps();

    final result = await LocalStorageMigrationService(steps).run();

    expect(result.stage, LocalStorageMigrationStage.completed);
    expect(steps.calls, [
      'syncAllRecords',
      'downloadAllImages',
      'countMissingLocalImages',
      // 모드 기록이 서버 삭제보다 반드시 앞에 온다. 순서가 바뀌면 삭제 직후
      // 중단됐을 때 다음 동기화가 로컬 기록까지 지운다.
      'switchToLocalMode',
      'deleteServerRecords',
      'markServerRecordsDeleted',
    ]);
  });

  test('받지 못한 이미지가 남아 있으면 서버 데이터를 건드리지 않는다', () async {
    final steps = _FakeSteps(
      report: const LocalImageSyncReport(stored: 3, failed: 2),
      missingAfterDownload: 2,
    );

    final result = await LocalStorageMigrationService(steps).run();

    expect(result.stage, LocalStorageMigrationStage.failed);
    expect(result.failureMessage, contains('2장'));
    expect(steps.calls, isNot(contains('switchToLocalMode')));
    expect(steps.calls, isNot(contains('deleteServerRecords')));
  });

  test('서버에서 더 이상 받을 수 없는 이미지는 이전을 막지 않는다', () async {
    // 404 등으로 사라진 이미지는 서버를 남겨 둬도 되찾을 수 없으므로,
    // 안내만 하고 이전을 마친다.
    final steps = _FakeSteps(
      report: const LocalImageSyncReport(stored: 4, unavailable: 1),
    );

    final result = await LocalStorageMigrationService(steps).run();

    expect(result.stage, LocalStorageMigrationStage.completed);
    expect(result.unavailableImages, 1);
    expect(steps.calls, contains('deleteServerRecords'));
  });

  test('기록 동기화가 실패하면 이미지도 받지 않고 중단한다', () async {
    final steps = _FakeSteps(failOn: 'syncAllRecords');

    final result = await LocalStorageMigrationService(steps).run();

    expect(result.stage, LocalStorageMigrationStage.failed);
    expect(steps.calls, ['syncAllRecords']);
  });

  test('서버 삭제가 실패해도 이미 전환한 모드는 되돌리지 않고 정리 미완료로 남긴다', () async {
    // 로컬이 원본이 된 뒤이므로 서버 삭제만 다시 시도하면 된다. 완료 표시를
    // 남기지 않아야 프로필에서 재시도 진입점이 보인다.
    final steps = _FakeSteps(failOn: 'deleteServerRecords');

    final result = await LocalStorageMigrationService(steps).run();

    expect(result.stage, LocalStorageMigrationStage.failed);
    expect(steps.calls, contains('switchToLocalMode'));
    expect(steps.calls, isNot(contains('markServerRecordsDeleted')));
    // 전환 전 실패와 구분되는 안내여야 한다.
    expect(result.failureMessage, contains('서버 기록 정리'));
  });

  test('진행 단계와 이미지 진행률을 순서대로 알린다', () async {
    final steps = _FakeSteps(progressSteps: 2);
    final stages = <LocalStorageMigrationStage>[];
    final progresses = <String>[];

    await LocalStorageMigrationService(steps).run(
      onProgress: (state) {
        if (stages.isEmpty || stages.last != state.stage) {
          stages.add(state.stage);
        }
        final progress = '${state.imagesDone}/${state.imagesTotal}';
        if (state.imagesTotal > 0 &&
            (progresses.isEmpty || progresses.last != progress)) {
          progresses.add(progress);
        }
      },
    );

    expect(stages, [
      LocalStorageMigrationStage.syncingRecords,
      LocalStorageMigrationStage.downloadingImages,
      LocalStorageMigrationStage.verifying,
      LocalStorageMigrationStage.switchingMode,
      LocalStorageMigrationStage.completed,
    ]);
    expect(progresses, ['1/2', '2/2']);
  });
}

class _FakeSteps implements LocalStorageMigrationSteps {
  _FakeSteps({
    this.report = const LocalImageSyncReport(stored: 1),
    this.missingAfterDownload = 0,
    this.failOn,
    this.progressSteps = 0,
  });

  final LocalImageSyncReport report;
  final int missingAfterDownload;
  final String? failOn;
  final int progressSteps;

  final calls = <String>[];

  void _record(String name) {
    calls.add(name);
    if (failOn == name) throw StateError('$name failed');
  }

  @override
  Future<void> syncAllRecords() async => _record('syncAllRecords');

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
    return missingAfterDownload;
  }

  @override
  Future<void> switchToLocalMode() async => _record('switchToLocalMode');

  @override
  Future<void> deleteServerRecords() async => _record('deleteServerRecords');

  @override
  Future<void> markServerRecordsDeleted() async =>
      _record('markServerRecordsDeleted');
}
