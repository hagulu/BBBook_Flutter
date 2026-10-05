import 'dart:io';
import 'dart:isolate';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// 서비스 전체 이미지 정책 — 메모·독후감·표지·프로필 등 모든 이미지에
/// 같은 값을 적용한다.
abstract final class ImagePolicy {
  /// 가로/세로 중 긴 변의 최대 길이(px). 이보다 작은 이미지는 확대하지 않는다.
  static const maxLongSide = 1600;

  /// JPEG 압축 품질(%).
  static const jpegQuality = 85;
}

/// 이미지 압축·리사이즈 공통 로직.
///
/// 원본 종횡비를 유지하며 긴 변을 [ImagePolicy.maxLongSide] 이하로 줄이고
/// EXIF 회전을 픽셀에 반영한 뒤 JPEG([ImagePolicy.jpegQuality])로
/// 재인코딩한다. 디코딩·인코딩은 UI 스레드를 막지 않도록 isolate에서 한다.
class ImageCompressor {
  const ImageCompressor._();

  /// [compressToTemp]가 만든 파일 이름 접두어. 이미 정책대로 처리된 파일을
  /// 저장 단계에서 한 번 더 재인코딩(화질 손실)하지 않도록 구분하는 표지다.
  static const processedPrefix = 'bbbook_img_';

  static bool isProcessed(String filePath) =>
      path.basename(filePath).startsWith(processedPrefix);

  /// [sourcePath]를 정책대로 압축해 [destinationPath]에 쓴다. 이미지를
  /// 해석할 수 없으면 [FileSystemException]을 던진다.
  static Future<void> compressToFile(
    String sourcePath,
    String destinationPath,
  ) async {
    final ok = await Isolate.run(() => _compress(sourcePath, destinationPath));
    if (!ok) {
      throw FileSystemException('이미지 파일이 손상되었습니다.', sourcePath);
    }
  }

  /// 앱 임시 디렉터리에 압축본을 만들고 그 경로를 반환한다.
  static Future<String> compressToTemp(String sourcePath) async {
    final directory = await getTemporaryDirectory();
    final destination = path.join(
      directory.path,
      '$processedPrefix${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await compressToFile(sourcePath, destination);
    return destination;
  }
}

bool _compress(String sourcePath, String destinationPath) {
  final decoded = img.decodeImage(File(sourcePath).readAsBytesSync());
  if (decoded == null) return false;

  var image = img.bakeOrientation(decoded);
  final longSide = image.width > image.height ? image.width : image.height;
  if (longSide > ImagePolicy.maxLongSide) {
    image = image.width >= image.height
        ? img.copyResize(
            image,
            width: ImagePolicy.maxLongSide,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            image,
            height: ImagePolicy.maxLongSide,
            interpolation: img.Interpolation.average,
          );
  }

  // JPEG는 투명도를 지원하지 않아 알파가 있는 PNG/WebP는 검은 배경이
  // 되므로 흰 배경에 합성한다.
  if (image.hasAlpha) {
    final background = img.Image(
      width: image.width,
      height: image.height,
      numChannels: 3,
    )..clear(img.ColorRgb8(255, 255, 255));
    image = img.compositeImage(background, image);
  }

  File(destinationPath).writeAsBytesSync(
    img.encodeJpg(image, quality: ImagePolicy.jpegQuality),
    flush: true,
  );
  return true;
}
