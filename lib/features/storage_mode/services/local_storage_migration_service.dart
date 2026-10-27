import 'dart:developer' as developer;

import '../../../core/network/api_exception.dart';
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

  /// 서버 기록 전체를 한 번에 받아(`GET /api/me/records`) 책장·노트·독후감·
  /// 태그에 그대로 반영하고, 그 응답의 `exportedAt`을 돌려준다.
  ///
  /// 서버 정리는 이 값으로 해야 받은 뒤 다른 기기·웹에서 바뀐 기록을 지우지
  /// 않는다. [syncAllRecords] 다음에 불러야 이 기기의 dirty 편집 push가 이
  /// 시각보다 앞선다. 저장 모드 게이트를 거치지 않으므로 로컬 저장 모드로
  /// 전환한 뒤에도 쓸 수 있다.
  Future<String?> applyLatestRecords();

  /// 아직 로컬에 없는 메모/독후감 이미지를 모두 내려받는다.
  Future<LocalImageSyncReport> downloadAllImages(
    void Function(int done, int total) onProgress,
  );

  /// 로컬에 남은 "서버에만 있는 이미지" 수. 0이어야 이전을 마칠 수 있다
  /// (서버가 더 이상 주지 않는 이미지는 [LocalImageSyncReport.unavailable]로
  /// 이미 걸러졌으므로 여기 포함되지 않는다).
  Future<int> countMissingLocalImages();

  /// 저장 모드를 로컬로 기록한다. 서버 삭제보다 **먼저** 실행한다.
  /// [exportedAt]은 남은 정리를 나중에 다시 시도할 때도 쓰도록 함께 남긴다.
  Future<void> switchToLocalMode({required String? exportedAt});

  /// 서버 기록을 다시 받아 반영한 뒤, 남겨 둔 `exportedAt`을 바꾼다.
  Future<void> updateExportedAt(String? exportedAt);

  /// 남은 서버 기록 정리에 보낼, 남겨 둔 `exportedAt`.
  Future<String?> pendingExportedAt();

  /// 서버 기록을 일괄 소프트 삭제한다(DELETE /api/me/records).
  ///
  /// [exportedAt] 이후 다른 기기·웹에서 바뀐 기록이 있으면 서버가 아무것도
  /// 지우지 않고 거절하며, 이때 [ServerRecordsChangedException]을 던진다.
  Future<void> deleteServerRecords({required String? exportedAt});

  /// 서버 정리까지 끝났음을 영속 기록한다. 이 표시가 없으면 앱을 다시
  /// 켰을 때 "정리가 남았는지" 알 수 없어 재시도 진입점이 사라진다.
  Future<void> markServerRecordsDeleted();
}

/// 받은 기록의 `exportedAt` 이후 다른 기기·웹에서 기록이 바뀌어 서버가
/// 기록 정리(`DELETE /api/me/records`)를 거절했다(409
/// `RECORDS_CHANGED_SINCE_EXPORT`). 서버에서는 아무것도 삭제되지 않았다.
class ServerRecordsChangedException implements Exception {
  const ServerRecordsChangedException();
}

/// [LocalStorageMigrationService.retryServerCleanup] 결과.
enum ServerCleanupResult {
  cleaned,

  /// 네트워크·서버 오류 등으로 정리하지 못함. 그대로 다시 시도하면 된다.
  failed,

  /// 이 기기에 아직 받지 못한 이미지가 있어 정리하지 않았다. 서버를 지우면
  /// 그 이미지는 다시 받을 수 없다.
  missingImages,

  /// 이 기기가 기록을 내려받은 뒤 다른 기기·웹에서 바뀐 기록이 있어 서버가
  /// 아무것도 지우지 않았다. 그대로 다시 시도해도 같은 결과다.
  changedSinceExport,
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
/// 1. **모드 전환 기록** → 2. 서버 기록 소프트 삭제
///
/// 1과 2의 순서를 바꾸면 안 된다. 서버를 먼저 지운 직후 앱이 죽으면 모드는
/// 여전히 서버 저장이고, 다음 동기화가 "서버에서 사라진 기록"으로 판단해
/// 로컬 원본까지 지운다. 반대로 1 다음에 죽으면 "로컬 모드 + 서버에 남은
/// 데이터"가 되는데, 이건 다시 실행해 지우면 되는 회복 가능한 상태다.
///
/// 전환 전에 서버의 최신 기록을 한 번 받아 와(다른 기기 변경사항 반영)
/// 이 기기를 최신으로 맞추고, 아직 기기에 없는 메모 사진·독후감 이미지를
/// 모두 내려받는다(서버 정리 뒤에는 다시 받을 수 없다). 둘 중 하나라도
/// 끝내지 못하면 [confirmProceed]로 그래도 전환할지 묻고, 거절하면 아무것도
/// 바꾸지 않고 [LocalStorageMigrationStage.idle]로 돌아간다. 서버가 더 이상
/// 주지 않는 이미지(404 등)는 재시도해도 같으므로 묻지 않는다.
///
/// 서버 정리에는 마지막으로 반영한 기록의 `exportedAt`을 함께 보낸다. 그 뒤
/// 다른 기기·웹에서 바뀐 기록이 있어 서버가 거절하면, 최신 기록을 다시 받아
/// 반영하고 새 `exportedAt`으로 다시 정리한다([_cleanUpServerRecords]).
class LocalStorageMigrationService {
  LocalStorageMigrationService(this._steps);

