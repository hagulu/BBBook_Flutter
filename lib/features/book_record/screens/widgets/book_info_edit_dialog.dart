import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_confirm.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../book_detail/providers/book_detail_providers.dart';
import '../../../bookshelf/models/book_item.dart';
import '../../../bookshelf/providers/bookshelf_providers.dart';
import '../../providers/book_record_providers.dart';
import 'book_category_field.dart';
import 'book_thumbnail_field.dart';
import 'isbn_link_dialog.dart';
import 'isbn_link_search_sheet.dart';
import 'record_dialog_shell.dart';

/// "책 정보 수정" 모달(제목/저자/출판사/총쪽수/표지/카테고리/ISBN 연결).
Future<void> showBookInfoEditDialog(
  BuildContext context, {
  required int userBookId,
  required BookItem book,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) =>
        BookInfoEditDialog(userBookId: userBookId, book: book),
  );
}

class BookInfoEditDialog extends ConsumerStatefulWidget {
  const BookInfoEditDialog({
    super.key,
    required this.userBookId,
    required this.book,
  });

  final int userBookId;
  final BookItem book;

  @override
  ConsumerState<BookInfoEditDialog> createState() => _BookInfoEditDialogState();
}

class _BookInfoEditDialogState extends ConsumerState<BookInfoEditDialog> {
  late final _titleController = TextEditingController(text: widget.book.title);
  late final _authorController = TextEditingController(
    text: widget.book.author ?? '',
  );
  late final _publisherController = TextEditingController(
    text: widget.book.publisher ?? '',
  );
  late final _totalPagesController = TextEditingController(
    text: widget.book.totalPages?.toString() ?? '',
  );

  File? _pickedThumbnail;
  bool _removeThumbnail = false;
  late int? _selectedCategoryId = widget.book.displayCategoryId;
  late String? _currentCoverUrl = widget.book.coverImageUrl;
  late String? _isbn13 = widget.book.isbn13;
  String? _errorText;

