/// `GET /api/me/reading-stats/profile-summary` 응답의 `mostReadCategory`.
class ProfileMostReadCategory {
  const ProfileMostReadCategory({
    required this.categoryId,
    required this.categoryName,
    required this.colorHex,
  });

  factory ProfileMostReadCategory.fromJson(Map<String, dynamic> json) {
    return ProfileMostReadCategory(
      categoryId: json['categoryId'] as int,
      categoryName: json['categoryName'] as String,
      colorHex: json['colorHex'] as String,
    );
  }

  final int categoryId;
  final String categoryName;
  final String colorHex;
}

/// `GET /api/me/reading-stats/profile-summary` 응답 데이터.
class ProfileStatsSummary {
  const ProfileStatsSummary({
    required this.finishedCount,
    required this.totalPages,
    required this.mostReadCategory,
  });

  factory ProfileStatsSummary.fromJson(Map<String, dynamic> json) {
    return ProfileStatsSummary(
      finishedCount: json['finishedCount'] as int? ?? 0,
      totalPages: json['totalPages'] as int? ?? 0,
      mostReadCategory: json['mostReadCategory'] == null
          ? null
          : ProfileMostReadCategory.fromJson(
              json['mostReadCategory'] as Map<String, dynamic>,
            ),
    );
  }

  final int finishedCount;
  final int totalPages;
  final ProfileMostReadCategory? mostReadCategory;
}
