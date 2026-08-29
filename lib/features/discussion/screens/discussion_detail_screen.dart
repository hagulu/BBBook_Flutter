import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_bar_title.dart';
import '../../../shared/widgets/app_confirm.dart';
import '../../../shared/widgets/app_loading.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/community_content.dart';
import '../../../shared/widgets/record_dialog_shell.dart';
import '../../book_detail/screens/widgets/report_dialog.dart';
import '../models/discussion_answer.dart';
import '../models/discussion_topic.dart';
import '../providers/discussion_providers.dart';
import '../utils/discussion_date.dart';
import '../utils/discussion_poll.dart';
import 'discussion_form_screen.dart';
import 'widgets/discussion_answer_composer.dart';
import 'widgets/discussion_answer_item.dart';
import 'widgets/discussion_common.dart';
import 'widgets/discussion_deadline_dialog.dart';
import 'widgets/discussion_poll.dart';

/// 토론 주제 상세(`/discussions/{topicId}` 대응).
///
/// 선택지 토론이면 결과 바 아래에서 바로 답변을 작성하고, 자유 토론이면 답변
/// 목록 위의 "내 답변 작성" 카드에서 작성한다. 닫힌 토론에서는 두 경우 모두
/// 작성 UI가 노출되지 않는다.
class DiscussionDetailScreen extends ConsumerStatefulWidget {
  const DiscussionDetailScreen({super.key, required this.topicId});

  final int topicId;

  @override
  ConsumerState<DiscussionDetailScreen> createState() =>
      _DiscussionDetailScreenState();
}

