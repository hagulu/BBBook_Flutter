import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class BookMemoOcrWord {
  const BookMemoOcrWord({
    required this.text,
    required this.boundingBox,
    required this.lineOrder,
    required this.wordOrder,
  });

  final String text;
  final ui.Rect boundingBox;
  final int lineOrder;
  final int wordOrder;
}

class BookMemoOcrAnalysis {
  const BookMemoOcrAnalysis({required this.imageSize, required this.words});

  final ui.Size imageSize;
  final List<BookMemoOcrWord> words;
}

/// 촬영한 책 페이지를 한국어로 인식하고 단어별 이미지 좌표를 반환한다.
class BookMemoOcrService {
  const BookMemoOcrService();

  Future<BookMemoOcrAnalysis> analyzeImage(String imagePath) async {
    final stopwatch = Stopwatch()..start();
    final recognizer = TextRecognizer(script: TextRecognitionScript.korean);
    try {
      final imageSize = await _readImageSize(imagePath);
      final recognized = await recognizer.processImage(
        InputImage.fromFilePath(imagePath),
      );
      final words = <BookMemoOcrWord>[];
      var lineOrder = 0;
      for (final block in recognized.blocks) {
        for (final line in block.lines) {
          for (
            var wordOrder = 0;
            wordOrder < line.elements.length;
            wordOrder++
          ) {
            final element = line.elements[wordOrder];
            final text = element.text.trim();
            if (text.isEmpty) continue;
            words.add(
              BookMemoOcrWord(
                text: text,
                boundingBox: element.boundingBox,
                lineOrder: lineOrder,
                wordOrder: wordOrder,
              ),
            );
          }
          lineOrder++;
        }
      }
      developer.log(
        '[메모 발췌 OCR] target=ml_kit script=korean '
        'result=SUCCESS wordCount=${words.length} '
        'durationMs=${stopwatch.elapsedMilliseconds}',
      );
      return BookMemoOcrAnalysis(imageSize: imageSize, words: words);
    } catch (error, stackTrace) {
      developer.log(
        '[메모 발췌 OCR] target=ml_kit script=korean '
        'result=FAIL reason=image_text_recognition_error '
        'durationMs=${stopwatch.elapsedMilliseconds}',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    } finally {
      try {
        await recognizer.close();
      } catch (error, stackTrace) {
        developer.log(
          '[메모 발췌 OCR 해제] target=ml_kit '
          'result=FAIL reason=recognizer_close_error',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }

  Future<ui.Size> _readImageSize(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      try {
        return ui.Size(
          frame.image.width.toDouble(),
          frame.image.height.toDouble(),
        );
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }
}
