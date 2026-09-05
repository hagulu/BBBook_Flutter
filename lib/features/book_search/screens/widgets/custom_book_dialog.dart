import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../book_detail/screens/widgets/add_status_dialog.dart';
import '../../../book_record/models/record_labels.dart';
import '../../../book_record/providers/book_record_providers.dart';
import '../../../book_record/screens/widgets/book_category_field.dart';
import '../../../book_record/screens/widgets/book_thumbnail_field.dart';
import '../../../book_record/screens/widgets/finish_confirm_dialog.dart';
import '../../../../shared/widgets/record_dialog_shell.dart';
import '../../../book_record/screens/widgets/record_field_tile.dart';
import '../../../bookshelf/models/book_status.dart';
import '../../../bookshelf/models/record_patch.dart';
import '../../../bookshelf/providers/bookshelf_providers.dart';

/// "직접 등록" 모달(book-search.md, `CustomBookModal` add 모드 대응). 항목은
/// 책 기록 상세의 "책 정보 수정" 팝업(표지/제목/저자/출판사/카테고리/총쪽수)과
/// 동일하게 구성하고, 새로 서재에 추가하는 화면이라 독서 상태 선택을 더한다.
///
/// 성공하면 새로 만들어진 userBookId와 로컬 DB 동기화 확인 여부([synced])를
/// 반환하고, 취소/바깥 탭이면 null을 반환한다. 서버 등록은 됐지만 동기화가
/// 아직 반영되지 않았을 수 있어([BookshelfSyncController.ensureSynced]),
/// 호출부는 [synced]가 false면 로컬 DB를 바로 읽는 책 기록 상세로 이동하지
/// 않아야 한다(존재하지 않는 행이라 "책을 찾을 수 없습니다"로 막힌다).
Future<({int userBookId, bool synced})?> showCustomBookDialog(
  BuildContext context,
) {
  return showModalBottomSheet<({int userBookId, bool synced})>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const _CustomBookDialog(),
  );
}

class _CustomBookDialog extends ConsumerStatefulWidget {
  const _CustomBookDialog();

  @override
  ConsumerState<_CustomBookDialog> createState() => _CustomBookDialogState();
}

class _CustomBookDialogState extends ConsumerState<_CustomBookDialog> {
  final _titleController = TextEditingController();
  final _authorController = TextEditingController();
  final _publisherController = TextEditingController();
  final _totalPagesController = TextEditingController();

  File? _pickedThumbnail;
  int? _selectedCategoryId;
  BookStatus _status = BookStatus.reading;
  FinishConfirmResult? _finishOptions;
  String? _errorText;

  static const _labelStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: AppColors.textMuted,
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
      _errorText = null;
    });
  }

  void _clearThumbnail() {
    setState(() => _pickedThumbnail = null);
  }

  Future<void> _pickStatus() async {
    final status = await showAddStatusDialog(context);
    if (status == null || !mounted) return;

    if (status == BookStatus.finished) {
      final options = await showFinishConfirmDialog(
        context,
        showSource: true,
        showDifficulty: true,
        showRatingReview: true,
        showFinishedAt: true,
      );
      if (options == null || !mounted) return;
      setState(() {
        _status = status;
        _finishOptions = options;
      });
    } else {
      setState(() {
        _status = status;
        _finishOptions = null;
      });
    }
  }

  String get _statusSummary =>
      _status == BookStatus.finished ? '완독(정보 입력됨)' : _status.label;

  String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

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
      final options = _finishOptions;
      final book = await ref
          .read(bookshelfRepositoryProvider)
          .createCustomBook(
            title: title,
            author: _authorController.text.trim().isEmpty
                ? null
                : _authorController.text.trim(),
            publisher: _publisherController.text.trim().isEmpty
                ? null
                : _publisherController.text.trim(),
            statsTotalPages: totalPages,
            categoryId: _selectedCategoryId,
            thumbnailFile: _pickedThumbnail,
            status: _status,
            sourceType: options?.sourceType?.apiValue,
            myRating: options?.myRating,
            shortReview: options?.shortReview,
            difficulty: options?.difficulty,
            wantToReread: options?.wantToReread ?? false,
            finishedAt: options?.finishedAt == null
                ? null
                : _formatDate(options!.finishedAt!),
          );
      // 명작은 생성 API가 받지 않으므로 생성 직후 로컬 우선 PATCH로 남긴다.
      // CREATE가 오프라인으로 대기 중이어도 dirty 필드가 보존돼, 생성 확정
      // 후 이어지는 PATCH 재시도에서 사용자가 고른 값을 반영한다.
      if (options?.isMasterpiece == true) {
        await ref
            .read(bookRecordRepositoryProvider)
            .updateRecord(
              book.userBookId,
              const RecordPatch(isMasterpiece: true),
            );
      }
      ref.read(bookshelfSyncVersionProvider.notifier).state++;
      if (mounted) {
        Navigator.of(context).pop((userBookId: book.userBookId, synced: true));
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorText = e.message);
    } catch (e) {
      // ApiException만 잡으면 로컬 DB 예외 등은 안내 없이 조용히 사라진다.
      developer.log('[서재 추가] result=FAIL reason=${e.runtimeType}');
      if (mounted) setState(() => _errorText = '서재에 추가하지 못했습니다.');
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
      title: '직접 등록',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BookThumbnailField(
            title: _titleController.text.isEmpty
                ? '책 표지'
                : _titleController.text,
            currentCoverUrl: null,
            pickedFile: _pickedThumbnail,
            hasThumbnail: _pickedThumbnail != null,
            onPick: _pickThumbnail,
            onRemove: _clearThumbnail,
          ),
          const SizedBox(height: 20),
          _labeledField(
            label: '제목',
            controller: _titleController,
            maxLength: 255,
          ),
          const SizedBox(height: 10),
          _labeledField(
            label: '저자',
            controller: _authorController,
            maxLength: 255,
          ),
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
          const SizedBox(height: 12),
          RecordFieldTile(
            label: '독서 상태',
            value: _statusSummary,
            hasValue: true,
            valueIcon: _status.icon,
            onTap: _pickStatus,
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
      buttons: [RecordDialogButton(label: '등록', onPressed: _save)],
    );
  }
}
