import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;

import '../../../core/image/image_compressor.dart';
import '../../../core/storage/local_image_store.dart';

/// 갤러리에서 이미지를 선택한다. 취소하면 null.
///
/// 기본적으로 이미지 정책([ImagePolicy])대로 압축한 임시 파일 경로를
/// 반환한다(긴 변 1600px 이하·JPEG 85%, iOS HEIC 등도 JPEG로 바뀐다).
/// OCR처럼 원본 해상도가 인식률에 영향을 주는 목적은 [compress]를 false로
/// 두어 원본 그대로 받는다.
Future<String?> pickImageFromGallery({bool compress = true}) async {
  // 정책 크기·품질을 picker에도 넘겨 플랫폼 디코더가 HEIC 등을 JPEG로
  // 바꾸고 큰 원본을 먼저 줄이게 한다(순수 Dart 디코더는 HEIC를 못 읽고
  // 고해상도 원본 전체를 디코딩하면 메모리를 많이 쓴다).
  final picked = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    imageQuality: compress ? ImagePolicy.jpegQuality : null,
    maxWidth: compress ? ImagePolicy.maxLongSide.toDouble() : null,
    maxHeight: compress ? ImagePolicy.maxLongSide.toDouble() : null,
  );
  if (picked == null) return null;
  if (!compress) return picked.path;
  return ImageCompressor.compressToTemp(picked.path);
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
