import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _dismissedKey = 'important_notice_dismissed_ids';

/// "그만 보기"를 선택한 중요 공지 id를 기기에만 저장한다(서버에는 올리지 않는다).
class ImportantNoticeDismissedStore {
  Future<Set<int>> read() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getStringList(_dismissedKey) ?? const [];
      return raw.map(int.tryParse).whereType<int>().toSet();
    } catch (_) {
      debugPrint('[중요 공지 그만보기 조회] result=FAIL reason=preferences_read_failed');
      return {};
    }
  }

  Future<void> add(int id) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final ids = await read()
        ..add(id);
      await preferences.setStringList(
        _dismissedKey,
        ids.map((e) => e.toString()).toList(),
      );
    } catch (_) {
      debugPrint('[중요 공지 그만보기 저장] result=FAIL reason=preferences_write_failed');
    }
  }
}
