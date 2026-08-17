import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// 책 기록 화면에서 반복되는 흰 카드 섹션 컨테이너. 그림자 스타일은
/// `reading_tab_view.dart`의 책장 카드와 통일한다.
class RecordSectionCard extends StatelessWidget {
  const RecordSectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowSoft,
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// 카드/섹션 제목에 공통으로 붙이는 아이콘+텍스트 라벨.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.accentForeground),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: AppColors.textStrong,
          ),
        ),
      ],
    );
  }
}
