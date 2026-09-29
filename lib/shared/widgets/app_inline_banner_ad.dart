import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../core/config/ad_config.dart';
import '../../core/theme/app_theme.dart';
import '../ads/ads_enabled_provider.dart';

/// 목록/그리드 "중간"에 끼워 넣는 배너 광고 전용 위젯.
///
/// 화면 상단/하단에 붙는 [AppBannerAd]와 달리, 이 위젯은 광고가 아직
/// 로드되기 전부터 광고가 들어갈 자리와 높이를 먼저 차지한다("광고" 라벨 +
/// 빈 배너 영역). 로드에 성공하면 같은 자리 안에서 실제 광고로 바뀔 뿐
/// 크기가 달라지지 않으므로, 사용자가 이미 스크롤해 지나간 목록이 광고
/// 로드 때문에 아래로 밀리지 않는다. 오직 로드에 실패했을 때만 확보해
/// 두었던 자리를 완전히 치운다(빈 광고 영역을 남기지 않음).
///
/// 완독 책장처럼 목록 하나에 슬롯이 여러 개 들어갈 수 있는 화면에서는,
/// 자리는 미리 확보하되 실제 `BannerAd.load()`(네트워크 요청 + 네이티브
/// 광고 객체 생성) 자체는 이 슬롯이 화면(뷰포트) 가까이 올 때까지
/// 미룬다. 반대로 로드된 뒤 화면에서 한참 멀어지면(스크롤이 계속
/// 이어지는 긴 목록에서 지나온 슬롯들) 붙들고 있던 `BannerAd`를 해제해,
/// 끝까지 스크롤할수록 네이티브 광고 객체가 계속 쌓이는 일을 막는다 —
/// 다시 그 근처로 돌아오면 자연스럽게 다시 로드된다.
class AppInlineBannerAd extends ConsumerStatefulWidget {
  const AppInlineBannerAd({
    super.key,
    this.topSpacing = 0,
    this.bottomSpacing = 0,
    this.onResolvedHeight,
  });

  /// 자리를 확보한 상태(대기 중 또는 로드 성공)일 때만 적용되는 위쪽/아래쪽
  /// 여백. 로드 실패로 자리를 치우면 이 여백도 함께 사라진다.
  final double topSpacing;
  final double bottomSpacing;

  /// 이 위젯이 실제로 차지하는 높이가 정해지거나 바뀔 때 알려준다 — 자리를
  /// 확보한 레이아웃 직후(대기 중이어도) 그리고 시스템 글자 크기가 바뀌어
  /// 실제 렌더 높이가 달라질 때마다 다시 호출되고, 로드 실패로 자리를
  /// 치울 때는 0으로 호출된다. 스크롤 오프셋을 미리 계산해 둬야 하는
  /// 화면(완독 책장의 월 인덱스 스크러버 등)이 사용한다.
  final ValueChanged<double>? onResolvedHeight;

  @override
  ConsumerState<AppInlineBannerAd> createState() => _AppInlineBannerAdState();
}

