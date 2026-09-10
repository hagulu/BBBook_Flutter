import 'package:bbbook/core/storage/local_image_store.dart';
import 'package:bbbook/features/storage_mode/services/local_storage_migration_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 서버 → 로컬 저장 이전의 순서와 중단 조건 테스트.
///
/// 이 서비스에서 틀리면 되돌릴 수 없는 사고가 난다 — 서버 기록을 먼저 지운
/// 뒤 중단되면 로컬 원본까지 다음 동기화가 지우고, 반대로 받지 못한
/// 이미지가 있는데 삭제까지 진행하면 그 이미지를 영영 잃는다.
void main() {
  test('새 동기화나 다운로드 없이 모드 전환 후 서버를 삭제한다', () async {
    final steps = _FakeSteps();
    final stages = <LocalStorageMigrationStage>[];
    final result = await LocalStorageMigrationService(
      steps,
    ).run(onProgress: (state) => stages.add(state.stage));
    expect(result.stage, LocalStorageMigrationStage.completed);
    expect(steps.calls, [
      'switchToLocalMode',
      'deleteServerRecords',
      'markServerRecordsDeleted',
    ]);
    expect(stages.first, LocalStorageMigrationStage.switchingMode);
  });

  test('모드 전환 실패 시 서버를 삭제하지 않는다', () async {
    final steps = _FakeSteps(failOn: 'switchToLocalMode');
    final result = await LocalStorageMigrationService(steps).run();
    expect(result.stage, LocalStorageMigrationStage.failed);
    expect(steps.calls, ['switchToLocalMode']);
  });

  test('서버 삭제 실패 시 정리 미완료로 남긴다', () async {
    final steps = _FakeSteps(failOn: 'deleteServerRecords');
    final result = await LocalStorageMigrationService(steps).run();
    expect(result.stage, LocalStorageMigrationStage.failed);
    expect(result.failureMessage, contains('서버 기록 정리'));
    expect(steps.calls, ['switchToLocalMode', 'deleteServerRecords']);
  });
}

class _FakeSteps implements LocalStorageMigrationSteps {
  _FakeSteps({this.failOn});

  final LocalImageSyncReport report = const LocalImageSyncReport(stored: 1);
  final int missingAfterDownload = 0;
  final String? failOn;
  final int progressSteps = 0;

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
