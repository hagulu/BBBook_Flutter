import 'package:url_launcher/url_launcher.dart';

import 'api_config.dart';

/// 백엔드가 제공하는 정책 페이지(이용약관·개인정보 처리방침) 링크.
///
/// 웹 프론트와 같은 주소(`API_BASE_URL` + 경로)를 외부 브라우저로 연다.
enum PolicyLink {
  terms('/terms'),
  privacy('/privacy');

  const PolicyLink(this.path);

  final String path;

  Uri get uri => Uri.parse('${ApiConfig.baseUrl}$path');

  Future<bool> open() => launchUrl(uri, mode: LaunchMode.externalApplication);
}
