import '../models/app_version_policy.dart';

enum AppUpdateLevel {
  /// 안내 없음(최신이거나 판단 불가).
  none,

  /// 업데이트 권장(안내 후 닫기·그만 보기 가능).
  recommended,

  /// 강제 업데이트(최소 지원 버전 미만).
  forced,
}

class AppUpdateDecision {
  const AppUpdateDecision(this.level, {this.policy});

  const AppUpdateDecision.none() : this(AppUpdateLevel.none);

  final AppUpdateLevel level;
  final AppVersionPolicy? policy;
}

/// 빌드 이름(versionName)만으로 업데이트 정책을 판단하는 순수 함수 모음.
/// 빌드 번호(versionCode)는 쓰지 않는다.
class AppUpdateService {
  const AppUpdateService._();

  /// 점으로 구분된 숫자 버전을 구성 요소별로 비교한다. 누락된 뒤쪽 구성 요소는
  /// 0으로 본다(1.2 == 1.2.0, 1.10.0 > 1.9.0). 형식이 올바르지 않으면
  /// [FormatException].
  static int compareVersions(String a, String b) {
    final left = _parse(a);
    final right = _parse(b);
    final length = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < length; i++) {
      final l = i < left.length ? left[i] : 0;
      final r = i < right.length ? right[i] : 0;
      if (l != r) return l < r ? -1 : 1;
    }
    return 0;
  }

  static List<int> _parse(String version) {
    final trimmed = version.trim();
    if (!RegExp(r'^\d+(\.\d+)*$').hasMatch(trimmed)) {
      throw FormatException('올바르지 않은 버전 형식입니다.', version);
    }
    return trimmed.split('.').map(int.parse).toList();
  }

  /// 서버 정책 목록에서 [platform]에 해당하는 항목을 찾는다.
  static AppVersionPolicy? findPolicy(
    List<AppVersionPolicy> policies,
    String platform,
  ) {
    for (final policy in policies) {
      if (policy.platform.toUpperCase() == platform) return policy;
    }
    return null;
  }

  /// [currentVersion]과 [policy]를 비교해 안내 수준을 정한다.
  /// [dismissedVersion]이 서버 최신 버전과 같으면 권장 안내는 생략한다
  /// (강제 업데이트에는 영향 없음). 버전 형식이 깨졌으면 앱을 막지 않도록
  /// 안내 없음으로 본다.
  static AppUpdateDecision decide({
    required String currentVersion,
    required AppVersionPolicy? policy,
    String? dismissedVersion,
  }) {
    if (policy == null) return const AppUpdateDecision.none();
    try {
      if (compareVersions(currentVersion, policy.minimumVersion) < 0) {
        return AppUpdateDecision(AppUpdateLevel.forced, policy: policy);
      }
      if (compareVersions(currentVersion, policy.latestVersion) >= 0) {
        return const AppUpdateDecision.none();
      }
      if (dismissedVersion != null &&
          _isSameVersion(dismissedVersion, policy.latestVersion)) {
        return const AppUpdateDecision.none();
      }
      return AppUpdateDecision(AppUpdateLevel.recommended, policy: policy);
    } on FormatException {
      return const AppUpdateDecision.none();
    }
  }

  static bool _isSameVersion(String a, String b) {
    try {
      return compareVersions(a, b) == 0;
    } on FormatException {
      return false;
    }
  }
}
