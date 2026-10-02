import 'package:bbbook/features/notices/models/notice_latest.dart';
import 'package:bbbook/features/notices/models/notice_summary.dart';
import 'package:bbbook/features/notices/services/notice_badge_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('isImportant 필드를 파싱하고 없으면 false', () {
    final a = NoticeSummary.fromJson({
      'id': 1,
      'title': 'a',
      'isImportant': true,
      'createdAt': '2026-10-01T00:00:00Z',
    });
    final b = NoticeSummary.fromJson({
      'id': 2,
      'title': 'b',
      'createdAt': '2026-10-01T00:00:00Z',
    });
    expect(a.isImportant, isTrue);
    expect(b.isImportant, isFalse);
  });

  test('latest 응답: exists=false면 id는 null', () {
    expect(
      NoticeLatest.fromJson({
        'exists': false,
        'id': null,
        'createdAt': null,
      }).id,
      isNull,
    );
    expect(
      NoticeLatest.fromJson({
        'exists': true,
        'id': 7,
        'createdAt': '2026-10-01T00:00:00Z',
      }).id,
      7,
    );
  });

  test('최신 공지가 없으면 배지 없음', () {
    expect(NoticeBadgeService.hasNewNotice(latestId: null), isFalse);
    expect(
      NoticeBadgeService.hasNewNotice(latestId: null, lastSeenId: 3),
      isFalse,
    );
  });

  test('확인 기록이 없으면 최신 공지가 있을 때 배지', () {
    expect(NoticeBadgeService.hasNewNotice(latestId: 5), isTrue);
  });

  test('마지막 확인 id보다 새로울 때만 배지', () {
    expect(NoticeBadgeService.hasNewNotice(latestId: 6, lastSeenId: 5), isTrue);
    expect(
      NoticeBadgeService.hasNewNotice(latestId: 5, lastSeenId: 5),
      isFalse,
    );
    expect(
      NoticeBadgeService.hasNewNotice(latestId: 4, lastSeenId: 5),
      isFalse,
    );
  });

  test('nextLastSeenId는 과거로 되돌리지 않는다', () {
    expect(NoticeBadgeService.nextLastSeenId(latestId: 6, lastSeenId: 5), 6);
    expect(NoticeBadgeService.nextLastSeenId(latestId: 6), 6);
    expect(
      NoticeBadgeService.nextLastSeenId(latestId: 5, lastSeenId: 5),
      isNull,
    );
    expect(NoticeBadgeService.nextLastSeenId(latestId: null), isNull);
  });

  test('latestNormalId는 표시한 목록의 일반 공지 중 최대 id만 본다', () {
    NoticeSummary n(int id, {bool important = false}) => NoticeSummary(
      id: id,
      title: 't',
      isImportant: important,
      createdAt: DateTime.utc(2026, 10, 1),
    );
    expect(
      NoticeBadgeService.latestNormalId([n(9, important: true), n(7), n(5)]),
      7,
    );
    expect(NoticeBadgeService.latestNormalId([n(9, important: true)]), isNull);
    expect(NoticeBadgeService.latestNormalId([]), isNull);
  });
}
