import '../models/public_reflection.dart';

/// 공개 독후감 조회 서비스가 의존하는 원격 데이터 경계.
abstract interface class PublicReflectionSource {
  Future<PublicReflectionsPage> fetchPage({
    required String isbn13,
    int? cursor,
    required int size,
  });

  Future<PublicReflectionDetail> fetchDetail(int reflectionId);

  Future<int> postLike(int reflectionId);

  Future<int> deleteLike(int reflectionId);
}
