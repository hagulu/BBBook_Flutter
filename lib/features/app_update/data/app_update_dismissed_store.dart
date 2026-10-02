import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _dismissedKey = 'app_update_dismissed_version';

/// "그만 보기"를 선택한 최신 버전을 기기에만 저장한다(서버에는 올리지 않는다).
/// 서버의 최신 버전이 바뀌면 저장값과 달라져 다시 안내된다.
class AppUpdateDismissedStore {
  Future<String?> read() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getString(_dismissedKey);
    } catch (_) {
      debugPrint('[업데이트 그만보기 조회] result=FAIL reason=preferences_read_failed');
      return null;
    }
  }

  Future<void> save(String latestVersion) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_dismissedKey, latestVersion);
    } catch (_) {
      debugPrint('[업데이트 그만보기 저장] result=FAIL reason=preferences_write_failed');
    }
  }
}
