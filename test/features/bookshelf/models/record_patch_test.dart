import 'package:bbbook/core/network/patch_field.dart';
import 'package:bbbook/features/bookshelf/models/book_item.dart';
import 'package:bbbook/features/bookshelf/models/book_status.dart';
import 'package:bbbook/features/bookshelf/models/record_patch.dart';
import 'package:flutter_test/flutter_test.dart';

/// `PATCH /api/me/books/{userBookId}`의 필드 처리 규칙
/// (api-doc/api-me-books-userBookId-patch.md)을 검증한다.
/// - 요청 body에 없는 필드 → 기존 값 유지
/// - 명시적 `null` → 삭제
/// - 빈 문자열 → 삭제가 아니라 값 그대로 저장
/// - `status`/`currentPage`/`isMasterpiece`/`rereadCount`는 삭제 불가
void main() {
  BookItem buildItem({
    BookStatus status = BookStatus.reading,
    int currentPage = 10,
    double? myRating,
    String? shortReview,
    String? sourceType,
    String? difficulty,
    DateTime? startedAt,
    DateTime? finishedAt,
    int? libraryId,
    DateTime? libraryDueAt,
    String? platformName,
    String? discoverySource,
  }) {
    final now = DateTime.utc(2026, 8, 26);
    return BookItem(
      userBookId: 1,
      serverId: 1,
      title: '책',
      status: status,
      currentPage: currentPage,
      myRating: myRating,
      shortReview: shortReview,
      isMasterpiece: false,
      sourceType: sourceType,
      rereadCount: 2,
      difficulty: difficulty,
      startedAt: startedAt,
      finishedAt: finishedAt,
      libraryId: libraryId,
      libraryDueAt: libraryDueAt,
      platformName: platformName,
      discoverySource: discoverySource,
      tags: const [],
      createdAt: now,
      updatedAt: now,
    );
  }

  group('RecordPatch.toJson - 필드 처리 규칙', () {
    test('담지 않은 필드는 요청 body에서 제외된다(기존 값 유지)', () {
      final body = const RecordPatch(currentPage: 42).toJson();

      expect(body, {'currentPage': 42});
      expect(body.containsKey('myRating'), isFalse);
      expect(body.containsKey('shortReview'), isFalse);
      expect(body.containsKey('startedAt'), isFalse);
    });

    test('PatchField.clear()는 명시적 null로 나간다(삭제)', () {
      final body = const RecordPatch(
        myRating: PatchField.clear(),
        startedAt: PatchField.clear(),
        platformName: PatchField.clear(),
      ).toJson();

      expect(body.containsKey('myRating'), isTrue);
      expect(body['myRating'], isNull);
      expect(body.containsKey('startedAt'), isTrue);
      expect(body['startedAt'], isNull);
      expect(body.containsKey('platformName'), isTrue);
      expect(body['platformName'], isNull);
    });

    test('빈 문자열은 삭제가 아니라 값 그대로 전달된다', () {
      final body = const RecordPatch(
        shortReview: PatchField.value(''),
        discoverySource: PatchField.value(''),
      ).toJson();

      expect(body['shortReview'], '');
      expect(body['discoverySource'], '');
      expect(body['shortReview'], isNot(isNull));
    });

    test('삭제 불가 필드는 값이 없으면 키 자체가 빠진다(null로 나가지 않음)', () {
      final body = const RecordPatch(
        status: null,
        currentPage: null,
        isMasterpiece: null,
        rereadCount: null,
        myRating: PatchField.clear(),
      ).toJson();

      expect(body.keys, ['myRating']);
    });

    test('changedFields는 요청에 실리는 키와 같다', () {
      const patch = RecordPatch(
        status: 'FINISHED',
        finishedAt: PatchField.value('2026-08-26'),
        difficulty: PatchField.clear(),
      );

      expect(patch.changedFields, {'status', 'finishedAt', 'difficulty'});
      expect(patch.isEmpty, isFalse);
      expect(const RecordPatch().isEmpty, isTrue);
    });
  });

  group('RecordPatch.fromSnapshot - 로컬 편집 재전송', () {
    test('바꾼 필드만 싣고, 지운 필드는 명시적 null로 보낸다', () {
      final item = buildItem(
        myRating: null, // 사용자가 지움
        shortReview: '좋았다',
        difficulty: 'EASY',
      );

      final body = RecordPatch.fromSnapshot(
        item,
        changedFields: {'myRating', 'shortReview'},
      ).toJson();

      expect(body.containsKey('myRating'), isTrue);
      expect(body['myRating'], isNull);
      expect(body['shortReview'], '좋았다');
      // 건드리지 않은 필드는 서버 값이 유지되도록 body에서 제외한다.
      expect(body.containsKey('difficulty'), isFalse);
      expect(body.containsKey('status'), isFalse);
      expect(body.containsKey('currentPage'), isFalse);
    });

    test('값이 없는 필드도 바꾼 목록에 없으면 아예 보내지 않는다', () {
      final item = buildItem(platformName: null, sourceType: 'EBOOK');

      final body = RecordPatch.fromSnapshot(
        item,
        changedFields: {'sourceType'},
      ).toJson();

      expect(body, {'sourceType': 'EBOOK'});
    });

    test('날짜는 yyyy-MM-dd로 직렬화한다', () {
      final item = buildItem(
        startedAt: DateTime.utc(2026, 1, 2),
        finishedAt: DateTime.utc(2026, 3, 4),
        libraryDueAt: DateTime.utc(2026, 5, 6),
        libraryId: 7,
      );

      final body = RecordPatch.fromSnapshot(
        item,
        changedFields: {
          'startedAt',
          'finishedAt',
          'libraryDueAt',
          'libraryId',
        },
      ).toJson();

      expect(body['startedAt'], '2026-01-02');
      expect(body['finishedAt'], '2026-03-04');
      expect(body['libraryDueAt'], '2026-05-06');
      expect(body['libraryId'], 7);
    });

    test('레거시 dirty 행(목록 없음)은 값이 있는 필드만 보내고 삭제는 보내지 않는다', () {
      final item = buildItem(myRating: null, shortReview: '한줄');

      final body = RecordPatch.fromSnapshot(item, changedFields: null).toJson();

      // 값이 null인 필드에 명시적 null(삭제)을 실으면, 사용자가 지운 적 없는
      // 서버 값까지 지워버린다.
      expect(body.containsKey('myRating'), isFalse);
      expect(body.containsKey('platformName'), isFalse);
      expect(body['shortReview'], '한줄');
      // 삭제 불가 필드는 로컬 값이 곧 최신이라 그대로 보낸다.
      expect(body['status'], 'READING');
      expect(body['currentPage'], 10);
      expect(body['isMasterpiece'], false);
      expect(body['rereadCount'], 2);
    });

    test('완독 상태인데 완독일을 모르면 status를 생략한다(서버가 오늘로 새로 잡는 것 방지)', () {
      final item = buildItem(status: BookStatus.finished, finishedAt: null);

      final body = RecordPatch.fromSnapshot(
        item,
        changedFields: {'status', 'currentPage'},
      ).toJson();

      expect(body.containsKey('status'), isFalse);
      expect(body['currentPage'], 10);
    });

    test('완독으로 바꾸는 요청에는 로컬 완독일을 함께 실어 서버가 오늘로 새로 잡지 못하게 한다', () {
      final item = buildItem(
        status: BookStatus.finished,
        finishedAt: DateTime.utc(2026, 8, 20),
      );

      final body = RecordPatch.fromSnapshot(
        item,
        changedFields: {'status'},
      ).toJson();

      expect(body['status'], 'FINISHED');
      expect(body['finishedAt'], '2026-08-20');
    });

    test('nonNullFieldsOf는 레거시 행이 보내던 필드를 모두 덮는다', () {
      // 레거시 dirty 행 위에 새 편집이 겹칠 때의 추적 목록 출발점이라,
      // 그 행이 실제로 보내던 필드가 하나도 빠지지 않아야 한다(완독인데
      // 완독일을 모르는 행처럼 push 시점에 다시 걸러지는 필드가 있어
      // 집합이 더 넓을 수는 있다).
      final item = buildItem(shortReview: '한줄', difficulty: 'HARD');

      final legacyBody = RecordPatch.fromSnapshot(
        item,
        changedFields: null,
      ).toJson();

      expect(
        RecordPatch.nonNullFieldsOf(item),
        containsAll(legacyBody.keys.toSet()),
      );
    });
  });

  group('BookItem.copyWithRecord - 로컬 즉시 반영', () {
    test('담지 않은 필드는 유지, clear는 지움, 빈 문자열은 값으로 저장', () {
      final item = buildItem(
        myRating: 4.5,
        shortReview: '좋았다',
        difficulty: 'EASY',
        startedAt: DateTime.utc(2026, 1, 2),
      );

      final updated = item.copyWithRecord(
        const RecordPatch(
          myRating: PatchField.clear(),
          shortReview: PatchField.value(''),
        ),
        updatedAt: DateTime.utc(2026, 8, 26),
      );

      expect(updated.myRating, isNull);
      expect(updated.shortReview, '');
      expect(updated.difficulty, 'EASY');
      expect(updated.startedAt, DateTime.utc(2026, 1, 2));
    });

    test('시작일 지우기는 로컬에서도 즉시 null이 된다', () {
      final item = buildItem(startedAt: DateTime.utc(2026, 1, 2));

      final updated = item.copyWithRecord(
        const RecordPatch(startedAt: PatchField.clear()),
        updatedAt: DateTime.utc(2026, 8, 26),
      );

      expect(updated.startedAt, isNull);
    });

    test('완독으로 바꾸면서 완독일을 안 보내면 로컬에도 오늘(KST)이 채워진다', () {
      final item = buildItem(status: BookStatus.reading);

      final updated = item.copyWithRecord(
        const RecordPatch(status: 'FINISHED'),
        updatedAt: DateTime.utc(2026, 8, 26),
      );

      final kstToday = DateTime.now().toUtc().add(const Duration(hours: 9));
      expect(updated.status, BookStatus.finished);
      expect(
        updated.finishedAt,
        DateTime(kstToday.year, kstToday.month, kstToday.day),
      );
    });

    test('완독 상태에서 완독일을 지워도 서버처럼 기존 값을 유지한다', () {
      // 서버는 수정 결과 status가 FINISHED면 finishedAt 삭제를 무시하고
      // 기존 값을 유지한다(api-doc) — 로컬만 지우면 push 응답이나 다음
      // 동기화에서 날짜가 되살아나 화면이 잠깐 거짓말을 하게 된다.
      final item = buildItem(
        status: BookStatus.finished,
        finishedAt: DateTime.utc(2026, 3, 4),
      );

      final updated = item.copyWithRecord(
        const RecordPatch(finishedAt: PatchField.clear()),
        updatedAt: DateTime.utc(2026, 8, 26),
      );

      expect(updated.finishedAt, DateTime.utc(2026, 3, 4));
    });

    test('완독으로 바꾸면서 완독일을 지우면 서버처럼 오늘로 설정된다', () {
      final item = buildItem(status: BookStatus.reading);

      final updated = item.copyWithRecord(
        const RecordPatch(status: 'FINISHED', finishedAt: PatchField.clear()),
        updatedAt: DateTime.utc(2026, 8, 26),
      );

      final kstToday = DateTime.now().toUtc().add(const Duration(hours: 9));
      expect(
        updated.finishedAt,
        DateTime(kstToday.year, kstToday.month, kstToday.day),
      );
    });

    test('완독이 아닌 상태에서는 완독일이 지워진다', () {
      final item = buildItem(
        status: BookStatus.paused,
        finishedAt: DateTime.utc(2026, 3, 4),
      );

      final updated = item.copyWithRecord(
        const RecordPatch(finishedAt: PatchField.clear()),
        updatedAt: DateTime.utc(2026, 8, 26),
      );

      expect(updated.finishedAt, isNull);
    });

    test('완독 → 다른 상태로 바꾸면서 완독일을 지우면 지워진다', () {
      final item = buildItem(
        status: BookStatus.finished,
        finishedAt: DateTime.utc(2026, 3, 4),
      );

      final updated = item.copyWithRecord(
        const RecordPatch(status: 'READING', finishedAt: PatchField.clear()),
        updatedAt: DateTime.utc(2026, 8, 26),
      );

      expect(updated.finishedAt, isNull);
    });
  });
}
