import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../bookshelf/screens/widgets/book_cover.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

const _allowedThumbnailExtensions = {'jpg', 'jpeg', 'png', 'webp'};
const _maxThumbnailBytes = 5 * 1024 * 1024;

/// 표지 이미지 선택 결과. [file]이 non-null이면 성공, [error]가 non-null이면
/// 형식/용량 검증 실패, 둘 다 null이면 사용자가 선택을 취소한 것이다.
class ThumbnailPickResult {
  const ThumbnailPickResult({this.file, this.error});

  final File? file;
  final String? error;
}

/// 갤러리에서 책 표지 이미지를 선택하고 API가 허용하는 형식(JPEG/PNG/WebP)·
/// 용량(5MB)을 서버 왕복 없이 먼저 검증한다. `book_info_edit_dialog.dart`
/// (책 정보 수정)와 `custom_book_dialog.dart`(직접 등록)가 공유한다.
Future<ThumbnailPickResult?> pickBookThumbnail() async {
  try {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (picked == null) return null;

    final extension = picked.path.split('.').last.toLowerCase();
    if (!_allowedThumbnailExtensions.contains(extension)) {
      return const ThumbnailPickResult(
        error: 'JPEG, PNG, WebP 형식의 이미지만 사용할 수 있습니다.',
      );
    }

    final file = File(picked.path);
    final sizeBytes = await file.length();
    if (sizeBytes > _maxThumbnailBytes) {
      return const ThumbnailPickResult(error: '이미지 용량은 5MB를 넘을 수 없습니다.');
    }
    return ThumbnailPickResult(file: file);
  } catch (_) {
    return const ThumbnailPickResult(error: '이미지를 선택하지 못했습니다.');
  }
}

/// 표지 미리보기 + 변경/삭제 버튼 행. 선택 로직·상태는 호출부(폼)가 들고
/// 있고, 이 위젯은 현재 값을 그대로 그리기만 한다.
class BookThumbnailField extends StatelessWidget {
  const BookThumbnailField({
    super.key,
    required this.title,
    required this.currentCoverUrl,
    required this.pickedFile,
    required this.hasThumbnail,
    required this.onPick,
    required this.onRemove,
  });

  final String title;
  final String? currentCoverUrl;
  final File? pickedFile;

  /// 미리보기에 표지를 보여줄지 여부(선택된 파일이 있거나, 기존 표지가
  /// 있고 삭제하지 않은 경우).
  final bool hasThumbnail;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          height: 92 * 3 / 2,
          child: pickedFile != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(pickedFile!, fit: BoxFit.cover),
                )
              : BookCover(
                  imageUrl: hasThumbnail ? currentCoverUrl : null,
                  title: title,
                  borderRadius: 12,
                ),
        ),
        const SizedBox(width: 32),
        Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _ThumbnailActionButton(
              icon: PhosphorIconsRegular.camera,
              label: hasThumbnail ? '표지 변경' : '표지 추가',
              color: AppColors.primary,
              onTap: onPick,
            ),
            if (hasThumbnail) ...[
              const SizedBox(height: 8),
              _ThumbnailActionButton(
                icon: PhosphorIconsRegular.trash,
                label: '표지 삭제',
                color: AppColors.error,
                onTap: onRemove,
              ),
            ],
          ],
        ),
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
