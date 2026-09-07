import 'dart:io';

import '../../book_reflection/data/book_reflection_dao.dart';
import 'record_import_payload_builder.dart';
import 'record_import_snapshot.dart';
import '../models/record_import_models.dart';

/// `/complete` 성공 뒤 로컬 DB에 한 번에 반영할 localId → serverId 매핑
/// 묶음. 청크 응답을 받는 즉시 반영하지 않는 이유는
/// `BookshelfDao.applyImportResults` 문서 참고.
class RecordImportAppliedResults {
  const RecordImportAppliedResults({
    required this.bookServerIdByLocalId,
    required this.noteServerIdByLocalId,
    required this.memoServerIdByLocalId,
    required this.memoImageUrlByLocalId,
    required this.reflectionResultsByLocalId,
    required this.tagServerIdByLocalId,
    required this.tagMapServerIdByLocalId,
  });

  final Map<int, int> bookServerIdByLocalId;
  final Map<int, int> noteServerIdByLocalId;
  final Map<int, int> memoServerIdByLocalId;
  final Map<int, String> memoImageUrlByLocalId;
  final Map<int, ReflectionImportResult> reflectionResultsByLocalId;
  final Map<int, int> tagServerIdByLocalId;
  final Map<int, int> tagMapServerIdByLocalId;
}

/// 로컬 → 서버 저장 모드 재전환 Import의 각 단계.
///
/// 실제 구현은 [ServerStorageMigrationRepositorySteps]이고,
/// [ServerStorageMigrationService]는 이 인터페이스만 통해 단계를
/// 순서대로 실행한다 — 테스트가 순서·중단 조건을 가짜 구현으로 검증할 수
/// 있게 한다(`storage_mode/data/local_storage_migration_steps.dart`와
/// 같은 구조).
abstract class ServerStorageMigrationSteps {
  /// 이전에 로컬 저장 모드로 전환하며 남겨 둔 "서버 기록 정리 미완료"
  /// 상태가 있으면 먼저 정리한다. 정리가 끝나야만(또는 애초에 없어야만)
  /// 이번 세션에서 되찾는 `serverId`가 전부 "이 계정이 소프트 삭제한 자기
  /// 자신의 옛 행"이라고 보장할 수 있다 — 그래야 독후감 첨부 가능 여부를
  /// `created` 값과 무관하게 "이번에 local:// placeholder를 보낸 독후감은
  /// 항상 첨부 가능"으로 단순하게 다룰 수 있다(§ attachments 문서의
  /// created=false 모호성 참고). 반환값은 정리가 끝나(또는 필요 없어)
  /// 안전하게 진행할 수 있는지 여부.
  Future<bool> ensureNoPendingServerCleanup();

  /// 로컬 DB를 훑어 스냅샷을 만들고 문서상 세션 전체를 죽일 수 있는 조합을
  /// 미리 걸러낸다.
  Future<RecordImportPreflightOutcome> prepare();

  Future<RecordImportSession> startSession();

  Future<RecordImportChunkResult> uploadChunk(
    int importId,
    RecordImportChunk chunk,
  );

  Future<RecordImportAttachmentResult> uploadMemoImage(
    int importId,
    int memoLocalId,
    File file,
  );

  Future<RecordImportAttachmentResult> uploadReflectionImage(
    int importId,
    int reflectionLocalId,
    String placeholder,
    File file,
  );

  Future<void> complete(int importId, RecordImportCounts counts);

  Future<void> applyResults(RecordImportAppliedResults results);

  Future<void> switchToServerMode();
}
