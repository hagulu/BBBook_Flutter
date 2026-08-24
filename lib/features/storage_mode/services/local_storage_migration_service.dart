import 'dart:developer' as developer;

import '../../../core/storage/local_image_store.dart';

/// 서버 → 로컬 저장 모드 이전의 단계별 실행기.
///
/// 실제 구현은 동기화 Repository와 API를 엮는
/// [LocalStorageMigrationRepositorySteps]이고, 테스트는 이 인터페이스만
/// 대체해 순서와 중단 조건을 검증한다.
abstract class LocalStorageMigrationSteps {
  /// 서버에 남아 있는 기록 전체를 로컬로 내려받는다(기존 동기화 재사용).
  /// dirty 로컬 편집도 이 과정에서 먼저 서버로 올라간다.
  Future<void> syncAllRecords();

  /// 아직 로컬에 없는 메모/독후감 이미지를 모두 내려받는다.
  Future<LocalImageSyncReport> downloadAllImages(
    void Function(int done, int total) onProgress,
  );

  /// 로컬에 남은 "서버에만 있는 이미지" 수. 0이어야 이전을 마칠 수 있다
  /// (서버가 더 이상 주지 않는 이미지는 [LocalImageSyncReport.unavailable]로
  /// 이미 걸러졌으므로 여기 포함되지 않는다).
  Future<int> countMissingLocalImages();

  /// 저장 모드를 로컬로 기록한다. 서버 삭제보다 **먼저** 실행한다.
  Future<void> switchToLocalMode();

  /// 서버 기록을 일괄 소프트 삭제한다(DELETE /api/me/records).
  Future<void> deleteServerRecords();

  /// 서버 정리까지 끝났음을 영속 기록한다. 이 표시가 없으면 앱을 다시
  /// 켰을 때 "정리가 남았는지" 알 수 없어 재시도 진입점이 사라진다.
  Future<void> markServerRecordsDeleted();
}

enum LocalStorageMigrationStage {
  /// 아직 시작하지 않음.
  idle,

  /// 서버 기록을 로컬로 내려받는 중.
  syncingRecords,

  /// 이미지를 내려받는 중.
  downloadingImages,

  /// 모든 이미지가 로컬에 확보됐는지 확인하는 중.
  verifying,

  /// 서버 기록을 정리하고 모드를 전환하는 중.
  switchingMode,

  completed,
  failed,
}

class LocalStorageMigrationState {
  const LocalStorageMigrationState({
    this.stage = LocalStorageMigrationStage.idle,
    this.imagesDone = 0,
    this.imagesTotal = 0,
    this.unavailableImages = 0,
    this.failureMessage,
  });

  final LocalStorageMigrationStage stage;
  final int imagesDone;
  final int imagesTotal;

  /// 서버에서 더 이상 받을 수 없어 로컬에 확보하지 못한 이미지 수.
  /// 이전을 막지는 않지만 사용자에게 알린다.
  final int unavailableImages;
  final String? failureMessage;

  bool get isRunning =>
      stage != LocalStorageMigrationStage.idle &&
      stage != LocalStorageMigrationStage.completed &&
      stage != LocalStorageMigrationStage.failed;

  double? get imageProgress {
    if (imagesTotal == 0) return null;
    return imagesDone / imagesTotal;
  }

  LocalStorageMigrationState copyWith({
    LocalStorageMigrationStage? stage,
    int? imagesDone,
    int? imagesTotal,
    int? unavailableImages,
    String? failureMessage,
  }) {
    return LocalStorageMigrationState(
      stage: stage ?? this.stage,
      imagesDone: imagesDone ?? this.imagesDone,
      imagesTotal: imagesTotal ?? this.imagesTotal,
      unavailableImages: unavailableImages ?? this.unavailableImages,
      failureMessage: failureMessage,
    );
  }
}

