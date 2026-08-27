import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';

import '../../../core/storage/local_image_store.dart';
import '../../book_note/models/book_note.dart';
import '../../book_note/services/note_memo_image_store.dart';
import '../../book_note/utils/memo_highlight.dart';
import 'reflection_image_store.dart';

/// [index, index+length) 범위가 이미지 embed와 겹치는지 검사한다.
///
/// `QuillController.replaceText()`는 `void`를 반환하고, `onReplaceText`가
/// 거부해도 그 사실을 호출부에 알려주지 않는다 — 그래서 이미지를 포함한
/// 범위에 프로그램적으로 삽입/치환을 시도하는 쪽([insert]/[insertImageBlock])은
/// `replaceText()`를 부르기 전에 이 판정을 직접 먼저 해서, 실제로 적용될
/// 교체에 대해서만 성공을 반환해야 한다. 편집 화면의 `onReplaceText`
/// 거부 판정(키보드 입력·붙여넣기 경로)도 같은 판정을 재사용해 두 곳이
/// 어긋나지 않게 한다.
bool documentRangeOverlapsImage(Document document, int index, int length) {
  if (length <= 0) return false;
  var operationStart = 0;
  final rangeEnd = index + length;
  for (final operation in document.toDelta().operations) {
    final operationEnd = operationStart + (operation.length ?? 0);
    final overlapsRange = operationStart < rangeEnd && operationEnd > index;
    final operationData = operation.data;
    if (overlapsRange &&
        operationData is Map &&
        operationData.containsKey(BlockEmbed.imageType)) {
      return true;
    }
    operationStart = operationEnd;
  }
  return false;
}

/// 노트 메모의 타입과 강조 마크업을 Quill 문서 서식으로 변환해 삽입한다.
///
/// 사진 메모는 사진 확보(네트워크/파일 I/O)와 문서 삽입을 분리해 둔다
/// ([resolvePhotoSource]/[insertPhoto]) — 호출부가 그 사이에 화면이 여전히
/// 살아 있는지 확인한 뒤에만 [QuillController]를 건드리게 하기 위해서다.
class BookReflectionMemoInsertService {
  const BookReflectionMemoInsertService();

  static const highlightColorValue = '#fef08a';

  /// `width`는 Quill에서 ignore scope 속성이라 `formatText()`의 기본 서식
  /// 규칙으로는 이미지에 적용되지 않는다. 이미지 operation을 retain하는
  /// Delta를 직접 compose해 너비를 저장하고 편집기를 다시 그린다.
  static void setImageWidth(
    QuillController controller, {
    required int offset,
    required double ratio,
  }) {
    final percentage = (ratio * 100).round().clamp(1, 100);
    final delta = Delta()
      ..retain(offset)
      ..retain(1, {Attribute.width.key: '$percentage%'});
    controller.compose(delta, controller.selection, ChangeSource.local);
  }

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
    if (documentRangeOverlapsImage(controller.document, start, end - start)) {
      return false;
    }
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
  }) {
    return insertImageBlock(
      controller,
      imageSource,
      caption: stripMemoHighlightMarkup(memo.content),
      selection: selection,
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
  }) {
    final documentText = controller.document.toPlainText();
    final currentSelection = selection ?? controller.selection;
    final start = currentSelection.start.clamp(0, documentText.length - 1);
    final end = currentSelection.end.clamp(start, documentText.length - 1);
    if (documentRangeOverlapsImage(controller.document, start, end - start)) {
      return false;
    }
    final needsLeadingNewline =
        start > 0 && documentText.codeUnitAt(start - 1) != 0x0A;

    final trimmedCaption = caption?.trim() ?? '';
    final insertion = Delta();
    var insertedLength = 0;
    if (needsLeadingNewline) {
      insertion.insert('\n');
      insertedLength += 1;
    }
    insertion
      ..insert(BlockEmbed.image(imageSource).toJson(), {
        Attribute.width.key: '100%',
      })
      ..insert('\n');
    insertedLength += 2;
    if (trimmedCaption.isNotEmpty) {
      insertion
        ..insert(trimmedCaption)
        ..insert('\n');
      insertedLength += trimmedCaption.length + 1;
    }
    // 사진(과 설명) 아래에 계속 작성할 빈 줄을 하나 둔다.
    insertion.insert('\n');
    insertedLength += 1;

    controller
      ..skipRequestKeyboard = true
      ..replaceText(start, end - start, insertion, null)
      ..skipRequestKeyboard = true
      ..updateSelection(
        TextSelection.collapsed(offset: start + insertedLength - 1),
        ChangeSource.local,
      );
    return true;
  }
}
