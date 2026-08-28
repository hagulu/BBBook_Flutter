import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// 답변 작성 입력창(본문 + 취소/등록).
///
/// 선택지 토론에서는 선택한 선택지 바로 아래에 인라인으로 열리고, 자유 토론
/// 에서는 "내 답변 작성" 카드 안에서 열린다. 두 경우 모두 등록 버튼은 본문이
/// 비어 있으면 비활성화된다.
class DiscussionAnswerComposer extends StatelessWidget {
  const DiscussionAnswerComposer({
    super.key,
    required this.controller,
    required this.hintText,
    required this.isSubmitting,
    required this.onCancel,
    required this.onSubmit,
    this.accentColor,
  });

  final TextEditingController controller;
  final String hintText;
  final bool isSubmitting;
  final VoidCallback onCancel;
  final VoidCallback onSubmit;

  /// 선택지 토론에서 선택한 선택지 색. 지정하면 입력창 포커스 테두리에 쓴다.
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? AppColors.accentForeground;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 8,
          style: const TextStyle(fontSize: 14, color: AppColors.textBody),
          decoration: InputDecoration(
            hintText: hintText,
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: accent, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: isSubmitting ? null : onCancel,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textMuted,
              ),
              child: const Text('취소'),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                final canSubmit = value.text.trim().isNotEmpty && !isSubmitting;
                return FilledButton(
                  onPressed: canSubmit ? onSubmit : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accentFill,
                    foregroundColor: AppColors.textStrong,
                    minimumSize: const Size(72, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  child: Text(isSubmitting ? '등록 중' : '등록'),
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}
