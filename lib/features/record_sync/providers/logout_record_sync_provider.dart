import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../book_note/providers/book_note_providers.dart';
import '../../book_reflection/providers/book_reflection_providers.dart';
import '../../bookshelf/providers/bookshelf_providers.dart';
import '../../tag/providers/tag_providers.dart';
import '../data/record_sync_dao.dart';

final logoutRecordSyncProvider = Provider<LogoutRecordSync>(
  (ref) => LogoutRecordSync(ref),
);

/// 서버 저장 모드 로그아웃 직전의 최종 동기화.
///
/// 서버 저장 모드 로그아웃은 로컬 기록을 통째로 지우므로
/// ([AuthNotifier.logout]), 그 전에 미전송 변경을 사용자 재시도로 한 번 더
/// 올려 본다. 순서는 백그라운드 동기화와 같다 — 하위 기록은 부모 책의 서버
/// 반영을 전제로 하므로 앞 단계가 실패하면 뒤 단계를 건너뛴다.
class LogoutRecordSync {
  LogoutRecordSync(this.ref, [this._dao = const RecordSyncDao()]);

  final Ref ref;
  final RecordSyncDao _dao;

  /// 최종 동기화를 시도한 뒤 서버에 반영되지 못한 기록이 남았는지 반환한다.
  ///
  /// 동기화 성공 여부가 아니라 남은 dirty 기록으로 판단한다 — 동기화가
  /// 실패했어도 올릴 기록이 없으면 그대로 로그아웃해도 잃을 것이 없고,
  /// 반대로 동기화가 끝났어도 재시도 대기 중인 기록이 남았으면 유실 대상이다.
  Future<bool> syncAndCheckUnsynced() async {
    try {
      await _syncAll();
    } catch (e) {
      developer.log('[로그아웃 최종 동기화] result=FAIL reason=${e.runtimeType}');
    }
    final bool hasUnsynced;
    try {
      hasUnsynced = await _dao.hasUnsyncedChanges();
    } catch (e) {
      // 남은 기록을 확인하지 못하면 있다고 보고 사용자에게 선택을 맡긴다.
      developer.log('[로그아웃 미동기화 확인] result=FAIL reason=${e.runtimeType}');
      return true;
    }
    developer.log(
      '[로그아웃 최종 동기화] result=${hasUnsynced ? 'UNSYNCED_REMAIN' : 'SUCCESS'}',
    );
    return hasUnsynced;
  }

  Future<void> _syncAll() async {
    await ref
        .read(bookshelfSyncControllerProvider.notifier)
        .syncNow(userInitiated: true);
    if (ref.read(bookshelfSyncControllerProvider).hasError) return;
    await ref
        .read(bookNoteSyncControllerProvider.notifier)
        .syncNow(userInitiated: true);
    if (ref.read(bookNoteSyncControllerProvider).hasError) return;
    await ref
        .read(bookReflectionSyncControllerProvider.notifier)
        .syncNow(userInitiated: true);
    if (ref.read(bookReflectionSyncControllerProvider).hasError) return;
    await ref.read(tagSyncControllerProvider.notifier).syncNow();
  }
}
