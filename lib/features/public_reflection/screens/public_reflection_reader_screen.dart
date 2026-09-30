import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_banner_ad.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/community_content.dart';
import '../../auth/providers/auth_access_providers.dart';
import '../../book_reflection/screens/book_reflection_editor_screen.dart';
import '../../book_reflection/screens/widgets/reflection_image_embed_builder.dart';
import '../../book_reflection/screens/widgets/reflection_title_body_divider.dart';
import '../../book_reflection/services/book_reflection_content_adapter.dart';
import '../../discussion/utils/discussion_date.dart';
import '../../public_bookshelf/widgets/author_profile_sheet.dart';
import '../models/public_reflection.dart';
import '../providers/public_reflection_providers.dart';

/// 긴 글을 위한 행간을 적용하되 Quill의 헤더·인용·목록·인라인 색상 속성은
/// 기존 독후감 리더와 같은 렌더러로 유지한다.
///
/// `fontFamily`는 `bookReflectionQuillStyles`(book_reflection_editor_screen.dart)
/// 와 같은 이유로 `bodyMedium`에서 직접 가져와 명시한다 — Quill의 `TextSpan`은
/// 주변 `DefaultTextStyle`과 병합되지 않아, 지정하지 않으면 플랫폼 기본 폰트로
/// 그려져(iOS는 제목/본문 폰트가 다르다) 토론 등 일반 `Text` 위젯과 같은
/// `height` 값을 줘도 실제 줄 간격이 달라 보인다.
DefaultStyles _readerQuillStyles(BuildContext context) {
  final brightness = Theme.of(context).brightness;
  final colors = brightness == Brightness.dark
      ? AppPalette.dark
      : AppPalette.light;
  final bodyFontFamily = Theme.of(context).textTheme.bodyMedium?.fontFamily;
  return _buildReaderQuillStyles(colors, bodyFontFamily);
}

DefaultStyles _buildReaderQuillStyles(
  AppPalette colors,
  String? bodyFontFamily,
) {
  final bodyTextStyle = TextStyle(
    color: colors.textBody,
    fontSize: 15,
    height: 1.6,
    fontFamily: bodyFontFamily,
  );
  return DefaultStyles(
    h1: DefaultTextBlockStyle(
      TextStyle(
        color: colors.textStrong,
        fontSize: 21,
        height: 1.3,
        fontWeight: FontWeight.bold,
      ),
      HorizontalSpacing.zero,
      VerticalSpacing(24, 12),
      VerticalSpacing.zero,
      null,
    ),
    h2: DefaultTextBlockStyle(
      TextStyle(
        color: colors.textStrong,
        fontSize: 18,
        height: 1.3,
        fontWeight: FontWeight.bold,
      ),
      HorizontalSpacing.zero,
      VerticalSpacing(20, 10),
      VerticalSpacing.zero,
      null,
    ),
    placeHolder: DefaultTextBlockStyle(
      TextStyle(
        color: colors.textMuted,
        fontSize: 15,
        height: 1.6,
        fontFamily: bodyFontFamily,
      ),
      HorizontalSpacing.zero,
      VerticalSpacing.zero,
      VerticalSpacing.zero,
      null,
    ),
    paragraph: DefaultTextBlockStyle(
      bodyTextStyle,
      HorizontalSpacing.zero,
      VerticalSpacing(0, 10),
      VerticalSpacing.zero,
      null,
    ),
    lists: DefaultListBlockStyle(
      bodyTextStyle,
      HorizontalSpacing.zero,
      VerticalSpacing(7, 2),
      VerticalSpacing(2, 7),
      null,
      null,
    ),
    quote: DefaultTextBlockStyle(
      TextStyle(
        color: colors.reflectionQuoteText,
        fontSize: 15,
        fontStyle: FontStyle.italic,
        height: 1.6,
        fontFamily: bodyFontFamily,
      ),
      HorizontalSpacing(14, 8),
      VerticalSpacing(14, 14),
      VerticalSpacing(1, 1),
      null,
    ),
  );
}

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
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            toolbarHeight: 48,
            pinned: false,
            backgroundColor: AppColors.of(context).pageBackground,
            foregroundColor: AppColors.of(context).textStrong,
            surfaceTintColor: Colors.transparent,
          ),
          switch (state) {
            // 공개 독후감 조회는 인증이 필요 없지만 공감은 계정이 있어야 한다.
            AsyncData(:final value) => SliverToBoxAdapter(
              child: _ReaderBody(
                bookTitle: widget.bookTitle,
                detail: value,
                onLike: _isLikeUpdating ? null : () => _toggleLike(args),
                allowLike: ref.watch(canUseAccountFeaturesProvider),
              ),
            ),
            AsyncError(:final error) => SliverFillRemaining(
              child: CommunityContentErrorState(
                message: error is ApiException
                    ? error.message
                    : '독후감을 불러오지 못했습니다.',
                onRetry: () =>
                    ref.invalidate(publicReflectionDetailProvider(args)),
              ),
            ),
            _ => const SliverFillRemaining(
              child: CommunityContentLoadingState(),
            ),
          },
        ],
      ),
    );
  }
}

class _ReaderBody extends StatelessWidget {
  const _ReaderBody({
    required this.bookTitle,
    required this.detail,
    required this.onLike,
    required this.allowLike,
  });

  final String bookTitle;
  final PublicReflectionDetail detail;
  final VoidCallback? onLike;
  final bool allowLike;

  @override
  Widget build(BuildContext context) {
    return CommunityContentWidth(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            bookTitle,
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
            title: detail.title.trim().isEmpty ? '제목 없음' : detail.title,
            nickname: detail.user.nickname,
            profileImageUrl: detail.user.profileImageUrl,
            dateLabel: formatRelativeDiscussionDateTime(detail.createdAt),
            onAuthorTap: authorProfileSheetHandler(
              context,
              userId: detail.user.id,
              nickname: detail.user.nickname,
              isFinishedBooksPublic: detail.user.isFinishedBooksPublic,
            ),
          ),
          const ReflectionTitleBodyDivider(horizontalInset: 0),
          _PublicReflectionRichContent(
            key: ValueKey('${detail.id}-${detail.updatedAt}'),
            contentJson: detail.contentJson,
          ),
          const AppBannerAd(topSpacing: 24),
          const SizedBox(height: 40),
          Divider(height: 1, color: AppColors.of(context).border),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: allowLike
                ? CommunityLikeButton(
                    isLiked: detail.likedByMe,
                    likeCount: detail.likeCount,
                    onTap: onLike,
                  )
                : CommunityLikeCount(likeCount: detail.likeCount),
          ),
        ],
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
      config: QuillEditorConfig(
        scrollable: false,
        padding: EdgeInsets.zero,
        enableInteractiveSelection: true,
        showCursor: false,
        customStyles: _readerQuillStyles(context),
        textSpanBuilder: reflectionTextSpanBuilder,
        embedBuilders: [ReflectionImageEmbedBuilder()],
      ),
    );
  }
}
