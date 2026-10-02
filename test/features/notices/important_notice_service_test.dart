import 'package:bbbook/features/notices/models/notice_detail.dart';
import 'package:bbbook/features/notices/services/important_notice_service.dart';
import 'package:flutter_test/flutter_test.dart';

NoticeDetail n(int id) => NoticeDetail(
  id: id,
  title: 't$id',
  content: 'c$id',
  isImportant: true,
  createdAt: DateTime.utc(2026, 10, id),
);

void main() {
  List<int> ids(List<NoticeDetail> l) => l.map((e) => e.id).toList();

  test('그만 보기 기록이 없으면 서버 정렬 그대로 전부 반환한다', () {
    expect(ids(ImportantNoticeService.pickPopupNotices([n(3), n(2)], {})), [
      3,
      2,
    ]);
  });

  test('그만 보기한 공지는 제외한다', () {
    expect(ids(ImportantNoticeService.pickPopupNotices([n(3), n(2)], {3})), [
      2,
    ]);
  });

  test('모두 그만 보기했거나 비어 있으면 빈 목록', () {
    expect(
      ImportantNoticeService.pickPopupNotices([n(3), n(2)], {2, 3}),
      isEmpty,
    );
    expect(ImportantNoticeService.pickPopupNotices([], {}), isEmpty);
  });

  test('새 중요 공지는 기존 그만 보기와 별개로 노출된다', () {
    expect(ids(ImportantNoticeService.pickPopupNotices([n(5), n(3)], {3})), [
      5,
    ]);
  });
}
