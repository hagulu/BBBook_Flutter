import 'dart:developer' as developer;
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/book_memo.dart';
import 'book_memo_dao.dart';

/// 메모 화면의 로컬 source of truth.
///
/// 이 Repository는 네트워크/API 의존성을 갖지 않는다. 모든 조회·CRUD는
/// `book_memo`/`book_memo_item` 로컬 테이블만 사용하며, 쓰기는 DAO가
/// `is_dirty=1`과 `updated_at`을 함께 기록한다.
class BookMemoRepository {
  const BookMemoRepository(this._dao);

  final BookMemoDao _dao;

  Future<List<BookMemoSummary>> findByUserBook({
    required int ownerUserId,
    required int userBookId,
  }) {
    return _dao.findByUserBook(
      ownerUserId: ownerUserId,
      userBookId: userBookId,
    );
  }

  Future<BookMemoDetail?> findDetail({
    required int ownerUserId,
    required int userBookId,
    required int memoId,
  }) {
    return _dao.findDetail(
      ownerUserId: ownerUserId,
      userBookId: userBookId,
      memoId: memoId,
    );
  }

  Future<BookMemo> saveTitle({
    required int ownerUserId,
    required int userBookId,
    required int? memoId,
    required String? title,
  }) async {
    final operation = memoId == null ? '메모 생성' : '메모 제목 수정';
    try {
      final memo = memoId == null
          ? await _dao.createMemo(
              ownerUserId: ownerUserId,
              userBookId: userBookId,
              title: title,
            )
          : await _dao.updateTitle(
              ownerUserId: ownerUserId,
              userBookId: userBookId,
              memoId: memoId,
              title: title,
            );
      developer.log(
        '[$operation] userId=$ownerUserId bookId=$userBookId '
        'memoId=${memo.id} result=SUCCESS',
      );
      return memo;
    } catch (error) {
      developer.log(
        '[$operation] userId=$ownerUserId bookId=$userBookId '
        'memoId=${memoId ?? 'new'} result=FAIL reason=local_storage_error',
      );
      rethrow;
    }
  }

  Future<BookMemoItem> createItem({
    required int ownerUserId,
    required int userBookId,
    required int memoId,
    required BookMemoItemDraft draft,
  }) async {
    String? imageUrl;
    try {
      imageUrl = await _resolveImageUrl(draft);
      final item = await _dao.createItem(
        ownerUserId: ownerUserId,
        userBookId: userBookId,
        memoId: memoId,
        draft: draft,
        imageUrl: imageUrl,
      );
      developer.log(
        '[메모 조각 생성] userId=$ownerUserId bookId=$userBookId '
        'memoId=$memoId itemId=${item.id} result=SUCCESS',
      );
      return item;
    } catch (error) {
      if (draft.pickedImagePath != null) {
        await _deleteManagedImage(imageUrl);
      }
      developer.log(
        '[메모 조각 생성] userId=$ownerUserId bookId=$userBookId '
        'memoId=$memoId result=FAIL reason=local_storage_error',
      );
      rethrow;
    }
  }

  Future<BookMemoItem> updateItem({
    required int ownerUserId,
    required int userBookId,
    required int memoId,
    required int itemId,
    required BookMemoItemDraft draft,
    required String? previousImageUrl,
  }) async {
    String? imageUrl;
    try {
      imageUrl = await _resolveImageUrl(draft);
      final item = await _dao.updateItem(
        ownerUserId: ownerUserId,
        userBookId: userBookId,
        memoId: memoId,
        itemId: itemId,
        draft: draft,
        imageUrl: imageUrl,
      );
      await _deleteManagedImage(previousImageUrl, except: imageUrl);
      developer.log(
        '[메모 조각 수정] userId=$ownerUserId bookId=$userBookId '
        'memoId=$memoId itemId=$itemId result=SUCCESS',
      );
      return item;
    } catch (error) {
      if (draft.pickedImagePath != null) {
        await _deleteManagedImage(imageUrl);
      }
      developer.log(
        '[메모 조각 수정] userId=$ownerUserId bookId=$userBookId '
        'memoId=$memoId itemId=$itemId result=FAIL '
        'reason=local_storage_error',
      );
      rethrow;
    }
  }

  Future<DeleteMemoItemResult> deleteItem({
    required int ownerUserId,
    required int userBookId,
    required int memoId,
    required int itemId,
    required String? previousImageUrl,
  }) async {
    try {
      final result = await _dao.deleteItem(
        ownerUserId: ownerUserId,
        userBookId: userBookId,
        memoId: memoId,
        itemId: itemId,
      );
      await _deleteManagedImage(previousImageUrl);
      developer.log(
        '[메모 조각 삭제] userId=$ownerUserId bookId=$userBookId '
        'memoId=$memoId itemId=$itemId result=SUCCESS',
      );
      return result;
    } catch (error) {
      developer.log(
        '[메모 조각 삭제] userId=$ownerUserId bookId=$userBookId '
        'memoId=$memoId itemId=$itemId result=FAIL '
        'reason=local_storage_error',
      );
      rethrow;
    }
  }

  Future<String?> _resolveImageUrl(BookMemoItemDraft draft) async {
    if (draft.type != BookMemoItemType.photo) return null;
    final pickedPath = draft.pickedImagePath;
    if (pickedPath == null) return draft.imageUrl;

    final source = File(pickedPath);
    if (!await source.exists()) throw const FileSystemException();
    final root = await getApplicationSupportDirectory();
    final directory = Directory(path.join(root.path, 'memo_images'));
    await directory.create(recursive: true);
    final extension = path.extension(pickedPath).toLowerCase();
    final fileName =
        'memo_${DateTime.now().microsecondsSinceEpoch}'
        '${extension.isEmpty ? '.jpg' : extension}';
    return source
        .copy(path.join(directory.path, fileName))
        .then((file) => file.path);
  }

  Future<void> _deleteManagedImage(String? imageUrl, {String? except}) async {
    if (imageUrl == null || imageUrl.isEmpty || imageUrl == except) return;
    if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
      return;
    }

    try {
      final root = await getApplicationSupportDirectory();
      final managedDirectory = path.normalize(
        path.absolute(path.join(root.path, 'memo_images')),
      );
      final rawPath = imageUrl.startsWith('file://')
          ? Uri.parse(imageUrl).toFilePath()
          : imageUrl;
      final targetPath = path.normalize(path.absolute(rawPath));
      if (!path.isWithin(managedDirectory, targetPath)) return;

      final file = File(targetPath);
      if (await file.exists()) await file.delete();
    } catch (_) {
      developer.log('[메모 사진 정리] result=FAIL reason=local_file_error');
    }
  }
}
