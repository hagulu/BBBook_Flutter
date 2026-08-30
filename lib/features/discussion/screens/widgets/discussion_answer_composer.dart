import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/record_dialog_shell.dart';
import 'discussion_poll.dart';

/// 답변 작성 바텀시트(본문 입력 + 등록). 선택지 토론이면 상단에 선택한
/// 선택지를 [DiscussionVoteBanner]로 보여준 채로 의견을 적게 하고, 자유
/// 토론이면 선택지 표시 없이 본문만 입력한다.
///
/// [onSubmit]이 성공(true)을 반환하면 시트를 닫고, 실패(false)를 반환하면
/// 입력값을 유지한 채 다시 등록할 수 있게 열어 둔다(에러 안내는 호출부가
/// 스낵바로 표시).
Future<void> showDiscussionAnswerSheet(
  BuildContext context, {
  required String hintText,
  required Future<bool> Function(String content) onSubmit,
  String? selectedOptionLabel,
  Color? accentColor,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _DiscussionAnswerSheet(
      hintText: hintText,
      selectedOptionLabel: selectedOptionLabel,
      accentColor: accentColor,
      onSubmit: onSubmit,
    ),
  );
}

class _DiscussionAnswerSheet extends StatefulWidget {
  const _DiscussionAnswerSheet({
    required this.hintText,
    required this.onSubmit,
    this.selectedOptionLabel,
    this.accentColor,
  });

  final String hintText;
  final Future<bool> Function(String content) onSubmit;
  final String? selectedOptionLabel;
  final Color? accentColor;

  @override
  State<_DiscussionAnswerSheet> createState() => _DiscussionAnswerSheetState();
}

class _DiscussionAnswerSheetState extends State<_DiscussionAnswerSheet> {
  final _controller = TextEditingController();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // 본문이 비어 있으면 등록 버튼을 비활성화하기 위해 입력마다 다시
    // 그린다(빈 답변으로 눌러도 조용히 무시되던 문제).
    _controller.addListener(_handleContentChanged);
  }

  void _handleContentChanged() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_handleContentChanged);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final content = _controller.text.trim();
    if (content.isEmpty || _isSubmitting) return;
    setState(() => _isSubmitting = true);
    final success = await widget.onSubmit(content);
    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop();
    } else {
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor ?? AppColors.accentForeground;

    return RecordDialogShell(
      title: '답변 작성',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.selectedOptionLabel != null) ...[
            DiscussionVoteBanner(
              label: widget.selectedOptionLabel!,
              color: accent,
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            style: const TextStyle(fontSize: 14, color: AppColors.textBody),
            decoration: InputDecoration(
              hintText: widget.hintText,
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: accent, width: 1.5),
              ),
            ),
          ),
        ],
      ),
      buttons: [
        RecordDialogButton(
          label: _isSubmitting ? '등록 중' : '등록',
          onPressed: _controller.text.trim().isNotEmpty && !_isSubmitting
              ? _submit
              : null,
        ),
      ],
    );
  }
}
