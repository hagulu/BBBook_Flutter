import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/community_content.dart';
import '../../../../shared/widgets/record_dialog_shell.dart';
import '../../models/discussion_answer.dart';
import '../../models/discussion_topic.dart';
import '../../utils/discussion_date.dart';
import '../../utils/discussion_poll.dart';
import 'discussion_poll.dart';

/// 답변 카드 한 장. "..." 메뉴의 수정을 누르면 카드가 인라인 편집 모드로
/// 바뀌며, 선택 배너는 그대로 두고 본문만 편집한다(웹과 동일 — 답변 수정에
/// 선택지 변경 UI는 없다).
class DiscussionAnswerItem extends StatefulWidget {
  const DiscussionAnswerItem({
    super.key,
    required this.answer,
    required this.options,
    required this.canEdit,
    required this.onSubmitEdit,
    required this.onDelete,
    required this.onReport,
    required this.onToggleLike,
  });

  final DiscussionAnswer answer;

  /// 선택 배너 색·라벨을 찾기 위한 주제의 선택지 목록(자유 토론이면 비어 있다).
  final List<DiscussionOption> options;

  /// 닫힌 토론에서는 수정 메뉴가 노출되지 않는다(삭제만 가능).
  final bool canEdit;

  /// 편집 확정. 성공하면 true를 반환해야 편집 모드가 닫힌다.
  final Future<bool> Function(String content) onSubmitEdit;
  final VoidCallback onDelete;
  final VoidCallback onReport;
  final VoidCallback onToggleLike;

  @override
  State<DiscussionAnswerItem> createState() => _DiscussionAnswerItemState();
}

class _DiscussionAnswerItemState extends State<DiscussionAnswerItem> {
  TextEditingController? _editController;
  bool _isSaving = false;

  bool get _isEditing => _editController != null;

  @override
  void dispose() {
    _editController?.dispose();
    super.dispose();
  }

  void _startEdit() {
    setState(() {
      _editController = TextEditingController(
        text: widget.answer.content ?? '',
      );
    });
  }

  void _cancelEdit() {
    _editController?.dispose();
    setState(() => _editController = null);
  }

  Future<void> _submitEdit() async {
    final content = _editController?.text.trim() ?? '';
    if (content.isEmpty || _isSaving) return;

    setState(() => _isSaving = true);
    try {
      final succeeded = await widget.onSubmitEdit(content);
      if (!mounted) return;
      if (succeeded) {
        _editController?.dispose();
        _editController = null;
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final answer = widget.answer;

    return CommunityContentCard(
      padding: const EdgeInsets.all(14),
      borderRadius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_isEditing)
            CommunityAuthorRow(
              nickname: answer.user.nickname,
              profileImageUrl: answer.user.profileImageUrl,
              dateLabel: formatDiscussionDateTime(answer.createdAt),
              avatarRadius: 13,
              layout: CommunityAuthorLayout.stacked,
              trailing: answer.isHidden ? null : _buildMenu(answer),
            ),
          if (answer.isHidden)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                '숨김 처리된 답변입니다.',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
            )
          else ...[
            if (answer.hasVote) ...[
              const SizedBox(height: 10),
              DiscussionVoteBanner(
                label: discussionOptionLabelOf(widget.options, answer.optionId),
                color: discussionOptionColorOf(widget.options, answer.optionId),
              ),
            ],
            const SizedBox(height: 10),
            if (_isEditing)
              _EditForm(
                controller: _editController!,
                isSaving: _isSaving,
                onCancel: _cancelEdit,
                onSubmit: _submitEdit,
              )
            else ...[
              Text(
                answer.content ?? '',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textBody,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1, color: AppColors.border),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: CommunityLikeButton(
                  isLiked: answer.likedByMe,
                  likeCount: answer.likeCount,
                  onTap: widget.onToggleLike,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildMenu(DiscussionAnswer answer) {
    if (!answer.isMine) {
      return IconButton(
        padding: EdgeInsets.zero,
        tooltip: '답변 신고',
        icon: const Icon(
          PhosphorIconsRegular.flag,
          size: 16,
          color: AppColors.textMuted,
        ),
        onPressed: widget.onReport,
      );
    }

    return CommunityMoreButton(
      tooltip: '답변 메뉴',
      iconSize: 18,
      onTap: () => _openMenuSheet(context),
    );
  }

  Future<void> _openMenuSheet(BuildContext context) async {
    final action = await showModalBottomSheet<_AnswerMenuAction>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => RecordDialogShell(
        title: '답변 관리',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.canEdit)
              CommunityMenuTile(
                icon: PhosphorIconsRegular.pencilSimple,
                label: '수정',
                onTap: () =>
                    Navigator.pop(sheetContext, _AnswerMenuAction.edit),
              ),
            CommunityMenuTile(
              icon: PhosphorIconsRegular.trash,
              label: '삭제',
              color: AppColors.error,
              onTap: () =>
                  Navigator.pop(sheetContext, _AnswerMenuAction.delete),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _AnswerMenuAction.edit:
        _startEdit();
      case _AnswerMenuAction.delete:
        widget.onDelete();
    }
  }
}

class _EditForm extends StatelessWidget {
  const _EditForm({
    required this.controller,
    required this.isSaving,
    required this.onCancel,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool isSaving;
  final VoidCallback onCancel;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 8,
          style: const TextStyle(fontSize: 14, color: AppColors.textBody),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: isSaving ? null : onCancel,
              style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
              child: const Text('취소'),
            ),
            const SizedBox(width: 4),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                final canSubmit = value.text.trim().isNotEmpty && !isSaving;
                return FilledButton(
                  onPressed: canSubmit ? onSubmit : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accentFill,
                    foregroundColor: AppColors.textStrong,
                    minimumSize: const Size(64, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  child: const Text('수정'),
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}

enum _AnswerMenuAction { edit, delete }