class _DiscussionDetailScreenState
    extends ConsumerState<DiscussionDetailScreen> {
  final _answerController = TextEditingController();

  /// 선택지 토론에서 지금 고른 선택지. 아무것도 고르지 않았으면 null이고,
  /// "기타"를 고르면 [_isOtherSelected]가 true가 된다.
  int? _selectedOptionId;
  bool _isOtherSelected = false;

  /// 자유 토론의 답변 작성 폼이 펼쳐졌는지 여부.
  bool _isFreeComposerOpen = false;
  bool _isSubmittingAnswer = false;

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  bool get _hasSelection => _selectedOptionId != null || _isOtherSelected;

  DiscussionDetailController get _detailController =>
      ref.read(discussionDetailControllerProvider(widget.topicId).notifier);

  DiscussionAnswersController get _answersController =>
      ref.read(discussionAnswersControllerProvider(widget.topicId).notifier);

  void _selectOption(int? optionId) {
    setState(() {
      if (optionId == null) {
        _isOtherSelected = !_isOtherSelected;
        _selectedOptionId = null;
      } else {
        _isOtherSelected = false;
        _selectedOptionId = _selectedOptionId == optionId ? null : optionId;
      }
      if (!_hasSelection) _answerController.clear();
    });
  }

  void _closeComposer() {
    setState(() {
      _selectedOptionId = null;
      _isOtherSelected = false;
      _isFreeComposerOpen = false;
      _answerController.clear();
    });
  }

  Future<void> _submitAnswer({required bool withOption}) async {
    final content = _answerController.text.trim();
    if (content.isEmpty || _isSubmittingAnswer) return;

    setState(() => _isSubmittingAnswer = true);
    try {
      final refreshed = await _answersController.submit(
        content: content,
        withOption: withOption,
        optionId: _selectedOptionId,
      );
      await _detailController.reload();
      if (!mounted) return;
      // 등록은 성공했으므로 목록 갱신 실패와 무관하게 작성 폼을 닫는다
      // (폼을 남겨 두면 같은 답변을 다시 등록할 수 있다).
      _closeComposer();
      if (!refreshed) {
        AppSnackBar.info(context, '답변을 등록했어요. 목록은 잠시 후 새로고침해주세요.');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      AppSnackBar.error(context, e.message);
      // 닫힌 토론(409)이면 최신 닫힘 상태를 화면에 반영한다.
      if (e.statusCode == 409) await _detailController.reload();
    } finally {
      if (mounted) setState(() => _isSubmittingAnswer = false);
    }
  }

  Future<bool> _updateAnswer(int answerId, String content) async {
    try {
      await _answersController.updateAnswer(
        answerId: answerId,
        content: content,
      );
      await _detailController.reload();
      return true;
    } on ApiException catch (e) {
      if (mounted) AppSnackBar.error(context, e.message);
      if (e.statusCode == 409) await _detailController.reload();
      return false;
    }
  }

  Future<void> _deleteAnswer(int answerId) async {
    final confirmed = await AppConfirm.show(
      context,
      title: '답변을 삭제할까요?',
      message: '삭제한 답변은 복구할 수 없습니다.',
      confirmText: '삭제',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await _answersController.deleteAnswer(answerId);
      await _detailController.reload();
    } on ApiException catch (e) {
      if (mounted) AppSnackBar.error(context, e.message);
    }
  }

  Future<void> _reportAnswer(int answerId) async {
    final submission = await showReportDialog(context);
    if (submission == null) return;
    try {
      await _answersController.report(
        answerId,
        reason: submission.reason.apiValue,
        content: submission.content,
      );
      if (mounted) AppSnackBar.success(context, '신고가 접수되었습니다.');
    } on ApiException catch (e) {
      if (mounted) AppSnackBar.error(context, e.message);
    }
  }

  Future<void> _toggleAnswerLike(DiscussionAnswer answer) async {
    try {
      await _answersController.toggleLike(answer);
    } on ApiException catch (e) {
      if (mounted) AppSnackBar.error(context, e.message);
    }
  }

  Future<void> _toggleTopicLike() async {
    try {
      await _detailController.toggleLike();
    } on ApiException catch (e) {
      if (mounted) AppSnackBar.error(context, e.message);
    }
  }

  Future<void> _reportTopic() async {
    final submission = await showReportDialog(context);
    if (submission == null) return;
    try {
      await _detailController.report(
        reason: submission.reason.apiValue,
        content: submission.content,
      );
      if (mounted) AppSnackBar.success(context, '신고가 접수되었습니다.');
    } on ApiException catch (e) {
      if (mounted) AppSnackBar.error(context, e.message);
    }
  }

  Future<void> _editTopic(DiscussionTopicDetail topic) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DiscussionFormScreen.edit(topic: topic),
      ),
    );
    if (!mounted || updated != true) return;
    ref.invalidate(discussionDetailControllerProvider(widget.topicId));
  }

  Future<void> _editDeadline(DiscussionTopicDetail topic) {
    return showDiscussionDeadlineDialog(
      context,
      initialClosesAt: topic.closesAt,
      onSave: (closesAt) async {
        try {
          await _detailController.updateClosesAt(closesAt);
          return true;
        } on ApiException {
          return false;
        }
      },
    );
  }

  Future<void> _closeTopic() async {
    final confirmed = await AppConfirm.show(
      context,
      title: '토론을 닫을까요?',
      message: '토론을 닫으면 더 이상 답변을 달거나 내용을 수정할 수 없습니다.',
      confirmText: '닫기',
    );
    if (!confirmed || !mounted) return;

    AppLoading.show(context);
    try {
      await _detailController.close();
    } on ApiException catch (e) {
      if (mounted) AppSnackBar.error(context, e.message);
    } finally {
      AppLoading.hide();
    }
  }

  Future<void> _reopenTopic() async {
    AppLoading.show(context);
    try {
      await _detailController.reopen();
    } on ApiException catch (e) {
      if (mounted) AppSnackBar.error(context, e.message);
    } finally {
      AppLoading.hide();
    }
  }

  Future<void> _deleteTopic() async {
    final confirmed = await AppConfirm.show(
      context,
      title: '토론을 삭제할까요?',
      message: '삭제한 토론과 답변은 복구할 수 없습니다.',
      confirmText: '삭제',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    AppLoading.show(context);
    try {
      await _detailController.delete();
      if (!mounted) return;
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) AppSnackBar.error(context, e.message);
    } finally {
      AppLoading.hide();
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailState = ref.watch(
      discussionDetailControllerProvider(widget.topicId),
    );
    final bookTitle = switch (detailState) {
      AsyncData(:final value) => value.book.title,
      _ => null,
    };

    return Scaffold(
      appBar: AppBar(
        title: bookTitle == null
            ? const AppBarTitle('토론')
            : AppBarTitle(bookTitle, subtitle: '주제 토론'),
        backgroundColor: AppColors.pageBackground,
        foregroundColor: AppColors.textStrong,
        elevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: switch (detailState) {
          AsyncData(:final value) => _buildBody(value),
          AsyncError(:final error) => CommunityContentErrorState(
            message: error is ApiException ? error.message : '토론을 불러오지 못했습니다.',
            onRetry: () => ref.invalidate(
              discussionDetailControllerProvider(widget.topicId),
            ),
          ),
          _ => const CommunityContentLoadingState(),
        },
      ),
    );
  }

  Widget _buildBody(DiscussionTopicDetail topic) {
    final answersState = ref.watch(
      discussionAnswersControllerProvider(widget.topicId),
    );

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(discussionDetailControllerProvider(widget.topicId));
        ref.invalidate(discussionAnswersControllerProvider(widget.topicId));
        // 재조회가 끝날 때까지 새로고침 인디케이터를 유지한다. 실패는 각
        // provider의 AsyncError로 화면에 이미 드러나므로 여기서 삼킨다.
        try {
          await Future.wait([
            ref.read(discussionDetailControllerProvider(widget.topicId).future),
            ref.read(
              discussionAnswersControllerProvider(widget.topicId).future,
            ),
          ]);
        } catch (_) {}
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: CommunityContentWidth(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TopicCard(
                topic: topic,
                onEdit: () => _editTopic(topic),
                onEditDeadline: () => _editDeadline(topic),
                onClose: _closeTopic,
                onReopen: _reopenTopic,
                onDelete: _deleteTopic,
                onReport: _reportTopic,
                onToggleLike: _toggleTopicLike,
                pollSection: topic.hasOptions ? _buildPollSection(topic) : null,
              ),
              if (!topic.hasOptions) ...[
                const SizedBox(height: 12),
                _FreeAnswerCard(
                  isClosed: topic.isClosed,
                  isOpen: _isFreeComposerOpen,
                  controller: _answerController,
                  isSubmitting: _isSubmittingAnswer,
                  onOpen: () => setState(() => _isFreeComposerOpen = true),
                  onCancel: _closeComposer,
                  onSubmit: () => _submitAnswer(withOption: false),
                ),
              ],
              const SizedBox(height: 16),
              switch (answersState) {
                AsyncData(:final value) => _AnswerList(
                  state: value,
                  options: topic.options,
                  canEditAnswers: !topic.isClosed,
                  onLoadMore: () => _answersController.loadMore(),
                  onSubmitEdit: _updateAnswer,
                  onDelete: _deleteAnswer,
                  onReport: _reportAnswer,
                  onToggleLike: _toggleAnswerLike,
                ),
                AsyncError() => CommunityContentErrorState(
                  message: '답변을 불러오지 못했습니다.',
                  onRetry: () => ref.invalidate(
                    discussionAnswersControllerProvider(widget.topicId),
                  ),
                ),
                _ => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              },
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPollSection(DiscussionTopicDetail topic) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DiscussionPoll(
          detail: topic,
          interactive: !topic.isClosed,
          selectedOptionId: _selectedOptionId,
          isOtherSelected: _isOtherSelected,
          onSelect: _selectOption,
        ),
        if (!topic.isClosed && _hasSelection) ...[
          const SizedBox(height: 12),
          DiscussionAnswerComposer(
            controller: _answerController,
            hintText: '이 선택을 한 이유나 생각을 들려주세요...',
            isSubmitting: _isSubmittingAnswer,
            accentColor: discussionOptionColorOf(
              topic.options,
              _selectedOptionId,
            ),
            onCancel: _closeComposer,
            onSubmit: () => _submitAnswer(withOption: true),
          ),
        ],
      ],
    );
  }
}

