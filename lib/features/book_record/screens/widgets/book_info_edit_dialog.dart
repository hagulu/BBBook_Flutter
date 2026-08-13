import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../bookshelf/models/book_item.dart';
import '../../../bookshelf/providers/bookshelf_providers.dart';
import '../../providers/book_record_providers.dart';
import 'book_category_field.dart';
import 'book_thumbnail_field.dart';
import 'record_dialog_shell.dart';

/// "책 정보 수정" 모달(제목/저자/출판사/총쪽수/표지/카테고리). ISBN 재연결
/// (검색 팝업)은 책 검색 기능이 아직 이관되지 않아 이번 범위에서 제외한다.
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
      (!_removeThumbnail && (widget.book.coverImageUrl?.isNotEmpty ?? false));

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
            currentCoverUrl: widget.book.coverImageUrl,
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
