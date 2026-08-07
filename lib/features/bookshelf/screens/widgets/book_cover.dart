import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// 책 표지 썸네일. 이미지가 없거나 로드 실패 시 그라디언트 + 제목으로 대체한다.
class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.imageUrl, required this.title, this.borderRadius = 10});

  final String? imageUrl;
  final String title;
  final double borderRadius;

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
                  return Image.network(
                    url,
                    fit: BoxFit.cover,
                    cacheWidth: cacheWidth,
                    errorBuilder: (context, error, stackTrace) => _CoverPlaceholder(title: title),
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
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }
}
