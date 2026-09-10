import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _themeModeKey = 'app_theme_mode';

final initialThemeModeProvider = Provider<ThemeMode>((ref) => ThemeMode.light);

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

Future<ThemeMode> loadThemeMode() async {
  try {
    final preferences = await SharedPreferences.getInstance();
    return switch (preferences.getString(_themeModeKey)) {
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => ThemeMode.light,
    };
  } catch (_) {
    debugPrint('[테마 조회] result=FAIL reason=preferences_read_failed');
    return ThemeMode.light;
  }
}

class ThemeModeController extends Notifier<ThemeMode> {
  Future<void> _pendingSave = Future<void>.value();
  int _selectionVersion = 0;
  ThemeMode _savedMode = ThemeMode.light;

  @override
  ThemeMode build() {
    _savedMode = ref.watch(initialThemeModeProvider);
    return _savedMode;
  }

  Future<bool> select(ThemeMode mode) {
    final version = ++_selectionVersion;
    state = mode;
    // 빠르게 연속 선택해도 마지막 선택이 마지막으로 저장된다.
    final save = _pendingSave.then((_) async {
      try {
        final preferences = await SharedPreferences.getInstance();
        final saved = await preferences.setString(_themeModeKey, mode.name);
        if (!saved) {
          debugPrint('[테마 저장] result=FAIL reason=preferences_write_failed');
        }
        return saved;
      } catch (_) {
        debugPrint('[테마 저장] result=FAIL reason=preferences_write_failed');
        return false;
      }
    });
    _pendingSave = save.then((saved) {
      if (saved) {
        _savedMode = mode;
      } else if (version == _selectionVersion) {
        state = _savedMode;
      }
    });
    return save;
  }
}
