import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;

import '../../../core/storage/local_image_store.dart';

/// 갤러리에서 이미지를 선택한다. 취소하면 null.
///
/// [imageQuality]/[maxWidth]를 지정하면 image_picker가 재인코딩하며
/// 압축한다(용량을 줄이고 iOS HEIC 등 원본 형식을 JPEG로 바꾼다). OCR처럼
/// 원본 해상도가 인식률에 영향을 주는 목적은 둘 다 비워 원본 그대로
/// 받는다.
Future<String?> pickImageFromGallery({int? imageQuality, double? maxWidth}) async {
  final picked = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    imageQuality: imageQuality,
    maxWidth: maxWidth,
  );
  return picked?.path;
}

/// [LocalImageStore]와 같은 형식(jpg/jpeg/png/webp)·용량(5MB) 제약으로
/// 이미지 파일을 검증한다. 문제가 없으면 null, 있으면 사용자에게 보여줄
/// 메시지를 반환한다.
Future<String?> validateImageFile(String filePath) async {
  final extension = path.extension(filePath).toLowerCase();
  if (!LocalImageStore.allowedExtensions.contains(extension)) {
    return '지원하지 않는 이미지 형식입니다.';
  }
  final file = File(filePath);
  if (!await file.exists()) return '이미지를 찾을 수 없습니다.';
  final sizeBytes = await file.length();
  if (sizeBytes == 0) return '이미지 파일이 손상되었습니다.';
  if (sizeBytes > LocalImageStore.maxBytes) {
    return '이미지 용량은 5MB 이하만 가능합니다.';
  }
  return null;
}
