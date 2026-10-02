/// `GET /api/app-versions`의 플랫폼별 앱 버전 정책 한 건.
class AppVersionPolicy {
  const AppVersionPolicy({
    required this.platform,
    required this.latestVersion,
    required this.minimumVersion,
    this.updateMessage,
    this.storeUrl,
  });

  factory AppVersionPolicy.fromJson(Map<String, dynamic> json) {
    return AppVersionPolicy(
      platform: json['platform'] as String,
      latestVersion: json['latestVersion'] as String,
      minimumVersion: json['minimumVersion'] as String,
      updateMessage: json['updateMessage'] as String?,
      storeUrl: json['storeUrl'] as String?,
    );
  }

  /// `ANDROID` | `IOS`
  final String platform;
  final String latestVersion;
  final String minimumVersion;
  final String? updateMessage;
  final String? storeUrl;
}