/// 주제 본문 + (선택지 토론이면) 결과 바 + 공감 버튼을 담는 카드. 책 정보는
/// 앱바(책 이름 + "토론" 서브타이틀)로 옮겼다.
class _TopicCard extends StatelessWidget {
  const _TopicCard({
    required this.topic,
    required this.onEdit,
    required this.onEditDeadline,
    required this.onClose,
    required this.onReopen,
    required this.onDelete,
    required this.onReport,
    required this.onToggleLike,
    required this.pollSection,
  });

  final DiscussionTopicDetail topic;
  final VoidCallback onEdit;
  final VoidCallback onEditDeadline;
  final VoidCallback onClose;
  final VoidCallback onReopen;
  final VoidCallback onDelete;
  final VoidCallback onReport;
  final VoidCallback onToggleLike;
  final Widget? pollSection;

  @override
  Widget build(BuildContext context) {
    return CommunityContentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CommunityContentHeader(
            title: topic.title ?? '',
            nickname: topic.user.nickname,
            profileImageUrl: topic.user.profileImageUrl,
            dateLabel: formatDiscussionDateTime(topic.createdAt),
            badges: [
              if (topic.isClosed) const DiscussionBadge.closed(),
              if (topic.isSpoiler) const DiscussionBadge.spoiler(),
            ],
            trailing: topic.isMine
                ? _TopicMenu(
                    topic: topic,
                    onEdit: onEdit,
                    onEditDeadline: onEditDeadline,
                    onClose: onClose,
                    onReopen: onReopen,
                    onDelete: onDelete,
                  )
                : IconButton(
                    padding: EdgeInsets.zero,
                    tooltip: '토론 신고',
                    icon: const Icon(
                      PhosphorIconsRegular.flag,
                      size: 16,
                      color: AppColors.textMuted,
                    ),
                    onPressed: onReport,
                  ),
            metadata: topic.closesAt == null
                ? null
                : Row(
                    children: [
                      const Icon(
                        PhosphorIconsRegular.calendarBlank,
                        size: 13,
                        color: AppColors.controlInactive,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${formatDiscussionDate(topic.closesAt!)} 마감',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 16),
          Text(
            topic.content ?? '',
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textBody,
              height: 1.6,
            ),
          ),
          if (pollSection != null) ...[
            const SizedBox(height: 18),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 12),
            pollSection!,
          ],
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: CommunityLikeButton(
              isLiked: topic.likedByMe,
              likeCount: topic.likeCount,
              onTap: onToggleLike,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopicMenu extends StatelessWidget {
  const _TopicMenu({
    required this.topic,
    required this.onEdit,
    required this.onEditDeadline,
    required this.onClose,
    required this.onReopen,
    required this.onDelete,
  });

  final DiscussionTopicDetail topic;
  final VoidCallback onEdit;
  final VoidCallback onEditDeadline;
  final VoidCallback onClose;
  final VoidCallback onReopen;
  final VoidCallback onDelete;

  Future<void> _openSheet(BuildContext context) async {
    final action = await showModalBottomSheet<_TopicMenuAction>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => RecordDialogShell(
        title: '토론 관리',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!topic.isClosed)
              CommunityMenuTile(
                icon: PhosphorIconsRegular.pencilSimple,
                label: '수정',
                onTap: () => Navigator.pop(sheetContext, _TopicMenuAction.edit),
              ),
            CommunityMenuTile(
              icon: PhosphorIconsRegular.calendarBlank,
              label: '마감일 설정/수정',
              onTap: () =>
                  Navigator.pop(sheetContext, _TopicMenuAction.deadline),
            ),
            if (!topic.isClosed)
              CommunityMenuTile(
                icon: PhosphorIconsRegular.lock,
                label: '토론 닫기',
                onTap: () =>
                    Navigator.pop(sheetContext, _TopicMenuAction.close),
              ),
            if (topic.canReopen)
              CommunityMenuTile(
                icon: PhosphorIconsRegular.lockOpen,
                label: '다시 열기',
                onTap: () =>
                    Navigator.pop(sheetContext, _TopicMenuAction.reopen),
              ),
            CommunityMenuTile(
              icon: PhosphorIconsRegular.trash,
              label: '삭제',
              color: AppColors.error,
              onTap: () => Navigator.pop(sheetContext, _TopicMenuAction.delete),
            ),
          ],
        ),
      ),
    );
    if (action == null) return;
    switch (action) {
      case _TopicMenuAction.edit:
        onEdit();
      case _TopicMenuAction.deadline:
        onEditDeadline();
      case _TopicMenuAction.close:
        onClose();
      case _TopicMenuAction.reopen:
        onReopen();
      case _TopicMenuAction.delete:
        onDelete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return CommunityMoreButton(
      tooltip: '토론 메뉴',
      onTap: () => _openSheet(context),
    );
  }
}

/// 자유 토론 전용 "내 답변 작성" 카드.
class _FreeAnswerCard extends StatelessWidget {
  const _FreeAnswerCard({
    required this.isClosed,
    required this.isOpen,
    required this.controller,
    required this.isSubmitting,
    required this.onOpen,
    required this.onCancel,
    required this.onSubmit,
  });

  final bool isClosed;
  final bool isOpen;
  final TextEditingController controller;
  final bool isSubmitting;
  final VoidCallback onOpen;
  final VoidCallback onCancel;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return CommunityContentCard(
      child: isClosed
          ? const Text(
              '닫힌 토론에는 답변을 작성할 수 없습니다',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const DiscussionSectionLabel('내 답변 작성'),
                const SizedBox(height: 12),
                if (isOpen)
                  DiscussionAnswerComposer(
                    controller: controller,
                    hintText: '답변을 작성해보세요...',
                    isSubmitting: isSubmitting,
                    onCancel: onCancel,
                    onSubmit: onSubmit,
                  )
                else
                  InkWell(
                    onTap: onOpen,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceSubtle,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        '답변을 작성해보세요...',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _AnswerList extends StatelessWidget {
  const _AnswerList({
    required this.state,
    required this.options,
    required this.canEditAnswers,
    required this.onLoadMore,
    required this.onSubmitEdit,
    required this.onDelete,
    required this.onReport,
    required this.onToggleLike,
  });

  final DiscussionListState<DiscussionAnswer> state;
  final List<DiscussionOption> options;
  final bool canEditAnswers;
  final VoidCallback onLoadMore;
  final Future<bool> Function(int answerId, String content) onSubmitEdit;
  final void Function(int answerId) onDelete;
  final void Function(int answerId) onReport;
  final void Function(DiscussionAnswer answer) onToggleLike;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DiscussionSectionLabel('답변 ${state.items.length}개'),
        const SizedBox(height: 12),
        if (state.items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                '아직 답변이 없습니다.',
                style: TextStyle(color: AppColors.textMuted),
              ),
            ),
          )
        else
          for (final answer in state.items) ...[
            DiscussionAnswerItem(
              key: ValueKey(answer.id),
              answer: answer,
              options: options,
              canEdit: canEditAnswers,
              onSubmitEdit: (content) => onSubmitEdit(answer.id, content),
              onDelete: () => onDelete(answer.id),
              onReport: () => onReport(answer.id),
              onToggleLike: () => onToggleLike(answer),
            ),
            const SizedBox(height: 10),
          ],
        if (state.hasNext)
          Center(
            child: TextButton(
              onPressed: state.isLoadingMore ? null : onLoadMore,
              child: Text(state.isLoadingMore ? '불러오는 중...' : '더 보기'),
            ),
          ),
      ],
    );
  }
}

enum _TopicMenuAction { edit, deadline, close, reopen, delete }
