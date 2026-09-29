import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../core/config/ad_config.dart';
import '../../core/theme/app_theme.dart';
import '../ads/ads_enabled_provider.dart';

/// 여러 화면이 공유하는 배너 광고 영역. 광고 단위 ID는 [AdConfig] 한 곳에서만
/// 관리하므로 화면은 이 위젯만 배치하면 된다. [adsEnabledProvider]가
/// 꺼져 있으면(추후 광고 제거 구매 등) 아예 로드를 시도하지 않고 빈
/// 영역만 반환한다.
///
/// 로드 전/실패 시에는 빈 [SizedBox.shrink]만 차지해 불필요한 공간이나 빈
/// 광고 영역을 남기지 않는다. 로드에 성공하면 그때부터 표시 가능한 폭에
/// 맞춘 크기로 광고를 표시하고, 콘텐츠와 혼동되지 않도록 "광고" 라벨을
/// 함께 보여준다.
class AppBannerAd extends ConsumerStatefulWidget {
  const AppBannerAd({
    super.key,
    this.topSpacing = 0,
    this.bottomSpacing = 0,
    this.onResolvedHeight,
  });

  /// 광고가 실제로 로드되어 보일 때만 적용되는 위쪽/아래쪽 여백. 로드 전/실패
  /// 시에는 이 여백도 함께 사라져야 해서(불필요한 빈 공간 금지) 위젯
  /// 바깥에 별도 `SizedBox`를 두지 않고 이 값으로 받는다.
  final double topSpacing;
  final double bottomSpacing;

  /// 광고 로드 상태가 바뀔 때마다(로드 성공/실패) 이 위젯이 실제로 차지하게 될
  /// 전체 높이(로드 전/실패면 0)를 알려준다. 광고를 넣기 전에 스크롤 오프셋을
  /// 미리 계산해 둬야 하는 화면(완독 책장의 월 인덱스 스크러버 등)이 사용한다.
  ///
  /// 값은 라벨의 실제 줄 높이(시스템 글자 배율에 따라 달라짐)와 좁은 화면의
  /// 축소 표시까지 반영한 실측 높이다 — 가정한 상수 대신 프레임이 끝난
  /// 뒤 실제 렌더 크기를 읽는다.
  final ValueChanged<double>? onResolvedHeight;

  @override
  ConsumerState<AppBannerAd> createState() => _AppBannerAdState();
}

class _AppBannerAdState extends ConsumerState<AppBannerAd> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  final _contentKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (ref.read(adsEnabledProvider)) _loadAd();
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
          _reportResolvedHeightAfterLayout();
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (!mounted) return;
          setState(() {
            _bannerAd = null;
            _isLoaded = false;
          });
          widget.onResolvedHeight?.call(0);
        },
      ),
    );
    _bannerAd = bannerAd;
    bannerAd.load();
  }

  /// [_isLoaded]가 true로 바뀐 시점에는 아직 이 프레임이 실제로 그려지지
  /// 않아 [_contentKey]의 렌더 크기를 읽을 수 없다 — 레이아웃이 끝난 다음
  /// 프레임에서 측정한다.
  void _reportResolvedHeightAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final measuredHeight = _contentKey.currentContext?.size?.height;
      widget.onResolvedHeight?.call(
        measuredHeight ??
            widget.topSpacing + widget.bottomSpacing + AdSize.banner.height,
      );
    });
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(adsEnabledProvider)) return const SizedBox.shrink();

    final bannerAd = _bannerAd;
    if (!_isLoaded || bannerAd == null) return const SizedBox.shrink();

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
                      child: AdWidget(ad: bannerAd),
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