/// 서버 저장 → 로컬 저장 이전을 순서대로 실행한다.
///
/// 순서가 이 기능의 전부라고 해도 될 만큼 중요하다.
/// 1. 기록 동기화 → 2. 이미지 전체 확보 → 3. 확보 검증 →
/// 4. **모드 전환 기록** → 5. 서버 기록 소프트 삭제
///
/// 4와 5의 순서를 바꾸면 안 된다. 서버를 먼저 지운 직후 앱이 죽으면 모드는
/// 여전히 서버 저장이고, 다음 동기화가 "서버에서 사라진 기록"으로 판단해
/// 로컬 원본까지 지운다. 반대로 4 다음에 죽으면 "로컬 모드 + 서버에 남은
/// 데이터"가 되는데, 이건 다시 실행해 지우면 되는 회복 가능한 상태다.
///
/// 3에서 하나라도 확보하지 못한 이미지가 있으면 4로 넘어가지 않는다 —
/// 서버 데이터를 지우기 전에 멈춰야 재시도할 수 있다. 단 서버가 더 이상
/// 주지 않는 이미지(404 등)는 서버를 남겨 둬도 되찾을 수 없으므로 이전을
/// 막지 않고 결과에만 담아 사용자에게 알린다.
class LocalStorageMigrationService {
  LocalStorageMigrationService(this._steps);

  final LocalStorageMigrationSteps _steps;

  Future<LocalStorageMigrationState> run({
    void Function(LocalStorageMigrationState state)? onProgress,
  }) async {
    var state = const LocalStorageMigrationState(
      stage: LocalStorageMigrationStage.syncingRecords,
    );
    void emit(LocalStorageMigrationState next) {
      state = next;
      onProgress?.call(next);
    }

    emit(state);
    try {
      await _steps.syncAllRecords();

      emit(state.copyWith(stage: LocalStorageMigrationStage.downloadingImages));
      final report = await _steps.downloadAllImages((done, total) {
        emit(state.copyWith(imagesDone: done, imagesTotal: total));
      });
      emit(state.copyWith(unavailableImages: report.unavailable));

      emit(state.copyWith(stage: LocalStorageMigrationStage.verifying));
      final missing = await _steps.countMissingLocalImages();
      if (missing > 0) {
        developer.log(
          '[로컬 저장 이전] result=FAIL reason=image_download_incomplete '
          'missing=$missing',
        );
        return _failed(
          emit,
          state,
          '이미지 $missing장을 아직 내려받지 못했습니다. '
          '네트워크 상태를 확인하고 다시 시도해 주세요.',
        );
      }

      // 여기서부터는 로컬이 원본이다. 서버 삭제보다 먼저 기록해 동기화를
      // 멈춰야, 삭제 직후 중단되더라도 로컬 데이터가 안전하다.
      emit(state.copyWith(stage: LocalStorageMigrationStage.switchingMode));
      await _steps.switchToLocalMode();
      try {
        await _steps.deleteServerRecords();
        await _steps.markServerRecordsDeleted();
      } catch (error) {
        // 로컬은 이미 원본이 됐고 남은 건 서버 정리뿐이다. 되돌리지 않고
        // "정리 미완료" 상태로 남겨, 프로필에서 다시 시도하게 한다.
        developer.log(
          '[로컬 저장 이전] result=FAIL reason=server_cleanup '
          '(${error.runtimeType})',
        );
        return _failed(
          emit,
          state,
          '로컬 저장으로는 전환됐지만 서버 기록 정리가 끝나지 않았습니다. '
          '프로필에서 다시 정리할 수 있습니다.',
        );
      }

      emit(state.copyWith(stage: LocalStorageMigrationStage.completed));
      developer.log(
        '[로컬 저장 이전] result=SUCCESS '
        'unavailableImages=${report.unavailable}',
      );
      return state;
    } catch (error) {
      developer.log('[로컬 저장 이전] result=FAIL reason=${error.runtimeType}');
      return _failed(emit, state, '이전에 실패했습니다. 서버 데이터는 그대로 두었으니 다시 시도해 주세요.');
    }
  }

  LocalStorageMigrationState _failed(
    void Function(LocalStorageMigrationState) emit,
    LocalStorageMigrationState state,
    String message,
  ) {
    final failed = state.copyWith(
      stage: LocalStorageMigrationStage.failed,
      failureMessage: message,
    );
    emit(failed);
    return failed;
  }
}
