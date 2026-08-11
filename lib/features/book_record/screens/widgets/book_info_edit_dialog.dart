import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../bookshelf/models/book_category.dart';
import '../../../bookshelf/models/book_item.dart';
import '../../../bookshelf/providers/bookshelf_providers.dart';
import '../../../bookshelf/screens/widgets/book_cover.dart';
import '../../providers/book_record_providers.dart';
import 'record_dialog_shell.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// "책 정보 수정" 모달(제목/저자/출판사/총쪽수/표지). ISBN 재연결(검색 팝업)은
/// 책 검색 기능이 아직 이관되지 않아 이번 범위에서 제외한다.
Future<void> showBookInfoEditDialog(
  BuildContext context, {
  required int userBookId,
  required BookItem book,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) =>
        BookInfoEditDialog(userBookId: userBookId, book: book),
  );
}

/// 카테고리 선택 팝업 결과. 취소/바깥 탭으로 닫히면 `pop()`이 null을 반환해
/// 값이 그대로 유지되고, "미지정"을 명시적으로 고른 경우와 구분하기 위해
/// `categoryId`가 null이어도 결과 자체는 non-null 래퍼로 감싼다.
class _CategorySelection {
  const _CategorySelection(this.categoryId);

  final int? categoryId;
}

Future<_CategorySelection?> _showCategoryPickerDialog(
  BuildContext context, {
  required List<BookCategory> categories,
  required int? initialCategoryId,
}) {
  return showDialog<_CategorySelection>(
    context: context,
    builder: (context) => RecordDialogShell(
      icon: PhosphorIconsRegular.tag,
      title: '카테고리',
      content: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _CategoryChip(
            label: '미지정',
            dotColor: AppColors.mutedIcon,
            selected: initialCategoryId == null,
            onTap: () =>
                Navigator.of(context).pop(const _CategorySelection(null)),
          ),
          for (final category in categories)
            _CategoryChip(
              label: category.name,
              dotColor: category.color,
              selected: initialCategoryId == category.id,
              onTap: () => Navigator.of(
                context,
              ).pop(_CategorySelection(category.id)),
            ),
        ],
      ),
      buttons: [
        RecordDialogButton(
          label: '취소',
          style: RecordDialogButtonStyle.neutral,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
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

  static const _allowedThumbnailExtensions = {'jpg', 'jpeg', 'png', 'webp'};
  static const _maxThumbnailBytes = 5 * 1024 * 1024;

  /// 갤러리 접근 거부 등 [ImagePicker]가 던질 수 있는 플랫폼 예외를 잡아
  /// 화면이 죽지 않고 인라인 에러로 안내한다. 업로드 API가 거부하는 형식/
  /// 용량(jpeg·png·webp, 5MB)도 서버 왕복 없이 먼저 걸러 구체적인 이유를 보여준다.
  Future<void> _pickThumbnail() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      if (picked == null || !mounted) return;

      final extension = picked.path.split('.').last.toLowerCase();
      if (!_allowedThumbnailExtensions.contains(extension)) {
        setState(() => _errorText = 'JPEG, PNG, WebP 형식의 이미지만 사용할 수 있습니다.');
        return;
      }

      final file = File(picked.path);
      final sizeBytes = await file.length();
      if (!mounted) return;
      if (sizeBytes > _maxThumbnailBytes) {
        setState(() => _errorText = '이미지 용량은 5MB를 넘을 수 없습니다.');
        return;
      }

      setState(() {
        _pickedThumbnail = file;
        _removeThumbnail = false;
        _errorText = null;
      });
    } catch (_) {
      if (mounted) setState(() => _errorText = '이미지를 선택하지 못했습니다.');
    }
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

  Widget _categoryField(AsyncValue<List<BookCategory>> categoriesAsync) {
    final categories = categoriesAsync.valueOrNull;
    BookCategory? selectedCategory;
    if (categories != null) {
      for (final category in categories) {
        if (category.id == _selectedCategoryId) {
          selectedCategory = category;
          break;
        }
      }
    }

    Future<void> pickCategory() async {
      final result = await _showCategoryPickerDialog(
        context,
        categories: categories!,
        initialCategoryId: _selectedCategoryId,
      );
      if (result != null && mounted) {
        setState(() => _selectedCategoryId = result.categoryId);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('카테고리', style: _labelStyle),
        const SizedBox(height: 4),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: categories == null ? null : pickCategory,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            decoration: BoxDecoration(
              color: AppColors.inputBackground,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: selectedCategory?.color ?? AppColors.mutedIcon,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    selectedCategory?.name ?? '미지정',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.bodyText,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(
                  PhosphorIconsRegular.caretDown,
                  size: 14,
                  color: AppColors.mutedIcon,
                ),
              ],
            ),
          ),
        ),
      ],
    );
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
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 92,
                height: 92 * 3 / 2,
                child: _pickedThumbnail != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          _pickedThumbnail!,
                          fit: BoxFit.cover,
                        ),
                      )
                    : BookCover(
                        imageUrl: _hasThumbnail
                            ? widget.book.coverImageUrl
                            : null,
                        title: widget.book.title,
                        borderRadius: 12,
                      ),
              ),
              const SizedBox(width: 32),
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _ThumbnailActionButton(
                    icon: PhosphorIconsRegular.camera,
                    label: '표지 변경',
                    color: AppColors.primary,
                    onTap: _pickThumbnail,
                  ),
                  if (_hasThumbnail) ...[
                    const SizedBox(height: 8),
                    _ThumbnailActionButton(
                      icon: PhosphorIconsRegular.trash,
                      label: '표지 삭제',
                      color: AppColors.error,
                      onTap: _clearThumbnail,
                    ),
                  ],
                ],
              ),
            ],
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
              Expanded(child: _categoryField(categoriesAsync)),
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
        RecordDialogButton(
          label: '취소',
          style: RecordDialogButtonStyle.neutral,
          onPressed: () => Navigator.of(context).pop(),
        ),
        RecordDialogButton(label: '저장', onPressed: _save),
      ],
    );
  }
}

class _ThumbnailActionButton extends StatelessWidget {
  const _ThumbnailActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.inputBackground,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.dotColor,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color dotColor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? dotColor.withValues(alpha: 0.16)
                : AppColors.inputBackground,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? dotColor : Colors.transparent,
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppColors.bodyText : AppColors.tertiaryText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
