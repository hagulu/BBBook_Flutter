import 'dart:developer' as developer;

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_notifier.dart';
import '../../book_note/providers/book_note_providers.dart';
import '../../book_reflection/providers/book_reflection_providers.dart';
import '../../bookshelf/providers/bookshelf_providers.dart';
import '../../bookshelf/data/bookshelf_database.dart';
import '../../tag/providers/tag_providers.dart';
import '../../server_storage_migration/providers/server_storage_migration_providers.dart';
import '../../storage_mode/providers/storage_mode_providers.dart';
import '../models/record_archive.dart';
import '../services/record_archive_service.dart';

final recordArchiveProvider = NotifierProvider<RecordArchiveController, bool>(
  RecordArchiveController.new,
);

class RecordArchiveController extends Notifier<bool> {
  @override
  bool build() => false;

  Future<String?> run({required bool importing}) async {
    if (state ||
        ref.read(localStorageMigrationControllerProvider).isRunning ||
        ref.read(serverStorageMigrationControllerProvider).isRunning) {
      return null;
    }
    final owner = ref.read(authNotifierProvider).user?.id;
    if (owner == null) return '로그인 상태를 확인해 주세요.';
    final generation = BookshelfDatabase.sessionGeneration;
    void checkSession() {
      if (generation != BookshelfDatabase.sessionGeneration ||
          ref.read(authNotifierProvider).user?.id != owner) {
        throw const ArchiveException('계정 상태가 변경되어 작업을 중단했습니다.');
      }
    }

    state = true;
    try {
      // 새 동기화를 요청하지 않고 이미 진행 중인 Repository 작업만 기다린다.
      await Future.wait([
        ref.read(bookshelfRepositoryProvider).waitForCurrentSync(),
        ref.read(bookNoteRepositoryProvider).waitForCurrentSync(),
        ref.read(bookReflectionRepositoryProvider).waitForCurrentSync(),
        ref.read(tagRepositoryProvider).waitForCurrentSync(),
      ]);
      checkSession();
      final service = RecordArchiveService();
      if (importing) {
        final file = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: ['zip'],
        );
        if (file == null) return null;
        if ((await file.length()) > RecordArchiveService.maxZipBytes) {
          throw const ArchiveException('가져올 ZIP 파일은 512MB까지 지원합니다.');
        }
        final bytes = await file.readAsBytes();
        checkSession();
        await service.importRecords(bytes, owner);
        ref.read(bookshelfSyncVersionProvider.notifier).state++;
        ref.read(bookNoteSyncVersionProvider.notifier).state++;
        ref.read(bookReflectionSyncVersionProvider.notifier).state++;
        ref.read(tagSyncVersionProvider.notifier).state++;
        return '기록을 가져왔습니다.';
      }
      final result = await service.exportRecords(owner);
      checkSession();
      final saved = await FilePicker.saveFile(
        dialogTitle: '내 기록 저장',
        fileName: result.file.uri.pathSegments.last,
        bytes: await result.file.readAsBytes(),
        mimeType: 'application/zip',
      );
      final notice = result.missingImages == 0
          ? ''
          : '\n확보하지 못한 이미지 ${result.missingImages}개는 제외했습니다.';
      return saved == null ? null : '선택한 위치에 내보내기 파일을 저장했습니다.$notice';
    } on ArchiveException catch (error) {
      developer.log('[내 기록 파일 처리] result=FAIL reason=invalid_archive');
      return error.message;
    } catch (_) {
      developer.log('[내 기록 파일 처리] result=FAIL reason=archive_io_error');
      return importing
          ? '기록을 가져오지 못했습니다. 파일을 확인한 뒤 다시 시도해 주세요.'
          : '기록을 내보내지 못했습니다. 저장 공간을 확인한 뒤 다시 시도해 주세요.';
    } finally {
      state = false;
    }
  }
}
