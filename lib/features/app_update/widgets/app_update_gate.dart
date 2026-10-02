import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_dialog_shell.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../models/app_version_policy.dart';
import '../providers/app_update_providers.dart';
import '../services/app_update_service.dart';

/// 앱 전체를 감싸 버전 정책에 따라 업데이트를 안내한다.
///
/// - 권장: 팝업(업데이트 / 그만 보기). 같은 최신 버전은 세션당 한 번만 띄운다.
/// - 강제: 앱 전체를 덮는 차단 화면(업데이트만). 포그라운드 복귀 때마다 다시
///   확인하며, 정책을 못 받아도 이미 차단된 상태는 유지한다.
/// - 조회 실패는 조용히 무시한다(처음부터 실패하면 막지 않는다).
class AppUpdateGate extends ConsumerStatefulWidget {
  const AppUpdateGate({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  ConsumerState<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends ConsumerState<AppUpdateGate>
    with WidgetsBindingObserver {
  AppVersionPolicy? _forcedPolicy;
  bool _checking = false;
  bool _dialogShowing = false;
  bool _storeOpenFailed = false;
  BuildContext? _dialogContext;
  String? _promptedVersion;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_check());
  }

  String? get _platform => switch (defaultTargetPlatform) {
    TargetPlatform.android => 'ANDROID',
    TargetPlatform.iOS => 'IOS',
    _ => null,
  };

  Future<void> _check() async {
    final platform = _platform;
    if (platform == null || _checking) return;
    _checking = true;
    try {
      final policies = await ref.read(appVersionApiProvider).fetchPolicies();
      final packageInfo = await PackageInfo.fromPlatform();
      final dismissed = await ref.read(appUpdateDismissedStoreProvider).read();
      final decision = AppUpdateService.decide(
        currentVersion: packageInfo.version,
        policy: AppUpdateService.findPolicy(policies, platform),
        dismissedVersion: dismissed,
      );
      if (!mounted) return;
      setState(() {
        _forcedPolicy = decision.level == AppUpdateLevel.forced
            ? decision.policy
            : null;
        if (_forcedPolicy == null) _storeOpenFailed = false;
      });
      if (decision.level == AppUpdateLevel.forced) {
        _closeRecommendedDialog();
      } else if (decision.level == AppUpdateLevel.recommended) {
        // 팝업이 열려 있는 동안에도 복귀 시 정책을 다시 확인할 수 있도록
        // 조회 잠금은 팝업 완료를 기다리지 않고 풀어 둔다.
        unawaited(_showRecommended(decision.policy!));
      }
    } catch (error) {
      debugPrint('[앱 버전 확인] result=FAIL reason=${error.runtimeType}');
    } finally {
      _checking = false;
    }
  }

  /// 강제 업데이트로 바뀌면 열려 있던 권장 팝업을 저장 없이 닫는다.
  void _closeRecommendedDialog() {
    final dialogContext = _dialogContext;
    if (dialogContext != null && dialogContext.mounted) {
      Navigator.of(dialogContext).pop();
    }
  }

  Future<void> _showRecommended(AppVersionPolicy policy) async {
    if (_dialogShowing || _promptedVersion == policy.latestVersion) return;
    final context = widget.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    _promptedVersion = policy.latestVersion;
    _dialogShowing = true;
    try {
      final update = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          _dialogContext = dialogContext;
          return AppDialogShell(
            title: '업데이트 안내',
            message: _messageOf(policy),
            actions: [
              AppDialogAction(
                label: '그만 보기',
                style: AppDialogActionStyle.neutral,
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              AppDialogAction(
                label: '업데이트',
                style: AppDialogActionStyle.primary,
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
            ],
          );
        },
      );
      if (update == true) {
        if (!await _openStore(policy)) _showStoreErrorSnackBar();
      } else if (update == false) {
        await ref
            .read(appUpdateDismissedStoreProvider)
            .save(policy.latestVersion);
      }
    } finally {
      _dialogContext = null;
      _dialogShowing = false;
    }
  }

  String _messageOf(AppVersionPolicy policy, {bool forced = false}) {
    final message = policy.updateMessage?.trim();
    if (message != null && message.isNotEmpty) return message;
    if (forced) return '원활한 이용을 위해 업데이트가 필요해요. 업데이트 후 계속 이용할 수 있어요.';
    return '새로운 버전(${policy.latestVersion})이 출시되었습니다.';
  }

  /// 스토어를 열었으면 true. 실패 안내는 호출부가 화면 상황에 맞게 보여준다.
  Future<bool> _openStore(AppVersionPolicy policy) async {
    final url = policy.storeUrl?.trim();
    final uri = (url == null || url.isEmpty) ? null : Uri.tryParse(url);
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  static const _storeErrorMessage = '스토어를 열 수 없습니다. 스토어에서 직접 업데이트해 주세요.';

  /// 루트 Navigator 자체의 context에는 Overlay 조상이 없으므로 Overlay의
  /// context를 쓴다.
  void _showStoreErrorSnackBar() {
    final context = widget.navigatorKey.currentState?.overlay?.context;
    if (context != null && context.mounted) {
      AppSnackBar.error(context, _storeErrorMessage);
    }
  }

  Future<void> _openStoreFromForcedScreen(AppVersionPolicy policy) async {
    final opened = await _openStore(policy);
    if (mounted) setState(() => _storeOpenFailed = !opened);
  }

  @override
  Widget build(BuildContext context) {
    final forced = _forcedPolicy;
    // child의 상태(공유 파일 대기 큐 등)가 강제 전환으로 초기화되지 않도록
    // 항상 같은 Stack 구조를 유지하고 차단 레이어만 덧붙인다.
    return Stack(
      children: [
        ExcludeFocus(excluding: forced != null, child: widget.child),
        if (forced != null) ...[
          // 뒤로 가기를 여기서 소비해, 아래 화면의 종료 확인 팝업 등이 뜨지 않게 한다.
          BackButtonListener(
            onBackButtonPressed: () async => true,
            child: const SizedBox.shrink(),
          ),
          const Positioned.fill(
            child: ModalBarrier(dismissible: false, color: Color(0x99000000)),
          ),
          Positioned.fill(
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.zero,
                  child: AppDialogShell(
                    title: '업데이트가 필요해요',
                    message: _messageOf(forced, forced: true),
                    content: _storeOpenFailed
                        ? Text(
                            _storeErrorMessage,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.of(context).error,
                            ),
                          )
                        : null,
                    actions: [
                      AppDialogAction(
                        label: '업데이트',
                        style: AppDialogActionStyle.primary,
                        onPressed: () =>
                            unawaited(_openStoreFromForcedScreen(forced)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