  final LocalStorageMigrationSteps _steps;

  /// 서버 정리가 바뀐 기록 때문에 거절됐을 때 다시 받아 재시도하는 최대 횟수.
  static const _maxRefreshForChangedRecords = 2;

  static const _cleanupPendingMessage =
      '로컬 저장으로는 전환됐지만 서버 기록 정리가 끝나지 않았습니다. '
      '프로필에서 다시 정리할 수 있습니다.';

  Future<LocalStorageMigrationState> run({
    void Function(LocalStorageMigrationState state)? onProgress,
    Future<bool> Function(String message)? confirmProceed,
  }) async {
    var state = const LocalStorageMigrationState(
      stage: LocalStorageMigrationStage.syncingRecords,
    );
    void emit(LocalStorageMigrationState next) {
      state = next;
      onProgress?.call(next);
    }

    Future<bool> askProceed(String message) async =>
        await confirmProceed?.call(message) ?? false;

    emit(state);
    // 최신 기록을 받지 못한 채 전환을 승인하면 null로 남아, 서버 정리가
    // 기존처럼 바뀐 기록 확인 없이 진행된다(사용자가 그 위험을 승인했다).
    String? exportedAt;
    try {
      await _steps.syncAllRecords();
      exportedAt = await _steps.applyLatestRecords();
    } catch (error) {
      developer.log(
        '[로컬 저장 이전] result=FAIL reason=sync (${error.runtimeType})',
      );
      final reason = error is ApiException
          ? error.message
          : '서버에서 최신 기록을 가져오지 못했습니다.';
      if (!await askProceed('$reason\n\n최신 기록 없이 그래도 동기화를 끌까요?')) {
        emit(const LocalStorageMigrationState());
        return state;
      }
    }

    var missingImages = 0;
    try {
      emit(state.copyWith(stage: LocalStorageMigrationStage.downloadingImages));
      final report = await _steps.downloadAllImages((done, total) {
        emit(state.copyWith(imagesDone: done, imagesTotal: total));
      });
      emit(state.copyWith(unavailableImages: report.unavailable));
      emit(state.copyWith(stage: LocalStorageMigrationStage.verifying));
      missingImages = await _steps.countMissingLocalImages();
    } catch (error) {
      developer.log(
        '[로컬 저장 이전] result=FAIL reason=image_download '
        '(${error.runtimeType})',
      );
      missingImages = -1;
    }
    if (missingImages != 0) {
      developer.log(
        '[로컬 저장 이전] result=FAIL reason=image_download_incomplete '
        'missing=$missingImages',
      );
      if (!await askProceed(_missingImagesMessage(missingImages))) {
        emit(const LocalStorageMigrationState());
        return state;
      }
    }

    try {
      // 여기서부터는 로컬이 원본이다. 서버 삭제보다 먼저 기록해 동기화를
      // 멈춰야, 삭제 직후 중단되더라도 로컬 데이터가 안전하다.
      emit(state.copyWith(stage: LocalStorageMigrationStage.switchingMode));
      await _steps.switchToLocalMode(exportedAt: exportedAt);
      // 로컬은 이미 원본이 됐고 남은 건 서버 정리뿐이다. 실패해도 되돌리지
      // 않고 "정리 미완료" 상태로 남겨, 프로필에서 다시 시도하게 한다.
      final cleanupFailure = await _cleanUpServerRecords(
        exportedAt,
        askProceed: askProceed,
        onImagesRefreshed: (report) =>
            emit(state.copyWith(unavailableImages: report.unavailable)),
      );
      if (cleanupFailure != null) {
        return _failed(emit, state, cleanupFailure);
      }

      emit(state.copyWith(stage: LocalStorageMigrationStage.completed));
      developer.log('[로컬 저장 이전] result=SUCCESS');
      return state;
    } catch (error) {
      developer.log('[로컬 저장 이전] result=FAIL reason=${error.runtimeType}');
      return _failed(emit, state, '이전에 실패했습니다. 서버 데이터는 그대로 두었으니 다시 시도해 주세요.');
    }
  }

