import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_banner_ad.dart';
import '../../../shared/widgets/app_confirm.dart';
import '../../../shared/widgets/app_loading.dart';
import '../../../shared/widgets/app_pagination.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/community_content.dart';
import '../../../shared/widgets/record_dialog_shell.dart';
import '../../auth/providers/auth_access_providers.dart';
import '../../book_detail/screens/widgets/report_dialog.dart';
import '../../public_bookshelf/widgets/author_profile_sheet.dart';
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
/// 답변은 항상 바텀시트로 작성한다. 선택지 토론이면 결과 바에서 선택지를
/// 누르는 즉시 그 선택지를 보여주는 시트가 뜨고, 자유 토론이면 "내 답변
/// 작성" 카드를 눌러 시트를 연다. 닫힌 토론에서는 두 경우 모두 작성 UI가
/// 노출되지 않는다.
class DiscussionDetailScreen extends ConsumerStatefulWidget {
  const DiscussionDetailScreen({
    super.key,
    required this.topicId,
    this.highlightAnswerId,
  });

  final int topicId;

  /// 지정하면 해당 답변으로 스크롤하고 외곽선으로 강조한다("내가 작성한
  /// 토론 댓글" 목록에서 진입할 때 사용).
  final int? highlightAnswerId;

  @override
  ConsumerState<DiscussionDetailScreen> createState() =>
      _DiscussionDetailScreenState();
}

