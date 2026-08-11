import 'package:flutter/material.dart';

/// `GET /api/books/categories` 응답 항목(활성 카테고리, sort_order 오름차순).
/// 계정과 무관한 전역 마스터 데이터로, 커스텀 책 추가·책 정보 수정·서재
/// 필터에서 공통으로 쓴다. 로컬 DB(`book_category` 테이블)에 캐시되므로
/// 원본 [colorHex] 문자열을 그대로 들고 있다가 필요할 때만 [color]로 파싱한다.
class BookCategory {
  const BookCategory({
    required this.id,
    required this.code,
    required this.name,
    required this.colorHex,
  });

  factory BookCategory.fromJson(Map<String, dynamic> json) {
    return BookCategory(
      id: json['id'] as int,
      code: json['code'] as String,
      name: json['name'] as String,
      colorHex: json['colorHex'] as String,
    );
  }

  final int id;
  final String code;
  final String name;
  final String colorHex;

  Color get color {
    final normalized = colorHex.replaceFirst('#', '');
    return Color(int.parse('FF$normalized', radix: 16));
  }
}
