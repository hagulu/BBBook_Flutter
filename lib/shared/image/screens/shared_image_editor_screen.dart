import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

import '../../widgets/app_alert.dart';

/// 이미지 에디터가 노출하는 기능 범위.
enum SharedImageEditorProfile {
  /// 크롭·회전·텍스트 입력·자유 그리기(메모 사진, 독후감 본문 이미지 등
  /// 사용자가 직접 촬영·선택한 일반 이미지).
  general,

  /// 크롭·회전만(OCR 촬영 이미지 — 인식 대상 문장을 텍스트/그리기로 가릴
  /// 이유가 없다).
  cropRotateOnly,
}

/// 공용 이미지 에디터를 열고 편집 결과를 앱 임시 디렉터리의 JPEG 파일로
/// 저장한 뒤 그 경로를 반환한다. 취소(변경 없이 닫기)하면 null.
Future<String?> openSharedImageEditor(
  BuildContext context, {
  required String imagePath,
  required SharedImageEditorProfile profile,
}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) =>
          _SharedImageEditorScreen(imagePath: imagePath, profile: profile),
    ),
  );
}

class _SharedImageEditorScreen extends StatefulWidget {
  const _SharedImageEditorScreen({
    required this.imagePath,
    required this.profile,
  });

  final String imagePath;
  final SharedImageEditorProfile profile;

  @override
  State<_SharedImageEditorScreen> createState() =>
      _SharedImageEditorScreenState();
}

class _SharedImageEditorScreenState extends State<_SharedImageEditorScreen> {
  // Done을 누르면 pro_image_editor가 onImageEditingComplete에 이어
  // onCloseEditor도 함께 호출한다 — 두 콜백이 모두 pop을 시도하면 화면이
  // 한 단계 더 닫히는 사고로 이어지므로, 이 화면이 이미 pop됐는지 여기서
  // 직접 지킨다.
  bool _hasPopped = false;

  @override
  Widget build(BuildContext context) {
    return ProImageEditor.file(
      File(widget.imagePath),
      configs: ProImageEditorConfigs(
        mainEditor: MainEditorConfigs(tools: _toolsFor(widget.profile)),
        imageGeneration: _imageGenerationFor(widget.profile),
      ),
      callbacks: ProImageEditorCallbacks(
        onImageEditingComplete: (bytes) => _finish(context, bytes),
        onCloseEditor: (_) => _cancel(context),
      ),
    );
  }

  List<SubEditorMode> _toolsFor(SharedImageEditorProfile profile) {
    switch (profile) {
      case SharedImageEditorProfile.general:
        return const [
          SubEditorMode.cropRotate,
          SubEditorMode.text,
          SubEditorMode.paint,
        ];
      case SharedImageEditorProfile.cropRotateOnly:
        return const [SubEditorMode.cropRotate];
    }
  }

  ImageGenerationConfigs _imageGenerationFor(SharedImageEditorProfile profile) {
    switch (profile) {
      case SharedImageEditorProfile.general:
        return const ImageGenerationConfigs(
          outputFormat: OutputFormat.jpg,
          jpegQuality: 85,
        );
      case SharedImageEditorProfile.cropRotateOnly:
        // OCR은 인식률을 위해 원본 해상도를 최대한 보존한다 — 일반
        // 프로필의 기본 상한(2000×2000)을 그대로 쓰면 고해상도 촬영본·
        // 갤러리 이미지가 작은 글자를 읽기 어려운 크기로 줄어든다.
        return const ImageGenerationConfigs(
          outputFormat: OutputFormat.jpg,
          jpegQuality: 90,
          maxOutputSize: Size(6000, 6000),
        );
    }
  }

  /// 결과 바이트가 비어 있거나(캡처 실패) 임시 파일 쓰기가 실패하면
  /// 사용자가 취소한 것처럼 조용히 넘기지 않고 실패를 알린다. "Done"을
  /// 누르면 pro_image_editor가 이 콜백 다음에 [onCloseEditor]도 호출해
  /// 화면을 닫으므로, 여기서는 pop하지 않고 알림만 보여준 뒤 그 close가
  /// 자연스럽게 화면을 정리하게 둔다.
  Future<void> _finish(BuildContext context, Uint8List bytes) async {
    if (_hasPopped) return;
    if (bytes.isEmpty) {
      if (context.mounted) {
        await AppAlert.show(
          context,
          title: '이미지를 만들지 못했습니다',
          message: '다시 시도해 주세요.',
        );
      }
      return;
    }
    String? savedPath;
    try {
      final temporaryDirectory = await getTemporaryDirectory();
      final candidatePath = path.join(
        temporaryDirectory.path,
        'edited_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await File(candidatePath).writeAsBytes(bytes, flush: true);
      savedPath = candidatePath;
    } catch (_) {
      savedPath = null;
    }
    if (savedPath == null) {
      if (context.mounted) {
        await AppAlert.show(
          context,
          title: '이미지를 저장하지 못했습니다',
          message: '잠시 후 다시 시도해 주세요.',
        );
      }
      return;
    }
    _hasPopped = true;
    if (context.mounted) Navigator.of(context).pop(savedPath);
  }

  void _cancel(BuildContext context) {
    if (_hasPopped) return;
    _hasPopped = true;
    if (context.mounted) Navigator.of(context).pop();
  }
}
