import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _lastSeenKey = 'notice_last_seen_id';

/// 사용자가 공지사항을 마지막으로 확인한 일반 공지 id를 기기에만 저장한다.
/// 서버에는 올리지 않는다.
class NoticeSeenStore {
  Future<int?> read() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getInt(_lastSeenKey);
    } catch (_) {
      debugPrint('[공지 확인 id 조회] result=FAIL reason=preferences_read_failed');
      return null;
    }
  }

  Future<void> write(int id) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setInt(_lastSeenKey, id);
    } catch (_) {
      debugPrint('[공지 확인 id 저장] result=FAIL reason=preferences_write_failed');
    }
  }
}
