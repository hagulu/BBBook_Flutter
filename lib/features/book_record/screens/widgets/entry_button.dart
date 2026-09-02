import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../../core/theme/app_theme.dart';
import 'record_section_card.dart';

/// `ReadingStatusTile`(책 기록 상세)과 같은 구성 — 원형 아이콘 배지 + 라벨 —
/// 을 카드(`RecordSectionCard`)에 가로로 담아 진입 버튼으로 쓴다.
class EntryButton extends StatelessWidget {
  const EntryButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.count,
    this.rating,
    this.compact = false,
    this.dense = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// 진입 대상 콘텐츠 개수 배지. null이면 표시하지 않는다(0은 배지로 표시).
  final int? count;

  /// 독자평 평균 별점(0.0~5.0). null이면 표시하지 않는다.
  final double? rating;

  /// true면 라벨과 평점/개수를 한 줄에 몰아넣지 않고 2줄로 나눠 보여준다
  /// (아이콘도 더 큼직하게). 생각나눔 탭의 세 진입 버튼이 이 규격을 쓴다.
  final bool compact;

  /// [compact]와 함께 써서, 폭 절반씩만 차지하는 가로 2단 배치(책 검색
  /// 상세의 독후감·토론 버튼)에서 아바타·여백을 더 줄여 라벨이 잘리지
  /// 않도록 한다.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return RecordSectionCard(
      padding: EdgeInsets.zero,
      // RecordSectionCard의 불투명 Container가 InkWell과 그 잉크를 그리는
      // 조상 Material 사이에 끼어 있으면 스플래시가 카드 배경 뒤에 가려진다.
      // 카드 장식 위(=하위)에 투명 Material을 둬서 잉크가 그 위에 그려지게 한다.
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: dense ? 10 : 16,
              vertical: compact ? 18 : 16,
            ),
            child: compact ? _buildCompact() : _buildSingleLine(),
          ),
        ),
      ),
    );
  }

  Widget _buildSingleLine() {
    return Row(
      children: [
        _Avatar(icon: icon),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textStrong,
            ),
          ),
        ),
        if (rating != null) ...[
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _RatingLabel(rating: rating!),
          ),
        ],
        if (count != null) ...[
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _CountBadge(count: count!),
          ),
        ],
        const Icon(
          PhosphorIconsRegular.caretRight,
          size: 18,
          color: AppColors.controlInactive,
        ),
      ],
    );
  }

  /// 라벨+평점(1줄) + 개수(2줄)로 나눠 보여준다. 아이콘을 [_buildSingleLine]
  /// 보다 크게 키워 존재감을 준다.
  Widget _buildCompact() {
    return Row(
      children: [
        _Avatar(
          icon: icon,
          radius: dense ? 18 : 24,
          iconSize: dense ? 18 : 24,
        ),
        SizedBox(width: dense ? 8 : 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: dense ? 14 : 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textStrong,
                      ),
                    ),
                  ),
                  if (rating != null) ...[
                    const SizedBox(width: 10),
                    _RatingLabel(rating: rating!),
                  ],
                ],
              ),
              if (count != null) ...[
                const SizedBox(height: 5),
                _CountBadge(count: count!),
              ],
            ],
          ),
        ),
        SizedBox(width: dense ? 2 : 4),
        Icon(
          PhosphorIconsRegular.caretRight,
          size: dense ? 16 : 20,
          color: AppColors.controlInactive,
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.icon, this.radius = 20, this.iconSize = 20});

  final IconData icon;
  final double radius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.accentSurface.withValues(alpha: 0.35),
      child: Icon(icon, color: AppColors.accentForeground, size: iconSize),
    );
  }
}

class _RatingLabel extends StatelessWidget {
  const _RatingLabel({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          PhosphorIconsFill.star,
          size: 13,
          color: AppColors.accentGraphic,
        ),
        const SizedBox(width: 3),
        Text(
          rating.toStringAsFixed(1),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textBody,
          ),
        ),
      ],
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}
