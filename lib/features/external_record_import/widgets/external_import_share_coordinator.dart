import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/app_snackbar.dart';
import '../../auth/providers/auth_access_providers.dart';
import '../../auth/providers/auth_notifier.dart';
import '../models/external_import_models.dart';
import '../providers/external_import_providers.dart';
import '../screens/external_import_screen.dart';
import '../services/external_share_service.dart';

class ExternalImportShareCoordinator extends ConsumerStatefulWidget {
  const ExternalImportShareCoordinator({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  ConsumerState<ExternalImportShareCoordinator> createState() =>
      _ExternalImportShareCoordinatorState();
}

class _ExternalImportShareCoordinatorState
    extends ConsumerState<ExternalImportShareCoordinator> {
  final _service = const ExternalShareService();
  final _pending = Queue<ExternalImportFileReference>();
  StreamSubscription<ExternalImportFileReference>? _subscription;
  var _opening = false;

  @override
  void initState() {
    super.initState();
    _subscription = _service.files.listen(
      _enqueue,
      onError: (Object error) {
        if (error is MissingPluginException) return;
        developer.log(
          '[외부 파일 공유] platform=ANDROID result=FAIL '
          'reason=event_channel_error',
        );
      },
    );
    unawaited(_loadInitialFile());
  }

  Future<void> _loadInitialFile() async {
    try {
      final file = await _service.initialFile();
      if (file != null && mounted) _enqueue(file);
    } on MissingPluginException {
      // Android 외 플랫폼 또는 플랫폼 채널이 없는 테스트 환경이다.
    } catch (_) {
      developer.log(
        '[외부 파일 공유] platform=ANDROID result=FAIL '
        'reason=initial_file_error',
      );
    }
  }

  void _enqueue(ExternalImportFileReference file) {
    _pending.add(file);
    developer.log('[외부 파일 공유] platform=ANDROID result=SUCCESS');
    _openNextWhenReady();
  }

  void _openNextWhenReady() {
    if (!mounted || _opening || _pending.isEmpty) return;
    // 외부 기록 가져오기는 서버 Import 세션을 쓴다 — 계정이 없으면 설정
    // 메뉴에서도 감춰 둔 기능이라 여기서도 열지 않고, 앱 밖에서 시작한
    // 동작이라 이유만 알리고 대기열을 비운다.
    if (!ref.read(canUseAccountFeaturesProvider)) {
      _discardPending();
      return;
    }
    if (!ref.read(authNotifierProvider).canUseApp) return;
    if (ref.read(externalImportExecutionLockProvider) != null) return;
    final navigator = widget.navigatorKey.currentState;
    if (navigator == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openNextWhenReady());
      return;
    }
    final file = _pending.removeFirst();
    _opening = true;
    unawaited(
      navigator
          .push<void>(
            MaterialPageRoute(builder: (_) => ExternalImportScreen(file: file)),
          )
          .whenComplete(() async {
            await _deleteCachedFile(file);
            _opening = false;
            _openNextWhenReady();
          }),
    );
  }

  void _discardPending() {
    final files = _pending.toList(growable: false);
    _pending.clear();
    for (final file in files) {
      unawaited(_deleteCachedFile(file));
    }
    developer.log('[외부 파일 공유] result=SKIP reason=login_required');
    final context = widget.navigatorKey.currentContext;
    if (context != null && context.mounted) {
      AppSnackBar.info(context, '다른 서비스 기록 가져오기는 로그인 후 사용할 수 있습니다.');
    }
  }

  Future<void> _deleteCachedFile(ExternalImportFileReference file) async {
    if (!file.deleteWhenDone || file.path.isEmpty) return;
    try {
      final cachedFile = File(file.path);
      if (await cachedFile.exists()) await cachedFile.delete();
    } catch (_) {
      developer.log('[외부 파일 임시 정리] result=FAIL reason=file_delete_failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authNotifierProvider, (_, _) => _openNextWhenReady());
    ref.listen(externalImportExecutionLockProvider, (_, next) {
      if (next == null) _openNextWhenReady();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _openNextWhenReady());
    return widget.child;
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
