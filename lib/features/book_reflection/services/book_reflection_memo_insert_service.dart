import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../../core/storage/local_image_store.dart';
import '../../book_note/models/book_note.dart';
import '../../book_note/services/note_memo_image_store.dart';
import '../../book_note/utils/memo_highlight.dart';
import 'reflection_image_store.dart';

/// 노트 메모의 타입과 강조 마크업을 Quill 문서 서식으로 변환해 삽입한다.
///
/// 사진 메모는 사진 확보(네트워크/파일 I/O)와 문서 삽입을 분리해 둔다
/// ([resolvePhotoSource]/[insertPhoto]) — 호출부가 그 사이에 화면이 여전히
/// 살아 있는지 확인한 뒤에만 [QuillController]를 건드리게 하기 위해서다.
class BookReflectionMemoInsertService {
  const BookReflectionMemoInsertService();

  static const highlightColorValue = '#fef08a';

  /// 텍스트형 메모(요약/발췌/생각)를 즉시 삽입한다.
  bool insert(
    QuillController controller,
    BookNoteMemo memo, {
    TextSelection? selection,
  }) {
    final parsed = parseMemoHighlight(memo.content);
    if (parsed.plainText.trim().isEmpty) return false;

    final documentText = controller.document.toPlainText();
    final currentSelection = selection ?? controller.selection;
    final start = currentSelection.start.clamp(0, documentText.length - 1);
    final end = currentSelection.end.clamp(start, documentText.length - 1);
    final isQuote = memo.type == BookNoteMemoType.quote;
    final needsLeadingNewline =
        isQuote && start > 0 && documentText.codeUnitAt(start - 1) != 0x0A;
    final needsTrailingNewline =
        isQuote &&
        end < documentText.length &&
        documentText.codeUnitAt(end) != 0x0A;
    final leading = needsLeadingNewline ? '\n' : '';
    final trailing = needsTrailingNewline ? '\n' : '';
    final insertedText = '$leading${parsed.plainText}$trailing';
    final contentStart = start + leading.length;

    controller
      ..skipRequestKeyboard = true
      ..replaceText(
        start,
        end - start,
        insertedText,
        TextSelection.collapsed(offset: start + insertedText.length),
      )
      ..formatText(
        contentStart,
        parsed.plainText.length,
        const BackgroundAttribute(null),
      );

    for (final range in parsed.ranges) {
      controller.formatText(
        contentStart + range.start,
        range.end - range.start,
        const BackgroundAttribute(highlightColorValue),
      );
    }
    if (isQuote) {
      controller.formatText(
        contentStart,
        parsed.plainText.length,
        Attribute.blockQuote,
      );
    }
    return true;
  }

  /// 사진 메모의 사진을 독후감 본문 이미지 저장소(`reflection_images/`)로
  /// 실체화해 본문에 넣을 출처 문자열을 반환한다. 실패하면 null이다.
  ///
  /// 1순위는 메모의 로컬 사본(`memo_images/`)을 복사한 것이다 — 서버로
  /// push할 때 이 사본이 그대로 업로드 대상이 된다. 로컬 사본이 없거나 이미
  /// 사라졌으면 서버 URL을 같은 저장소로 내려받는다. 원본 메모 URL을 그대로
  /// 본문에 남기지는 않는다 — 원본 메모가 나중에 삭제되거나 URL이 만료되면
  /// 독후감 본문 이미지가 영구히 깨지기 때문이다. 실패는 예외 대신 null로
  /// 알린다(호출부가 삽입 실패로 처리해 사용자에게 안내한다).
  Future<String?> resolvePhotoSource(BookNoteMemo memo) async {
    try {
      final localImagePath = memo.localImagePath;
      if (localImagePath != null) {
        final file = await noteMemoImageStore.resolve(localImagePath);
        if (file != null && await file.exists()) {
          return await reflectionImageStore.saveSelected(file.path);
        }
      }
      final imageUrl = memo.imageUrl;
      if (imageUrl == null) return null;
      final downloaded = await reflectionImageStore.ensureDownloaded(imageUrl);
      if (downloaded.status == LocalImageDownloadStatus.stored) {
        return downloaded.localImagePath;
      }
      return null;
    } catch (_) {
      developer.log('[독후감 사진 메모 삽입] result=FAIL reason=image_resolve_error');
      return null;
    }
  }