  static const _labelStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: AppColors.tertiaryText,
  );

  @override
  void dispose() {
    _titleController.dispose();
    _authorController.dispose();
    _publisherController.dispose();
    _totalPagesController.dispose();
    super.dispose();
  }

  Future<void> _pickThumbnail() async {
    final result = await pickBookThumbnail();
    if (result == null || !mounted) return;
    if (result.error != null) {
      setState(() => _errorText = result.error);
      return;
    }
    setState(() {
      _pickedThumbnail = result.file;
      _removeThumbnail = false;
      _errorText = null;
    });
  }

  void _clearThumbnail() {
    setState(() {
      _pickedThumbnail = null;
      _removeThumbnail = true;
    });
  }

  bool get _hasThumbnail =>
      _pickedThumbnail != null ||
      (!_removeThumbnail && (_currentCoverUrl?.isNotEmpty ?? false));

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _errorText = '제목을 입력해주세요.');
      return;
    }
    final totalPagesText = _totalPagesController.text.trim();
    final totalPages = totalPagesText.isEmpty
        ? null
        : int.tryParse(totalPagesText);
    if (totalPagesText.isNotEmpty && totalPages == null) {
      setState(() => _errorText = '총 쪽수는 숫자로 입력해주세요.');
      return;
    }

    setState(() => _errorText = null);
    AppLoading.show(context);
    try {
      // ISBN 연결/변경/해제는 액션 시트에서 바로 서버에 반영하지 않고 폼
      // 상태(_isbn13)만 바꿔둔다(검색 결과를 고르면 입력창만 채워질 뿐 —
      // book_info_edit_dialog.dart 상단 흐름 참고). "저장"을 누르면 원래
      // 값과 달라진 항목만 한 번에 반영한다. `PATCH .../link`는 응답의
      // display_* 필드를 연결한 책 데이터로 덮어써 돌려주지만(api-doc), 그
      // 값을 그대로 로컬에 반영하는 대신 아래 [updateBookInfo]로 현재 폼에
      // 보이는 값(연결 직후 사용자가 다시 손댔을 수도 있는 값)을 이어서
      // 저장한다 — 그래야 "선택 → 추가로 손보기 → 저장"이 그대로 반영된다.
      // 이 두 요청 사이에 실패가 나서 저장을 다시 눌러도, 같은 책으로
      // 재연결하는 건 문서상 중복으로 취급하지 않아 다시 보내도 안전하다.
      if (_isbn13 != widget.book.isbn13) {
        await ref
            .read(bookRecordControllerProvider(widget.userBookId).notifier)
            .linkBook(isbn13: _isbn13);
      }
      await ref
          .read(bookRecordControllerProvider(widget.userBookId).notifier)
          .updateBookInfo(
            title: title,
            author: _authorController.text.trim().isEmpty
                ? null
                : _authorController.text.trim(),
            publisher: _publisherController.text.trim().isEmpty
                ? null
                : _publisherController.text.trim(),
            totalPages: totalPages,
            categoryId: _selectedCategoryId,
            // 파일 업로드/삭제가 없고, ISBN 불러오기·변경으로 표지 URL이
            // 원래 값과 달라졌을 때만 그 URL을 함께 저장한다(그러지 않으면
            // 미리보기에는 새 표지가 보이지만 실제로는 반영되지 않는다).
            coverImageUrl:
                _pickedThumbnail == null &&
                    !_removeThumbnail &&
                    _currentCoverUrl != widget.book.coverImageUrl
                ? _currentCoverUrl
                : null,
            thumbnailFile: _pickedThumbnail,
            removeThumbnail: _removeThumbnail,
          );
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorText = e.message);
    } finally {
      AppLoading.hide();
    }
  }

  Future<void> _handleIsbnTap() async {
    // 연결 안 된 책은 고를 액션이 "연결"(검색) 하나뿐이라 액션 시트를 거치지
    // 않고 바로 검색 결과로 들어간다. 연결된 책만 불러오기/변경/연결 끊기
    // 중에서 고르도록 액션 시트를 띄운다.
    if (_isbn13 == null) {
      await _openChangeSearch();
      return;
    }

    final action = await showIsbnLinkActionSheet(context);
    if (action == null || !mounted) return;
    switch (action) {
      case IsbnLinkAction.reload:
        await _fillFromIsbn(_isbn13!, message: '책 정보를 다시 불러왔습니다. 저장을 눌러 반영해주세요.');
      case IsbnLinkAction.change:
        await _openChangeSearch();
      case IsbnLinkAction.unlink:
        await _unlinkIsbnPending();
    }
  }

  Future<void> _openChangeSearch() async {
    final query = [
      widget.book.title,
      if (widget.book.publisher != null && widget.book.publisher!.isNotEmpty)
        widget.book.publisher!,
    ].join(' ');
    final selectedIsbn = await showIsbnLinkSearchSheet(
      context,
      initialQuery: query,
    );
    if (selectedIsbn == null || !mounted) return;
    await _fillFromIsbn(selectedIsbn, message: '책 정보를 불러왔습니다. 저장을 눌러 반영해주세요.');
  }

  /// 선택한 ISBN의 공개 책 정보(`GET /api/books/:isbn` — 조회 전용, 서재에는
  /// 아무 영향 없음)로 입력창만 채운다. 실제로 서재에 연결/반영되는 시점은
  /// "저장" 버튼을 눌렀을 때다.
  Future<void> _fillFromIsbn(String isbn, {required String message}) async {
    AppLoading.show(context);
    try {
      final detail = await ref.read(bookDetailApiProvider).getBookDetail(isbn);
      if (!mounted) return;
      setState(() {
        _titleController.text = detail.title;
        _authorController.text = detail.author ?? '';
        _publisherController.text = detail.publisher ?? '';
        _totalPagesController.text = detail.pageCount > 0
            ? detail.pageCount.toString()
            : '';
        _selectedCategoryId = detail.categoryId;
        _currentCoverUrl = detail.coverUrl;
        _pickedThumbnail = null;
        _removeThumbnail = false;
        _isbn13 = isbn;
        _errorText = null;
      });
      AppSnackBar.info(context, message);
    } on ApiException catch (e) {
      if (mounted) AppSnackBar.error(context, e.message);
    } finally {
      AppLoading.hide();
    }
  }

  Future<void> _unlinkIsbnPending() async {
    final confirmed = await AppConfirm.show(
      context,
      title: '연결 끊기',
      message: '책 연결을 끊을까요? 표시 중인 책 정보는 그대로 남고, 저장을 눌러야 실제로 반영됩니다.',
      confirmText: '연결 끊기',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _isbn13 = null);
  }

  Widget _labeledField({
    required String label,
    required TextEditingController controller,
    int? maxLength,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _labelStyle),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          maxLength: maxLength,
          keyboardType: keyboardType,
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(isDense: true, counterText: ''),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(bookCategoriesProvider);
    return RecordDialogShell(
      title: '책 정보 수정',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BookThumbnailField(
            title: widget.book.title,
            currentCoverUrl: _currentCoverUrl,
            pickedFile: _pickedThumbnail,
            hasThumbnail: _hasThumbnail,
            onPick: _pickThumbnail,
            onRemove: _clearThumbnail,
          ),
          const SizedBox(height: 20),
          _labeledField(label: '제목', controller: _titleController, maxLength: 255),
          const SizedBox(height: 10),
          _labeledField(label: '저자', controller: _authorController, maxLength: 255),
          const SizedBox(height: 10),
          _labeledField(
            label: '출판사',
            controller: _publisherController,
            maxLength: 255,
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: BookCategoryField(
                  categories: categoriesAsync.valueOrNull,
                  selectedCategoryId: _selectedCategoryId,
                  onChanged: (id) => setState(() => _selectedCategoryId = id),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 120,
                child: _labeledField(
                  label: '총 쪽수',
                  controller: _totalPagesController,
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _IsbnField(isbn13: _isbn13, onTap: _handleIsbnTap),
          if (_errorText != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorText!,
              style: const TextStyle(color: AppColors.error, fontSize: 12),
            ),
          ],
        ],
      ),
      buttons: [
        RecordDialogButton(label: '저장', onPressed: _save),
      ],
    );
  }
}

/// ISBN 표시 행. 직접 수정할 수 없고, 터치하면 연결 관리 액션 시트가 뜬다.
class _IsbnField extends StatelessWidget {
  const _IsbnField({required this.isbn13, required this.onTap});

  final String? isbn13;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ISBN',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.tertiaryText,
          ),
        ),
        const SizedBox(height: 4),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            decoration: BoxDecoration(
              color: AppColors.inputBackground,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  PhosphorIconsRegular.link,
                  size: 15,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isbn13 ?? '책 정보 연결',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const Icon(
                  PhosphorIconsRegular.caretRight,
                  size: 14,
                  color: AppColors.primary,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