class _DiscussionDetailScreenState
    extends ConsumerState<DiscussionDetailScreen> {
  final _scrollController = ScrollController();
  final _pendingAnswerLikeIds = <int>{};
  final _highlightedAnswerKey = GlobalKey();
  final _answerSectionKey = GlobalKey();
  bool _isTogglingTopicLike = false;
  bool _isSearchingForHighlight = false;
  // 스캔이 찾았든 포기했든 한 번 끝나면 다시 시작하지 않는다. `_buildBody`가
  // 리빌드마다 스캔을 재호출하는데, 이 표시가 없으면 중단된 스캔이 이후
  // 리빌드(공감 토글 등)마다 되살아나 페이지를 계속 앞으로 넘겨버린다.
  bool _highlightSearchDone = false;

  void _scrollToHighlightedAnswer() {
    final context = _highlightedAnswerKey.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      alignment: 0.2,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  /// 답변 목록에서 다른 페이지로 이동하면 그 목록 상단이 보이게 스크롤한다.
  void _scrollToAnswerSectionTop() {
    final context = _answerSectionKey.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 강조 대상 답변이 현재 페이지에 없으면 있을 때까지(또는 더 이상 페이지가
  /// 없을 때까지) 다음 페이지를 순차 조회한 뒤 스크롤한다.
  Future<void> _ensureHighlightVisible() async {
    final highlightAnswerId = widget.highlightAnswerId;
    if (highlightAnswerId == null ||
        _highlightSearchDone ||
        _isSearchingForHighlight) {
      return;
    }
    _isSearchingForHighlight = true;
    try {
      while (mounted) {
        final state = ref
            .read(discussionAnswersControllerProvider(widget.topicId))
            .valueOrNull;
        if (state == null) return;
        if (state.items.any((answer) => answer.id == highlightAnswerId)) {
          _highlightSearchDone = true;
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _scrollToHighlightedAnswer(),
          );
          return;
        }
        if (state.page >= state.totalPages || state.isChangingPage) return;
        final pageBeforeLoad = state.page;
        try {
          await _answersController.goToPage(pageBeforeLoad + 1);
        } catch (_) {
          return;
        }
        final latest = ref
            .read(discussionAnswersControllerProvider(widget.topicId))
            .valueOrNull;
        // 페이지가 실제로 넘어가지 않았다면(동시 요청 등) 더 진행하지 않는다.
        if (latest == null || latest.page == pageBeforeLoad) return;
      }
    } finally {
      _isSearchingForHighlight = false;
      _highlightSearchDone = true;
    }
  }

  DiscussionDetailController get _detailController =>
      ref.read(discussionDetailControllerProvider(widget.topicId).notifier);

  DiscussionAnswersController get _answersController =>
      ref.read(discussionAnswersControllerProvider(widget.topicId).notifier);

  void _openPollAnswerSheet(DiscussionTopicDetail topic, int? optionId) {
    final label = optionId == null
        ? '기타'
        : topic.options.firstWhere((o) => o.id == optionId).content;
    final color = discussionOptionColorOf(topic.options, optionId);
    showDiscussionAnswerSheet(
      context,
      hintText: '내용을 입력하세요',
      selectedOptionLabel: label,
      accentColor: color,
      onSubmit: (content) =>
          _submitAnswer(content: content, withOption: true, optionId: optionId),
    );
  }

  void _openFreeAnswerSheet() {
    showDiscussionAnswerSheet(
      context,
      hintText: '내용을 입력하세요',
      onSubmit: (content) => _submitAnswer(content: content, withOption: false),
    );
  }

  Future<bool> _submitAnswer({
    required String content,
    required bool withOption,
    int? optionId,
  }) async {
    try {
      final refreshed = await _answersController.submit(
        content: content,
        withOption: withOption,
        optionId: optionId,
      );
      await _detailController.reload();
      if (!refreshed && mounted) {
        AppSnackBar.info(context, '답변을 등록했어요. 목록은 잠시 후 새로고침해주세요.');
      }
      return true;
    } on ApiException catch (e) {
      if (mounted) {
        AppSnackBar.error(context, e.message);
        // 닫힌 토론(409)이면 최신 닫힘 상태를 화면에 반영한다.
        if (e.statusCode == 409) await _detailController.reload();
      }
      return false;
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

  Future<void> _goToAnswerPage(int page) async {
    try {
      await _answersController.goToPage(page);
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _scrollToAnswerSectionTop(),
        );
      }
    } catch (_) {
      if (mounted) AppSnackBar.error(context, '답변을 불러오지 못했습니다');
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
    if (_pendingAnswerLikeIds.contains(answer.id)) return;
    setState(() => _pendingAnswerLikeIds.add(answer.id));
    try {
      await _answersController.toggleLike(answer);
    } on ApiException catch (e) {
      if (mounted) AppSnackBar.error(context, e.message);
    } finally {
      if (mounted) setState(() => _pendingAnswerLikeIds.remove(answer.id));
    }
  }

  Future<void> _toggleTopicLike() async {
    if (_isTogglingTopicLike) return;
    setState(() => _isTogglingTopicLike = true);
    try {
      await _detailController.toggleLike();
    } on ApiException catch (e) {
      if (mounted) AppSnackBar.error(context, e.message);
    } finally {
      if (mounted) setState(() => _isTogglingTopicLike = false);
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
    if (!ref.read(canPublishCommunityContentProvider)) {
      AppSnackBar.error(context, '징계 기간에는 마감일을 수정할 수 없습니다.');
      return Future<void>.value();
    }
    return showDiscussionDeadlineDialog(
      context,
      initialClosesAt: topic.closesAt,
      onSave: (closesAt) async {
        if (!ref.read(canPublishCommunityContentProvider)) {
          return '징계 기간에는 마감일을 수정할 수 없습니다.';
        }
        try {
          await _detailController.updateClosesAt(closesAt);
          return null;
        } on ApiException catch (error) {
          return error.message;
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

    return Scaffold(
      body: switch (detailState) {
        AsyncData(:final value) => _buildBody(value),
        AsyncError(:final error) => CustomScrollView(
          slivers: [
            _buildAppBar(),
            SliverFillRemaining(
              child: CommunityContentErrorState(
                message: error is ApiException
                    ? error.message
                    : '토론을 불러오지 못했습니다.',
                onRetry: () => ref.invalidate(
                  discussionDetailControllerProvider(widget.topicId),
                ),
              ),
            ),
          ],
        ),
        _ => CustomScrollView(
          slivers: [
            _buildAppBar(),
            const SliverFillRemaining(child: CommunityContentLoadingState()),
          ],
        ),
      },
    );
  }

  SliverAppBar _buildAppBar() {
    return SliverAppBar(
      toolbarHeight: 48,
      pinned: false,
      backgroundColor: AppColors.of(context).pageBackground,
      foregroundColor: AppColors.of(context).textStrong,
      surfaceTintColor: Colors.transparent,
    );
  }

  Widget _buildBody(DiscussionTopicDetail topic) {
    final answersState = ref.watch(
      discussionAnswersControllerProvider(widget.topicId),
    );
    // 토론 조회는 인증이 필요 없지만 답변 작성·공감·신고·선택지 투표는
    // 계정이 있어야 한다. 계정이 없으면 그 진입점을 아예 만들지 않는다.
    final allowAccountActions = ref.watch(canUseAccountFeaturesProvider);
    final canPublish = ref.watch(canPublishCommunityContentProvider);

    if (widget.highlightAnswerId != null && answersState.valueOrNull != null) {
      // build 도중 바로 실행하면 `_ensureHighlightVisible`이 첫 await 전에
      // 동기적으로 `goToPage`(→ provider state 변경)까지 진행해 "위젯 트리를
      // 빌드하는 동안 provider를 수정할 수 없다"는 Riverpod 제약을 위반한다.
      // 프레임이 끝난 뒤로 미룬다.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_ensureHighlightVisible());
      });
    }

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
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          _buildAppBar(),
          SliverToBoxAdapter(
            child: CommunityContentWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TopicCard(
                    topic: topic,
                    canEdit: canPublish,
                    onEdit: () => _editTopic(topic),
                    onEditDeadline: () => _editDeadline(topic),
                    onClose: _closeTopic,
                    onReopen: _reopenTopic,
                    onDelete: _deleteTopic,
                    onReport: _reportTopic,
                    onToggleLike: _isTogglingTopicLike
                        ? null
                        : _toggleTopicLike,
                    pollSection: topic.hasOptions
                        ? _buildPollSection(
                            topic,
                            allowAccountActions: canPublish,
                          )
                        : null,
                    allowAccountActions: allowAccountActions,
                  ),
                  const AppBannerAd(topSpacing: 20),
                  if (!topic.hasOptions && canPublish) ...[
                    const SizedBox(height: 32),
                    _FreeAnswerCard(
                      isClosed: topic.isClosed,
                      onOpen: _openFreeAnswerSheet,
                    ),
                  ],
                  SizedBox(key: _answerSectionKey, height: 40),
                  switch (answersState) {
                    AsyncData(:final value) => _AnswerList(
                      state: value,
                      options: topic.options,
                      canEditAnswers: !topic.isClosed && canPublish,
                      pendingLikeIds: _pendingAnswerLikeIds,
                      onSubmitEdit: _updateAnswer,
                      onDelete: _deleteAnswer,
                      onReport: _reportAnswer,
                      onToggleLike: _toggleAnswerLike,
                      onPageChanged: _goToAnswerPage,
                      highlightAnswerId: widget.highlightAnswerId,
                      highlightKey: _highlightedAnswerKey,
                      allowAccountActions: allowAccountActions,
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
        ],
      ),
    );
  }

  Widget _buildPollSection(
    DiscussionTopicDetail topic, {
    required bool allowAccountActions,
  }) {
    return DiscussionPoll(
      detail: topic,
      interactive: !topic.isClosed && allowAccountActions,
      onSelect: (optionId) => _openPollAnswerSheet(topic, optionId),
    );
  }
}

/// 책 이름·주제 본문·선택지 결과·공감 버튼을 담는 토론 지면.
class _TopicCard extends StatelessWidget {
  const _TopicCard({
    required this.topic,
    required this.canEdit,
    required this.onEdit,
    required this.onEditDeadline,
    required this.onClose,
    required this.onReopen,
    required this.onDelete,
    required this.onReport,
    required this.onToggleLike,
    required this.pollSection,
    required this.allowAccountActions,
  });

  final DiscussionTopicDetail topic;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onEditDeadline;
  final VoidCallback onClose;
  final VoidCallback onReopen;
  final VoidCallback onDelete;
  final VoidCallback onReport;
  final VoidCallback? onToggleLike;
  final Widget? pollSection;

  /// 서버 계정이 필요한 액션(공감·신고·작성자 메뉴)을 노출할지.
  final bool allowAccountActions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          topic.book.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            fontWeight: FontWeight.w600,
            color: AppColors.of(context).accentForeground,
          ),
        ),
        const SizedBox(height: 12),
        CommunityContentHeader(
          title: topic.title ?? '',
          nickname: topic.user.nickname,
          profileImageUrl: topic.user.profileImageUrl,
          dateLabel: formatRelativeDiscussionDateTime(topic.createdAt),
          onAuthorTap: authorProfileSheetHandler(
            context,
            userId: topic.user.id,
            nickname: topic.user.nickname,
            isFinishedBooksPublic: topic.user.isFinishedBooksPublic,
          ),
          badges: [
            if (topic.isClosed) const DiscussionBadge.closed(),
            if (topic.isSpoiler) const DiscussionBadge.spoiler(),
          ],
          trailing: !allowAccountActions
              ? null
              : topic.isMine
              ? _TopicMenu(
                  topic: topic,
                  canEdit: canEdit,
                  onEdit: onEdit,
                  onEditDeadline: onEditDeadline,
                  onClose: onClose,
                  onReopen: onReopen,
                  onDelete: onDelete,
                )
              : IconButton(
                  padding: EdgeInsets.zero,
                  tooltip: '토론 신고',
                  icon: Icon(
                    PhosphorIconsRegular.flag,
                    size: 16,
                    color: AppColors.of(context).textMuted,
                  ),
                  onPressed: onReport,
                ),
          metadata: topic.closesAt == null
              ? null
              : Row(
                  children: [
                    Icon(
                      PhosphorIconsRegular.calendarBlank,
                      size: 13,
                      color: AppColors.of(context).controlInactive,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        '${formatDiscussionDate(topic.closesAt!)} 마감',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.of(context).textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        Divider(height: 1, color: AppColors.of(context).border),
        const SizedBox(height: 16),
        SelectableText(
          topic.content ?? '',
          style: TextStyle(
            fontSize: 15,
            color: AppColors.of(context).textBody,
            height: 1.6,
          ),
        ),
        if (pollSection != null) ...[
          const SizedBox(height: 32),
          Divider(height: 1, color: AppColors.of(context).border),
          const SizedBox(height: 24),
          pollSection!,
        ],
        const SizedBox(height: 32),
        Divider(height: 1, color: AppColors.of(context).border),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerLeft,
          child: allowAccountActions
              ? CommunityLikeButton(
                  isLiked: topic.likedByMe,
                  likeCount: topic.likeCount,
                  onTap: onToggleLike,
                )
              : CommunityLikeCount(likeCount: topic.likeCount),
        ),
      ],
    );
  }
}

class _TopicMenu extends StatelessWidget {
  const _TopicMenu({
    required this.topic,
    required this.canEdit,
    required this.onEdit,
    required this.onEditDeadline,
    required this.onClose,
    required this.onReopen,
    required this.onDelete,
  });

  final DiscussionTopicDetail topic;
  final bool canEdit;
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
            if (!topic.isClosed && canEdit)
              CommunityMenuTile(
                icon: PhosphorIconsRegular.pencilSimple,
                label: '수정',
                onTap: () => Navigator.pop(sheetContext, _TopicMenuAction.edit),
              ),
            if (canEdit)
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
              destructive: true,
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

/// 자유 토론 전용 "내 답변 작성" 카드. 누르면 답변 작성 바텀시트를 연다.
class _FreeAnswerCard extends StatelessWidget {
  const _FreeAnswerCard({required this.isClosed, required this.onOpen});

  final bool isClosed;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    if (isClosed) {
      return Text(
        '닫힌 토론에는 답변을 작성할 수 없습니다',
        style: TextStyle(fontSize: 13, color: AppColors.of(context).textMuted),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onOpen,
        icon: const Icon(PhosphorIconsRegular.pencilSimple, size: 18),
        label: const Text('나의 생각 남기기'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          foregroundColor: AppColors.of(context).accentForeground,
        ),
      ),
    );
  }
}

class _AnswerList extends StatelessWidget {
  const _AnswerList({
    required this.state,
    required this.options,
    required this.canEditAnswers,
    required this.pendingLikeIds,
    required this.onSubmitEdit,
    required this.onDelete,
    required this.onReport,
    required this.onToggleLike,
    required this.onPageChanged,
    this.highlightAnswerId,
    this.highlightKey,
    required this.allowAccountActions,
  });

  final DiscussionAnswerPageState state;
  final List<DiscussionOption> options;
  final bool canEditAnswers;
  final Set<int> pendingLikeIds;
  final Future<bool> Function(int answerId, String content) onSubmitEdit;
  final void Function(int answerId) onDelete;
  final void Function(int answerId) onReport;
  final void Function(DiscussionAnswer answer) onToggleLike;
  final ValueChanged<int> onPageChanged;

  /// "내가 작성한 토론 댓글" 목록에서 진입했을 때 스크롤·강조할 답변 ID.
  final int? highlightAnswerId;
  final GlobalKey? highlightKey;

  /// 서버 계정이 필요한 액션(공감·신고·본인 답변 관리)을 노출할지.
  final bool allowAccountActions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '함께 나눈 생각 ${state.totalElements}',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.of(context).textStrong,
          ),
        ),
        const SizedBox(height: 8),
        if (state.items.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                // 숨김 답변만 있는 페이지는 목록에서 빠져 비어 보인다. 다른
                // 페이지에 공개 답변이 있을 수 있어 "없다"고 단정하지 않는다.
                state.totalElements > 0
                    ? '이 페이지에 표시할 답변이 없습니다.'
                    : '아직 답변이 없습니다.',
                style: TextStyle(color: AppColors.of(context).textMuted),
              ),
            ),
          )
        else
          AnimatedOpacity(
            opacity: state.isChangingPage ? 0.5 : 1,
            duration: const Duration(milliseconds: 150),
            child: IgnorePointer(
              ignoring: state.isChangingPage,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (answerIndex, answer) in state.items.indexed) ...[
                    _MaybeHighlightedAnswer(
                      isHighlighted: answer.id == highlightAnswerId,
                      highlightKey: answer.id == highlightAnswerId
                          ? highlightKey
                          : null,
                      child: DiscussionAnswerItem(
                        key: ValueKey(answer.id),
                        answer: answer,
                        options: options,
                        canEdit: canEditAnswers,
                        onSubmitEdit: (content) =>
                            onSubmitEdit(answer.id, content),
                        onDelete: () => onDelete(answer.id),
                        onReport: () => onReport(answer.id),
                        onToggleLike: pendingLikeIds.contains(answer.id)
                            ? null
                            : () => onToggleLike(answer),
                        allowAccountActions: allowAccountActions,
                      ),
                    ),
                    if (answerIndex < state.items.length - 1)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: CommunityContentDivider(),
                      ),
                  ],
                ],
              ),
            ),
          ),
        if (state.totalPages > 1)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Center(
              child: AppPagination(
                currentPage: state.page,
                totalPages: state.totalPages,
                onPageChanged: onPageChanged,
                // 다른 3개 "내 콘텐츠" 페이지네이션(전체 폭)과 달리 이 화면은
                // 토론 본문 옆 좁은 폭에 놓이므로 양쪽 끝이 스크롤 없이 보이게
                // 좌우로 펼치는 개수를 줄인다.
                siblingCount: 1,
              ),
            ),
          ),
      ],
    );
  }
}

/// 강조 대상 답변에 스크롤 앵커([highlightKey])와 옅은 배경을 씌운다.
/// 펄스 없이 계속 유지되는 은은한 강조.
class _MaybeHighlightedAnswer extends StatelessWidget {
  const _MaybeHighlightedAnswer({
    required this.isHighlighted,
    required this.highlightKey,
    required this.child,
  });

  final bool isHighlighted;
  final GlobalKey? highlightKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isHighlighted) return child;

    final colors = AppColors.of(context);
    return TweenAnimationBuilder<double>(
      key: highlightKey,
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      builder: (context, value, _) => Opacity(
        opacity: value,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          decoration: BoxDecoration(
            color: colors.accentSurface.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: colors.accentForeground.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

enum _TopicMenuAction { edit, deadline, close, reopen, delete }