class _AppInlineBannerAdState extends ConsumerState<AppInlineBannerAd> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  bool _failed = false;
  bool _loadTriggered = false;
  final _contentKey = GlobalKey();
  ScrollPosition? _observedPosition;

  /// 뷰포트 앞뒤로 이 배수(화면 높이 기준) 안에 들어오면 로드를 시작한다.
  static const _loadMarginMultiplier = 2.0;

  /// 로드된 뒤에는 이보다 더 멀어져야 해제한다 — 로드/해제 경계 바로
  /// 앞뒤로 스크롤을 오갈 때 반복 로드·해제(thrashing)가 일어나지 않도록
  /// [_loadMarginMultiplier]보다 넉넉한 여유를 둔다.
  static const _unloadMarginMultiplier = 4.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateLoadState();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (!identical(position, _observedPosition)) {
      _observedPosition?.removeListener(_updateLoadState);
      _observedPosition = position;
      _observedPosition?.addListener(_updateLoadState);
    }
    // MediaQuery(텍스트 배율 등) 같은 의존성이 바뀔 때마다(최초 빌드
    // 포함) 다시 불려, 시스템 글자 크기가 바뀌어도 실제 렌더 높이를 다시
    // 알려준다 — 그러지 않으면 이전 배율의 높이가 [_adSlotHeights](완독
    // 책장 등)에 그대로 남아 월 이동 오프셋이 어긋난다.
    _reportResolvedHeightAfterLayout();
  }

  void _reportResolvedHeightAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _failed) return;
      final measuredHeight = _contentKey.currentContext?.size?.height;
      if (measuredHeight != null) widget.onResolvedHeight?.call(measuredHeight);
    });
  }

  /// 스크롤할 때마다 불려, 뷰포트 근처에 들어오면 로드를 시작하고 로드된
  /// 뒤 충분히 멀어지면 붙들고 있던 [BannerAd]를 해제한다.
  void _updateLoadState() {
    if (!mounted) return;
    if (!_loadTriggered) {
      if (!ref.read(adsEnabledProvider)) return;
      if (_isNearViewport(_loadMarginMultiplier)) {
        _loadTriggered = true;
        _loadAd();
      }
      return;
    }
    if (_failed) return;
    if (!_isNearViewport(_unloadMarginMultiplier)) {
      _unloadAd();
    }
  }

  /// 스크롤 컨테이너를 찾지 못하거나(예: 위젯 테스트) 위치 계산이
  /// 실패하면 보수적으로 "근처"로 판단한다.
  bool _isNearViewport(double marginMultiplier) {
    final position = _observedPosition;
    if (position == null) return true;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return false;
    try {
      final viewport = RenderAbstractViewport.of(renderObject);
      final revealOffset = viewport.getOffsetToReveal(renderObject, 0).offset;
      final margin = position.viewportDimension * marginMultiplier;
      return revealOffset <= position.pixels + margin &&
          revealOffset >= position.pixels - margin;
    } catch (_) {
      return true;
    }
  }

  void _loadAd() {
    final bannerAd = BannerAd(
      adUnitId: AdConfig.bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (!mounted) return;
          setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (!mounted) return;
          setState(() {
            _bannerAd = null;
            _isLoaded = false;
            _failed = true;
          });
          widget.onResolvedHeight?.call(0);
        },
      ),
    );
    _bannerAd = bannerAd;
    bannerAd.load();
  }

  /// 화면에서 충분히 멀어진 슬롯의 네이티브 광고 객체를 해제한다. 자리
  /// 크기는 그대로 유지되므로(로드 전과 같은 빈 배너 영역) 목록이 다시
  /// 움직이지 않고, 다음에 근처로 돌아오면 [_updateLoadState]가 자연히
  /// 다시 로드한다.
  void _unloadAd() {
    _bannerAd?.dispose();
    _bannerAd = null;
    _loadTriggered = false;
    if (!mounted) return;
    setState(() => _isLoaded = false);
  }

  @override
  void dispose() {
    _observedPosition?.removeListener(_updateLoadState);
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(adsEnabledProvider)) return const SizedBox.shrink();
    if (_failed) return const SizedBox.shrink();

    final bannerAd = _bannerAd;
    return Padding(
      key: _contentKey,
      padding: EdgeInsets.only(
        top: widget.topSpacing,
        bottom: widget.bottomSpacing,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '광고',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.of(context).textMuted,
              ),
            ),
          ),
          const SizedBox(height: 4),
          // 320dp 고정 폭이 화면 폭(좌우 여백 제외)보다 넓을 수 있는 좁은
          // 화면에서도 잘리지 않도록, 남는 폭이 부족할 때만 비율을 유지한
          // 채 축소한다(여유가 있으면 원래 크기 그대로).
          LayoutBuilder(
            builder: (context, constraints) {
              final bannerWidth = AdSize.banner.width.toDouble();
              final bannerHeight = AdSize.banner.height.toDouble();
              final targetWidth =
                  constraints.maxWidth.isFinite &&
                      constraints.maxWidth < bannerWidth
                  ? constraints.maxWidth
                  : bannerWidth;
              return Center(
                child: SizedBox(
                  width: targetWidth,
                  height: bannerHeight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: bannerWidth,
                      height: bannerHeight,
                      // 로드 전/해제 후에는 같은 크기의 빈 자리만 차지하고,
                      // 성공하면 그 안에서 실제 광고로 바뀐다 — 크기가
                      // 그대로라 아래 콘텐츠가 밀리지 않는다.
                      child: _isLoaded && bannerAd != null
                          ? AdWidget(ad: bannerAd)
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
