import 'package:bbbook/features/app_update/models/app_version_policy.dart';
import 'package:bbbook/features/app_update/services/app_update_service.dart';
import 'package:flutter_test/flutter_test.dart';

AppVersionPolicy policy({String latest = '1.3.0', String minimum = '1.1.0'}) =>
    AppVersionPolicy(
      platform: 'ANDROID',
      latestVersion: latest,
      minimumVersion: minimum,
    );

AppUpdateLevel level(
  String current, {
  AppVersionPolicy? p,
  String? dismissed,
}) => AppUpdateService.decide(
  currentVersion: current,
  policy: p ?? policy(),
  dismissedVersion: dismissed,
).level;

void main() {
  group('compareVersions', () {
    test('구성 요소를 숫자로 비교한다', () {
      expect(AppUpdateService.compareVersions('1.10.0', '1.9.0'), 1);
      expect(AppUpdateService.compareVersions('2.9', '2.10'), -1);
    });

    test('누락된 뒤쪽 구성 요소는 0으로 본다', () {
      expect(AppUpdateService.compareVersions('1.2', '1.2.0'), 0);
      expect(AppUpdateService.compareVersions('1.2.1', '1.2'), 1);
    });

    test('형식이 잘못되면 FormatException', () {
      expect(
        () => AppUpdateService.compareVersions('1.x', '1.0'),
        throwsFormatException,
      );
    });
  });

  group('decide', () {
    test('최신 이상이면 안내 없음', () {
      expect(level('1.3.0'), AppUpdateLevel.none);
      expect(level('1.4.0'), AppUpdateLevel.none);
    });

    test('최소 지원 이상 최신 미만이면 권장', () {
      expect(level('1.1.0'), AppUpdateLevel.recommended);
      expect(level('1.2.9'), AppUpdateLevel.recommended);
    });

    test('최소 지원 미만이면 강제', () {
      expect(level('1.0.9'), AppUpdateLevel.forced);
    });

    test('그만 보기한 최신 버전은 권장 안내를 생략한다', () {
      expect(level('1.2.0', dismissed: '1.3.0'), AppUpdateLevel.none);
      expect(level('1.2.0', dismissed: '1.3'), AppUpdateLevel.none);
    });

    test('최신 버전이 바뀌면 다시 안내한다', () {
      expect(
        level(
          '1.2.0',
          p: policy(latest: '1.4.0'),
          dismissed: '1.3.0',
        ),
        AppUpdateLevel.recommended,
      );
    });

    test('그만 보기해도 강제 업데이트는 유지된다', () {
      expect(level('1.0.0', dismissed: '1.3.0'), AppUpdateLevel.forced);
    });

    test('정책이 없거나 형식이 깨졌으면 막지 않는다', () {
      expect(
        AppUpdateService.decide(currentVersion: '1.0.0', policy: null).level,
        AppUpdateLevel.none,
      );
      expect(level('1.0.0', p: policy(minimum: 'abc')), AppUpdateLevel.none);
    });
  });

  test('findPolicy는 플랫폼에 맞는 항목을 고른다', () {
    final ios = AppVersionPolicy(
      platform: 'IOS',
      latestVersion: '2.0.0',
      minimumVersion: '1.0.0',
    );
    expect(AppUpdateService.findPolicy([policy(), ios], 'IOS'), ios);
    expect(AppUpdateService.findPolicy([ios], 'ANDROID'), isNull);
  });
}