  /// 서버 기록을 정리한다. 끝나면 null을, 정리가 남으면 사용자에게 보여줄
  /// 문구를 반환한다.
  ///
  /// 서버가 [ServerRecordsChangedException]으로 거절하면 아무것도 지워지지
  /// 않은 상태다. API 문서대로 최신 기록을 다시 받아 반영하고(그 기록의
  /// 이미지도 함께 확보한다) 새 `exportedAt`으로 다시 정리한다 — 전환 직후
  /// 같은 실행 안이라 그 사이 로컬에서만 바뀐 기록은 없다고 보고 서버 기록을
  /// 그대로 반영한다. 나중에 프로필에서 다시 시도하는 정리는 그 사이 로컬
  /// 편집·삭제가 있을 수 있어(로컬 모드 삭제는 즉시 물리 삭제된다) 이렇게
  /// 덮어쓰지 않는다.
  Future<String?> _cleanUpServerRecords(
    String? exportedAt, {
    required Future<bool> Function(String message) askProceed,
    required void Function(LocalImageSyncReport report) onImagesRefreshed,
  }) async {
    var guard = exportedAt;
    for (var refreshed = 0; ; refreshed++) {
      try {
        await _steps.deleteServerRecords(exportedAt: guard);
        await _steps.markServerRecordsDeleted();
        return null;
      } on ServerRecordsChangedException {
        developer.log(
          '[로컬 저장 이전] result=FAIL reason=records_changed_since_export '
          'refreshed=$refreshed',
        );
        if (refreshed >= _maxRefreshForChangedRecords) {
          return '로컬 저장으로는 전환됐지만 다른 기기나 웹에서 기록이 계속 바뀌어 '
              '서버 기록을 정리하지 못했습니다. 프로필에서 다시 정리할 수 있습니다.';
        }
      } catch (error) {
        developer.log(
          '[로컬 저장 이전] result=FAIL reason=server_cleanup '
          '(${error.runtimeType})',
        );
        return _cleanupPendingMessage;
      }

      try {
        guard = await _steps.applyLatestRecords();
        onImagesRefreshed(await _steps.downloadAllImages((_, _) {}));
        final missingImages = await _steps.countMissingLocalImages();
        if (missingImages != 0 &&
            !await askProceed(_missingImagesMessage(missingImages))) {
          return _cleanupPendingMessage;
        }
        // 새로 반영한 기록의 이미지를 확보했거나 누락을 승인한 뒤에만 정리
        // 기준을 바꾼다. 먼저 바꾸면 그 사이 끊겼을 때, 나중 재시도가 받지
        // 못한 이미지를 그대로 둔 채 이 기준으로 서버를 지울 수 있다.
        await _steps.updateExportedAt(guard);
      } catch (error) {
        developer.log(
          '[로컬 저장 이전] result=FAIL reason=refresh_changed_records '
          '(${error.runtimeType})',
        );
        return _cleanupPendingMessage;
      }
    }
  }

  /// 전환은 끝났는데 서버 기록 정리만 남은 상태를 마저 처리한다(프로필의
  /// 다시 시도, 서버 저장 복귀 전 정리).
  ///
  /// 전환 때 남긴 `exportedAt`을 보내, 그 뒤 다른 기기·웹에서 바뀐 기록은
  /// 지우지 않는다. [run]과 달리 서버 기록을 다시 받아 덮어쓰지 않는다 — 그
  /// 사이 로컬에서 고치거나 지운 기록(로컬 모드 삭제는 즉시 물리 삭제된다)이
  /// 서버 값으로 되돌아갈 수 있어서다. 대신 이미지 확보만 이어서 한다 — 전환이
  /// 이미지를 다 받기 전에 끊겼을 수 있고, 서버를 지우면 다시 받을 수 없다.
  ///
  /// 받지 못한 이미지가 남거나 바뀐 기록이 있으면 지우지 않고 그 이유를
  /// 반환한다. 화면이 사용자에게 묻고, 승인하면 [ignoreMissingImages]·
  /// [ignoreChangedRecords]로 다시 호출한다.
  Future<ServerCleanupResult> retryServerCleanup({
    bool ignoreMissingImages = false,
    bool ignoreChangedRecords = false,
  }) async {
    try {
      if (!ignoreMissingImages) {
        await _steps.downloadAllImages((_, _) {});
        final missingImages = await _steps.countMissingLocalImages();
        if (missingImages != 0) {
          developer.log(
            '[서버 기록 정리] result=FAIL reason=image_download_incomplete '
            'missing=$missingImages',
          );
          return ServerCleanupResult.missingImages;
        }
      }
      await _steps.deleteServerRecords(
        exportedAt: ignoreChangedRecords
            ? null
            : await _steps.pendingExportedAt(),
      );
      await _steps.markServerRecordsDeleted();
      developer.log('[서버 기록 정리] result=SUCCESS');
      return ServerCleanupResult.cleaned;
    } on ServerRecordsChangedException {
      developer.log(
        '[서버 기록 정리] result=FAIL reason=records_changed_since_export',
      );
      return ServerCleanupResult.changedSinceExport;
    } catch (error) {
      developer.log('[서버 기록 정리] result=FAIL reason=${error.runtimeType}');
      return ServerCleanupResult.failed;
    }
  }

  String _missingImagesMessage(int missingImages) {
    final count = missingImages > 0 ? '$missingImages장' : '일부';
    return '이미지 $count을 내려받지 못했습니다.\n\n'
        '지금 끄면 받지 못한 이미지는 다시 받을 수 없습니다. 그래도 동기화를 끌까요?';
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
