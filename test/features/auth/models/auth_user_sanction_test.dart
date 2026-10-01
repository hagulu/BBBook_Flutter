import 'package:bbbook/features/auth/models/auth_user.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final base = <String, dynamic>{
    'id': 7,
    'nickname': '독자',
    'profileImageUrl': null,
    'isFinishedBooksPublic': false,
  };

  test('징계 안내 정보와 해제 시각을 /api/users/me 응답에서 읽는다', () {
    final user = AuthUser.fromJson({
      ...base,
      'isSanctioned': true,
      'sanction': {
        'reason': 'SPAM',
        'reasonLabel': '스팸',
        'isPermanent': false,
        'endsAt': '2026-10-03T12:00:00Z',
      },
    });

    expect(user.isSanctioned, isTrue);
    expect(user.sanction?.reasonLabel, '스팸');
    expect(user.sanction?.endsAt?.toUtc(), DateTime.utc(2026, 10, 3, 12));
  });

  test('징계 해제 응답은 이전 징계 정보를 남기지 않는다', () {
    final user = AuthUser.fromJson({
      ...base,
      'isSanctioned': false,
      'sanction': null,
    });

    expect(user.isSanctioned, isFalse);
    expect(user.sanction, isNull);
  });
}
