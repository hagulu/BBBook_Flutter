import 'package:flutter_test/flutter_test.dart';

import 'package:bbbook/features/public_bookshelf/services/user_report_policy.dart';

void main() {
  group('canReportUser', () {
    test('다른 사용자는 신고할 수 있다', () {
      expect(
        canReportUser(isLoggedIn: true, myUserId: 1, targetUserId: 2),
        isTrue,
      );
    });

    test('본인은 신고할 수 없다', () {
      expect(
        canReportUser(isLoggedIn: true, myUserId: 1, targetUserId: 1),
        isFalse,
      );
    });

    test('로그인하지 않았으면 신고할 수 없다', () {
      expect(
        canReportUser(isLoggedIn: false, myUserId: null, targetUserId: 2),
        isFalse,
      );
    });
  });
}
