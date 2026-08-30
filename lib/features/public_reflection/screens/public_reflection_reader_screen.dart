import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_bar_title.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/community_content.dart';
import '../../book_reflection/screens/book_reflection_editor_screen.dart';
import '../../book_reflection/screens/widgets/reflection_image_embed_builder.dart';
import '../../book_reflection/screens/widgets/reflection_title_body_divider.dart';
import '../../book_reflection/services/book_reflection_content_adapter.dart';
import '../../discussion/utils/discussion_date.dart';
import '../models/public_reflection.dart';
import '../providers/public_reflection_providers.dart';

const _readerBodyTextStyle = TextStyle(
  color: AppColors.textBody,
  fontSize: 16,
  height: 1.65,
);

/// 긴 글을 위한 행간을 적용하되 Quill의 헤더·인용·목록·인라인 색상 속성은
/// 기존 독후감 리더와 같은 렌더러로 유지한다.
const _readerQuillStyles = DefaultStyles(
  placeHolder: DefaultTextBlockStyle(
    TextStyle(color: AppColors.textMuted, fontSize: 16, height: 1.65),
    HorizontalSpacing.zero,
    VerticalSpacing.zero,
    VerticalSpacing.zero,
    null,
  ),
  paragraph: DefaultTextBlockStyle(
    _readerBodyTextStyle,
    HorizontalSpacing.zero,
    VerticalSpacing(3, 5),
    VerticalSpacing.zero,
    null,
  ),
  lists: DefaultListBlockStyle(
    _readerBodyTextStyle,
    HorizontalSpacing.zero,
    VerticalSpacing(7, 2),
    VerticalSpacing(2, 7),
    null,
    null,
  ),
  quote: DefaultTextBlockStyle(
    TextStyle(
      color: AppColors.reflectionQuoteText,
      fontSize: 16,
      fontStyle: FontStyle.italic,
      height: 1.65,
    ),
    HorizontalSpacing(14, 8),
    VerticalSpacing(14, 14),
    VerticalSpacing(1, 1),
    null,
  ),
);

/// 공개 독후감의 읽기 전용 Quill 리더.
class PublicReflectionReaderScreen extends ConsumerStatefulWidget {
  const PublicReflectionReaderScreen({
    super.key,
    required this.isbn13,
    required this.bookTitle,
    required this.reflectionId,
  });

  final String isbn13;
  final String bookTitle;
  final int reflectionId;

  @override
  ConsumerState<PublicReflectionReaderScreen> createState() =>
      _PublicReflectionReaderScreenState();
}

class _PublicReflectionReaderScreenState
    extends ConsumerState<PublicReflectionReaderScreen> {
  bool _isLikeUpdating = false;

  Future<void> _toggleLike(PublicReflectionDetailArgs args) async {
    if (_isLikeUpdating) return;
    setState(() => _isLikeUpdating = true);
    try {
      await ref
          .read(publicReflectionDetailProvider(args).notifier)
          .toggleLike();
    } on ApiException catch (error) {
      if (mounted) AppSnackBar.error(context, error.message);
    } finally {
      if (mounted) setState(() => _isLikeUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final args = (isbn13: widget.isbn13, reflectionId: widget.reflectionId);
    final state = ref.watch(publicReflectionDetailProvider(args));

    return Scaffold(
      appBar: AppBar(
        title: AppBarTitle(widget.bookTitle, subtitle: '공개 독후감'),
        backgroundColor: AppColors.pageBackground,
        foregroundColor: AppColors.textStrong,
        elevation: 0,
      ),
      body: switch (state) {
        AsyncData(:final value) => _ReaderBody(
          detail: value,
          onLike: _isLikeUpdating ? null : () => _toggleLike(args),
        ),
        AsyncError(:final error) => CommunityContentErrorState(
          message: error is ApiException ? error.message : '독후감을 불러오지 못했습니다.',
          onRetry: () => ref.invalidate(publicReflectionDetailProvider(args)),
        ),
        _ => const CommunityContentLoadingState(),
      },
    );
  }
}

class _ReaderBody extends StatelessWidget {
  const _ReaderBody({required this.detail, required this.onLike});

  final PublicReflectionDetail detail;
  final VoidCallback? onLike;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: CommunityContentWidth(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: CommunityContentCard(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CommunityContentHeader(
                  title: detail.title.trim().isEmpty ? '제목 없음' : detail.title,
                  nickname: detail.user.nickname,
                  profileImageUrl: detail.user.profileImageUrl,
                  dateLabel: formatRelativeDiscussionDateTime(detail.createdAt),
                ),
                const ReflectionTitleBodyDivider(horizontalInset: 0),
                _PublicReflectionRichContent(
                  key: ValueKey('${detail.id}-${detail.updatedAt}'),
                  contentJson: detail.contentJson,
                ),
                const SizedBox(height: 16),
                const Divider(height: 1, color: AppColors.border),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: CommunityLikeButton(
                    isLiked: detail.likedByMe,
                    likeCount: detail.likeCount,
                    onTap: onLike,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PublicReflectionRichContent extends StatefulWidget {
  const _PublicReflectionRichContent({super.key, required this.contentJson});

  final Map<String, dynamic> contentJson;

  @override
  State<_PublicReflectionRichContent> createState() =>
      _PublicReflectionRichContentState();
}

class _PublicReflectionRichContentState
    extends State<_PublicReflectionRichContent> {
  static const _adapter = BookReflectionContentAdapter();
  late final QuillController _controller;
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller = QuillController(
      document: _adapter.fromServerJson(widget.contentJson),
      selection: const TextSelection.collapsed(offset: 0),
      readOnly: true,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ReflectionQuillEditor(
      controller: _controller,
      focusNode: _focusNode,
      scrollController: _scrollController,
      config: const QuillEditorConfig(
        scrollable: false,
        padding: EdgeInsets.zero,
        enableInteractiveSelection: true,
        showCursor: false,
        customStyles: _readerQuillStyles,
        textSpanBuilder: reflectionTextSpanBuilder,
        embedBuilders: [ReflectionImageEmbedBuilder()],
      ),
    );
  }
}
