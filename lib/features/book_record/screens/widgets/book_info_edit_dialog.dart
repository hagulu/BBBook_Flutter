import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../bookshelf/models/book_item.dart';
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
  String? _errorText;

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

  @override
  Widget build(BuildContext context) {
    return RecordDialogShell(
      icon: PhosphorIconsRegular.bookOpen,
      title: '책 정보 수정',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                SizedBox(
                  width: 92,
                  height: 92 * 3 / 2,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _pickedThumbnail != null
                        ? Image.file(_pickedThumbnail!, fit: BoxFit.cover)
                        : (_hasThumbnail
                              ? Image.network(
                                  widget.book.coverImageUrl!,
                                  fit: BoxFit.cover,
                                )
                              : const ColoredBox(
                                  color: AppColors.inputBackground,
                                )),
                  ),
                ),
                Positioned(
                  right: -8,
                  bottom: -8,
                  child: _CircleIconButton(
                    icon: PhosphorIconsRegular.camera,
                    background: AppColors.primary,
                    onTap: _pickThumbnail,
                  ),
                ),
                if (_hasThumbnail)
                  Positioned(
                    left: -8,
                    top: -8,
                    child: _CircleIconButton(
                      icon: PhosphorIconsRegular.x,
                      background: AppColors.error,
                      size: 16,
                      onTap: _clearThumbnail,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _titleController,
            maxLength: 255,
            decoration: const InputDecoration(
              isDense: true,
              labelText: '제목',
              counterText: '',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _authorController,
            maxLength: 255,
            decoration: const InputDecoration(
              isDense: true,
              labelText: '저자',
              counterText: '',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _publisherController,
            maxLength: 255,
            decoration: const InputDecoration(
              isDense: true,
              labelText: '출판사',
              counterText: '',
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: 120,
            child: TextField(
              controller: _totalPagesController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                isDense: true,
                labelText: '총 쪽수',
              ),
            ),
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

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.background,
    required this.onTap,
    this.size = 18,
  });

  final IconData icon;
  final Color background;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, color: Colors.white, size: size),
        ),
      ),
    );
  }
}
