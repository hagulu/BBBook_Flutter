import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/finished_cover_cache_manager.dart';

/// 책 표지 썸네일. 이미지가 없거나 로드 실패 시 그라디언트 + 제목으로 대체한다.
class BookCover extends StatelessWidget {
  const BookCover({
    super.key,
    required this.imageUrl,
    required this.title,
    this.borderRadius = 10,
    this.useDiskCache = false,
  });

  final String? imageUrl;
  final String title;
  final double borderRadius;

  /// true면 리사이즈된 이미지를 디스크에 캐시해 재방문 시 원본 디코딩을
  /// 건너뛴다(완독 목록처럼 카드 수가 많아 스크롤 시 반복 디코딩 비용이 큰
  /// 화면에서만 켠다).
  final bool useDiskCache;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    return AspectRatio(
      aspectRatio: 2 / 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: url == null || url.isEmpty
            ? _CoverPlaceholder(title: title)
            : LayoutBuilder(
                builder: (context, constraints) {
                  // 화면엔 그리드 셀 크기(대략 3열 썸네일)로만 표시되는데 서버
                  // 원본 해상도로 디코딩하면 스크롤 중 새 카드가 나타날 때마다
                  // 큰 이미지 디코딩·GPU 업로드가 반복돼 버벅임의 주요 원인이
                  // 된다. 실제 렌더 폭 × devicePixelRatio로 디코딩 목표 폭만
                  // 지정하고 높이는 원본 비율에 맡긴다.
                  final dpr = MediaQuery.devicePixelRatioOf(context);
                  final cacheWidth = constraints.maxWidth.isFinite
                      ? (constraints.maxWidth * dpr).round()
                      : null;

                  if (!useDiskCache || cacheWidth == null) {
                    return Image.network(
                      url,
                      fit: BoxFit.cover,
                      cacheWidth: cacheWidth,
                      errorBuilder: (context, error, stackTrace) =>
                          _CoverPlaceholder(title: title),
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const ColoredBox(color: AppColors.border);
                      },
                    );
                  }

                  // 인메모리 이미지 캐시는 (provider, 디코딩 폭)을 키로 쓰므로,
                  // 레이아웃 폭이 1px 단위로 흔들려도 같은 캐시 항목을 재사용하도록
                  // 8px 단위로 반올림해 키를 안정시킨다.
                  final bucketedCacheWidth = ((cacheWidth + 7) ~/ 8) * 8;
                  // 원본 바이트만 디스크에 캐시하고(재요청 없이 재사용), 디코딩
                  // 크기 제한은 항상 ResizeImage로 건다 — flutter_cache_manager의
                  // 디스크 리사이즈(maxWidth)는 JPG/PNG 등 일부 포맷에서만 동작하고,
                  // 그 경로를 타면 원본 디코딩 1회 + 리사이즈 디코딩 1회 + PNG
                  // 인코딩까지 콜드 캐시 스크롤 경로에서 수행해 오히려 더 무거워진다.
                  return Image(
                    image: ResizeImage.resizeIfNeeded(
                      bucketedCacheWidth,
                      null,
                      CachedNetworkImageProvider(
                        url,
                        cacheManager: FinishedCoverCacheManager.instance,
                      ),
                    ),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        _CoverPlaceholder(title: title),
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const ColoredBox(color: AppColors.border);
                    },
                  );
                },
              ),
      ),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.accentLight, AppColors.accent],
        ),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8),
      child: Text(
        title,
        textAlign: TextAlign.center,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}
