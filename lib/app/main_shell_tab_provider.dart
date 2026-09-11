import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 로그인 후 메인 셸의 현재 탭(0=책장, 1=마이).
final mainShellTabIndexProvider = StateProvider.autoDispose<int>((ref) => 0);