  /// [resolvePhotoSource]로 확보한 사진을 이미지 임베드로 삽입하고, 설명이
  /// 있으면 그 아래 줄에 붙인다. 원본 메모의 사진 파일은 건드리지 않는다.
  /// 네트워크/파일 I/O 없이 문서만 동기적으로 바꾸므로, 호출부가 이 사이에
  /// 화면이 여전히 유효한지 확인해 두면 사라진 컨트롤러를 건드릴 일이 없다.
  bool insertPhoto(
    QuillController controller,
    BookNoteMemo memo,
    String imageSource, {
    TextSelection? selection,
    required double bodyWidth,
  }) {
    return insertImageBlock(
      controller,
      imageSource,
      caption: stripMemoHighlightMarkup(memo.content),
      selection: selection,
      bodyWidth: bodyWidth,
    );
  }

  /// 이미지를 자기 줄에 임베드로 넣고, [caption]이 있으면 그 아래 줄에
  /// 붙인 뒤, 항상 그 밑에 빈 줄을 하나 더 만들어 커서를 둔다 — 사진을 넣은
  /// 직후 바로 이어서 쓸 수 있게 하기 위해서다. 메모 사진 삽입([insertPhoto])
  /// 과 편집기 도구모음의 수동 사진 첨부가 이 로직을 공유한다.
  bool insertImageBlock(
    QuillController controller,
    String imageSource, {
    String? caption,
    TextSelection? selection,
    required double bodyWidth,
  }) {
    final documentText = controller.document.toPlainText();
    final currentSelection = selection ?? controller.selection;
    final start = currentSelection.start.clamp(0, documentText.length - 1);
    final end = currentSelection.end.clamp(start, documentText.length - 1);
    final needsLeadingNewline =
        start > 0 && documentText.codeUnitAt(start - 1) != 0x0A;

    controller
      ..skipRequestKeyboard = true
      ..replaceText(start, end - start, '', TextSelection.collapsed(offset: start));

    var index = start;
    if (needsLeadingNewline) {
      controller
        ..skipRequestKeyboard = true
        ..replaceText(index, 0, '\n', TextSelection.collapsed(offset: index + 1));
      index += 1;
    }

    controller
      ..skipRequestKeyboard = true
      ..replaceText(
        index,
        0,
        BlockEmbed.image(imageSource),
        TextSelection.collapsed(offset: index + 1),
      )
      ..formatText(index, 1, WidthAttribute(bodyWidth.toStringAsFixed(1)));
    var cursor = index + 1;

    final trimmedCaption = caption?.trim() ?? '';
    if (trimmedCaption.isNotEmpty) {
      final captionText = '\n$trimmedCaption';
      controller
        ..skipRequestKeyboard = true
        ..replaceText(
          cursor,
          0,
          captionText,
          TextSelection.collapsed(offset: cursor + captionText.length),
        );
      cursor += captionText.length;
      // 삽입 지점에 형광펜 등 서식이 걸려 있으면 새 텍스트가 그 서식을
      // 그대로 물려받는다 — 설명 텍스트만 서식 없이 보이도록 리셋한다.
      controller.formatText(
        cursor - trimmedCaption.length,
        trimmedCaption.length,
        const BackgroundAttribute(null),
      );
    }

    // 사진(과 설명) 줄을 닫고 그 아래 빈 줄을 하나 더 만든다 — 이어서
    // 타이핑할 자리를 항상 마련해 둔다.
    controller
      ..skipRequestKeyboard = true
      ..replaceText(
        cursor,
        0,
        '\n\n',
        TextSelection.collapsed(offset: cursor + 1),
      );
    controller.moveCursorToPosition(cursor + 1);
    return true;
  }
}
