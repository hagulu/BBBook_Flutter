import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/patch_field.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/author_display.dart';
import '../../../shared/widgets/app_bar_title.dart';
import '../../../shared/widgets/app_confirm.dart';
import '../../../shared/widgets/app_loading.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../book_note/screens/book_note_list.dart';
import '../../book_reflection/screens/book_reflection_list.dart';
import '../../bookshelf/models/book_item.dart';
import '../../bookshelf/models/book_status.dart';
import '../../bookshelf/models/record_patch.dart';
import '../../bookshelf/providers/bookshelf_providers.dart';
import '../../bookshelf/screens/widgets/book_cover.dart';
import '../models/record_labels.dart';
import '../providers/book_record_providers.dart';
import 'book_sharing_list.dart';
import 'widgets/book_info_edit_dialog.dart';
import 'widgets/finish_confirm_dialog.dart';
import 'widgets/meta_dialogs.dart';
import 'widgets/meta_summary_card.dart';
import 'widgets/progress_card.dart';
import 'widgets/rating_review_card.dart';
import 'widgets/reading_status_tile.dart';
import 'widgets/record_field_tile.dart';
import 'widgets/record_section_card.dart';
import 'widgets/reread_dialog.dart';
import 'widgets/tag_section.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// 책 기록 상세 화면(`/records/[userBookId]` 대응). 자체 AppBar만 갖고
/// 공통 하단 탭은 쓰지 않는다(book-record.md — 별도 `Navigator.push`로 진입).
/// 조회는 로컬 DB(bookRecordControllerProvider)만 사용한다. 기본 기록 필드
/// 수정(updateRecord)은 로컬 우선이라 로딩·에러 UI 없이 즉시 반영된 결과를
/// 보여주고, 서재 삭제는 서버 응답을 기다려 로딩·에러를 그대로 노출한다.
class BookRecordScreen extends ConsumerWidget {
  const BookRecordScreen({super.key, required this.userBookId});

  final int userBookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(bookRecordControllerProvider(userBookId));
    final book = state.valueOrNull;

    Widget body;
    if (state.hasValue) {
      body = AppLoadingOverlay(
        isLoading: state.isLoading,
        child: book == null
            ? const _NotFoundBody()
            : _BookRecordBody(userBookId: userBookId, book: book),
      );
    } else if (state.hasError) {
      body = _ErrorBody(
        onRetry: () => ref.invalidate(bookRecordControllerProvider(userBookId)),
      );
    } else {
      body = const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        title: AppBarTitle(book?.title ?? '책 기록'),
        backgroundColor: AppColors.pageBackground,
        foregroundColor: AppColors.textStrong,
        elevation: 0,
      ),
      body: body,
    );
  }
}

class _NotFoundBody extends StatelessWidget {
  const _NotFoundBody();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        '책을 찾을 수 없습니다.',
        style: TextStyle(color: AppColors.textMuted),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '불러오지 못했습니다.',
            style: TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    );
  }
}

class _BookRecordBody extends ConsumerWidget {
  const _BookRecordBody({required this.userBookId, required this.book});

  final int userBookId;
  final BookItem book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(
      bookRecordControllerProvider(userBookId).notifier,
    );
    final isWantToRead = book.status == BookStatus.wantToRead;

    return DefaultTabController(
      length: isWantToRead ? 2 : 4,
      // 읽을 책은 노트·독후감 대신 생각 나눔을 기본 탭으로 연다.
      initialIndex: isWantToRead ? 1 : 0,
      child: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          // 책 표지·제목 헤더는 스크롤과 함께 말려 올라가고(사용자 확인
          // 사항), 탭 바만 상단에 고정한다. 헤더는 여기 한 곳에만 있고 탭
          // 콘텐츠마다 따로 넣지 않는다 — NestedScrollView가 활성 탭의
          // 스크롤에 맞춰 이 헤더를 공유해서 접어준다.
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: _Header(
                book: book,
                onEditBookInfo: () => showBookInfoEditDialog(
                  context,
                  userBookId: userBookId,
                  book: book,
                ),
              ),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabBarHeaderDelegate(
              TabBar(
                tabs: [
                  const Tab(text: '정보'),
                  if (!isWantToRead) const Tab(text: '노트'),
                  if (!isWantToRead) const Tab(text: '독후감'),
                  const Tab(text: '생각나눔'),
                ],
                // 탭이 4개라 기본 labelPadding(좌우 16)으로는 좁은 화면에서
                // '생각나눔'이 잘린다.
                labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                labelColor: AppColors.textStrong,
                unselectedLabelColor: AppColors.textMuted,
                indicatorColor: AppColors.accentForeground,
                dividerColor: AppColors.border,
              ),
            ),
          ),
        ],
        body: TabBarView(
          children: [
            ListView(
              key: const PageStorageKey('book-record-info'),
              // 쪽수 등 입력 중에 스크롤을 시작하면 포커스(커서)도 함께 풀어
              // 편집 상태가 화면 밖으로 밀려도 그대로 남지 않게 한다.
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
              children: [
                if (_showProgress(book)) ...[
                  ProgressCard(userBookId: userBookId, book: book),
                  const SizedBox(height: 12),
                ],
                RecordSectionCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: ReadingStatusTile(
                          status: book.status,
                          summary: book.status.label,
                          countLabel:
                              _isFinishedLike(book) && book.rereadCount >= 2
                              ? '${book.rereadCount}회'
                              : null,
                          onTap: () =>
                              _openReadingStatusDialog(context, controller),
                        ),
                      ),
                      if (_showReadingDetails(book)) ...[
                        Container(
                          width: 1,
                          height: 40,
                          color: AppColors.border,
                          margin: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        Expanded(
                          child: RecordFieldTile(
                            label: '책 유형',
                            value: _sourceSummary(book),
                            hasValue:
                                BookSourceType.fromApiValue(book.sourceType) !=
                                null,
                            onTap: () =>
                                _openSourceDialog(context, ref, controller),
                            valueIcon: BookSourceType.fromApiValue(
                              book.sourceType,
                            )?.icon,
                            valueSecondary:
                                (book.platformName == null ||
                                    book.platformName!.isEmpty)
                                ? null
                                : book.platformName,
                            labelStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textMuted,
                            ),
                            valueStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textStrong,
                            ),
                            placeholderStyle: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_showReadingDetails(book)) ...[
                  const SizedBox(height: 12),
                  MetaSummaryCard(
                    startedAt: book.startedAt,
                    onTapStartedAt: () => _pickDate(
                      context,
                      controller,
                      current: book.startedAt,
                      isStartedAt: true,
                    ),
                    finishedAt: book.finishedAt,
                    onTapFinishedAt: () => _pickDate(
                      context,
                      controller,
                      current: book.finishedAt,
                      isStartedAt: false,
                    ),
                    showFinishedAt: _isFinishedLike(book),
                  ),
                ],
                if (_showReadingDetails(book)) ...[
                  const SizedBox(height: 12),
                  RecordSectionCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _IconField(
                            label: '명작',
                            icon: book.isMasterpiece
                                ? PhosphorIconsFill.crown
                                : PhosphorIconsRegular.crown,
                            color: book.isMasterpiece
                                ? AppColors.highlightGold
                                : AppColors.textMuted,
                            toggled: book.isMasterpiece,
                            onTap: () =>
                                _toggleMasterpiece(context, controller),
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 48,
                          color: AppColors.border,
                          margin: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        Expanded(
                          child: _IconField(
                            // 완독/재독 팝업(WantToRereadToggle)과 같은 반말
                            // 라벨 — "내가 나에게 남기는 기록" 원칙을 유지한다.
                            label: '또 볼래',
                            icon: book.wantToReread
                                ? PhosphorIconsFill.repeat
                                : PhosphorIconsRegular.repeat,
                            color: book.wantToReread
                                ? AppColors.error
                                : AppColors.textMuted,
                            toggled: book.wantToReread,
                            onTap: () =>
                                _toggleWantToReread(context, controller),
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 48,
                          color: AppColors.border,
                          margin: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        Expanded(
                          child: _IconField(
                            label: '난이도',
                            // 난이도를 아직 안 골랐으면 3단계 중 무엇도
                            // 아니라는 뜻이라 중립("보통") 표정을 옅게 보여준다.
                            icon:
                                DifficultyLevel.fromApiValue(
                                  book.difficulty,
                                )?.icon ??
                                PhosphorIconsRegular.smileyMeh,
                            color:
                                DifficultyLevel.fromApiValue(book.difficulty) !=
                                    null
                                ? AppColors.accentForeground
                                : AppColors.textMuted,
                            placeholder:
                                DifficultyLevel.fromApiValue(book.difficulty) ==
                                    null
                                ? DifficultyLevel.values
                                      .map((level) => level.label)
                                      .join(' · ')
                                : null,
                            // 아이콘만으로는 스크린 리더에 값이 전달되지
                            // 않아 현재 값(또는 미설정)을 라벨에 덧붙인다.
                            valueLabel:
                                DifficultyLevel.fromApiValue(
                                  book.difficulty,
                                )?.label ??
                                '설정 안 됨',
                            onTap: () =>
                                _openDifficultyDialog(context, controller),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_isFinishedLike(book)) ...[
                  const SizedBox(height: 12),
                  RatingReviewCard(userBookId: userBookId, book: book),
                ],
                const SizedBox(height: 12),
                RecordSectionCard(
                  child: RecordFieldTile(
                    label: '알게 된 경로',
                    value: book.discoverySource ?? '미설정',
                    hasValue: book.discoverySource != null,
                    onTap: () =>
                        _openDiscoverySourceDialog(context, controller),
                  ),
                ),
                const SizedBox(height: 12),
                RecordSectionCard(
                  child: TagSection(userBookId: userBookId, tags: book.tags),
                ),
                const SizedBox(height: 20),
                Center(
                  child: InkWell(
                    onTap: () => _confirmDelete(context, ref),
                    borderRadius: BorderRadius.circular(8),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 12,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            PhosphorIconsRegular.trash,
                            size: 16,
                            color: AppColors.textMuted,
                          ),
                          SizedBox(width: 6),
                          Text(
                            '서재에서 삭제',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (!isWantToRead)
              BookNoteList(userBookId: userBookId, bookTitle: book.title),
            if (!isWantToRead)
              BookReflectionList(userBookId: userBookId, bookTitle: book.title),
            BookSharingList(
              userBookId: userBookId,
              bookTitle: book.title,
              isbn13: book.isbn13,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await AppConfirm.show(
      context,
      title: '책 삭제',
      message: '이 책을 서재에서 삭제할까요? 삭제하면 되돌릴 수 없습니다.',
      confirmText: '삭제',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;

    AppLoading.show(context);
    try {
      await ref
          .read(bookRecordControllerProvider(userBookId).notifier)
          .deleteBook();
      if (context.mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (context.mounted) {
        AppSnackBar.error(context, e.message);
      }
    } finally {
      AppLoading.hide();
    }
  }

  /// 읽고 싶음 상태만 아니면(읽는 중/멈춤/중단/완독) 출처·독서 기간을
  /// 보여준다 — 요구사항이 명시한 예외는 읽고 싶음뿐이다.
  bool _showReadingDetails(BookItem book) =>
      book.status != BookStatus.wantToRead;

  /// 중단은 완독과, 멈춤은 읽는 중과 같은 취급으로 대응시킨다(사용자 확인
  /// 사항). finishedAt이 있으면 현재 상태가 무엇이든 과거에 한 번이라도
  /// 완독을 마친 책이라(`_onStatusTap`의 완독 재확인 로직과 동일한 근거),
  /// 완독일·재독 횟수·별점/한줄평처럼 "다 읽은 책"에서만 의미 있는 항목의
  /// 노출 여부는 이 값을 기준으로 판단한다.
  bool _isFinishedLike(BookItem book) =>
      book.status == BookStatus.finished ||
      book.status == BookStatus.stopped ||
      book.finishedAt != null;

  /// 진행률 카드를 보여줄지: 읽는 중/멈춤/중단 상태이면서(사용자 확인 사항
  /// — 완독은 제외) 총 진행 상한(오디오북은 100, 그 외는 총쪽수)을 아는
  /// 책만이다. 0은 "모른다"와 동일하게 취급해 빈 슬라이더를 막는다.
  bool _showProgress(BookItem book) {
    const eligibleStatuses = {
      BookStatus.reading,
      BookStatus.paused,
      BookStatus.stopped,
    };
    if (!eligibleStatuses.contains(book.status)) return false;
    final upperBound = book.progressUpperBound;
    return upperBound != null && upperBound > 0;
  }

  /// 완독 팝업에서 고른 출처까지 반영한 진행률 상한. 출처를 아직 고르지
  /// 않았으면 현재 책의 유형을 그대로 따르고, 오디오북이면 쪽수와 무관하게
  /// 100%를 저장한다.
  int? _completedProgressForSource(
    BookItem book,
    BookSourceType? selectedSource,
  ) {
    final isAudioBook =
        selectedSource == BookSourceType.audioBook ||
        (selectedSource == null && book.isAudioBook);
    return isAudioBook ? 100 : book.effectiveTotalPages;
  }

  String _sourceSummary(BookItem book) {
    final source = BookSourceType.fromApiValue(book.sourceType);
    if (source == null) {
      return BookSourceType.values.map((s) => s.label).join(' · ');
    }
    return source.label;
  }

  Future<void> _openReadingStatusDialog(
    BuildContext context,
    BookRecordController controller,
  ) async {
    final status = await showReadingStatusDialog(
      context,
      initialStatus: book.status,
    );
    if (status == null || !context.mounted) return;
    await _onStatusTap(context, controller, status);
  }

  Future<void> _toggleMasterpiece(
    BuildContext context,
    BookRecordController controller,
  ) {
    return controller.updateRecord(
      RecordPatch(isMasterpiece: !book.isMasterpiece),
    );
  }

  Future<void> _toggleWantToReread(
    BuildContext context,
    BookRecordController controller,
  ) {
    return controller.updateRecord(
      RecordPatch(wantToReread: !book.wantToReread),
    );
  }

  Future<void> _onStatusTap(
    BuildContext context,
    BookRecordController controller,
    BookStatus tapped,
  ) async {
    if (tapped == BookStatus.finished) {
      // finishedAt이 있으면 과거에 한 번 이상 완독한 책이다(현재 상태가
      // 완독이 아니어도 마찬가지) — 바로 완독 처리하지 않고 완독 횟수
      // 조정 팝업을 띄운다.
      if (book.finishedAt != null) {
        final result = await showRereadDialog(
          context,
          initialCount: book.rereadCount + 1,
          initialWantToReread: book.wantToReread,
        );
        if (result == null) return;
        switch (result) {
          case RereadCountUpdated(:final count, :final wantToReread):
            await controller.updateRecord(
              RecordPatch(
                // 이미 완독 상태면 status를 다시 보내지 않는다 — status가
                // FINISHED인데 finishedAt을 안 보내면 서버가 완독일을 오늘
                // 날짜로 새로 설정해버려(api-doc), 횟수만 고치려던 사용자의
                // 완독일이 의도치 않게 바뀐다. 완독이 아닌 상태(읽는 중 등)
                // 에서 재독을 완료하는 경우에만 상태를 FINISHED로 바꿔
                // 완독일이 오늘로 새로 기록되게 한다.
                status: book.status == BookStatus.finished
                    ? null
                    : tapped.apiValue,
                // 이미 기록된 완독일이 있으면 재독 완료로 상태를 다시
                // FINISHED로 바꿔도 그 날짜를 보낸다. 생략하면 서버가 오늘로
                // 자동 설정하므로, 최초 완독일이 의도치 않게 바뀐다.
                finishedAt: PatchField.value(_formatApiDate(book.finishedAt!)),
                rereadCount: count,
                wantToReread: wantToReread,
                // 총쪽수(오디오북은 100%)를 아는 책은 끝까지로 진행률을
                // 맞춘다(실제 웹 클라이언트와 동일 — 완독인데 진행률이
                // 중간에 멈춰 있는 모순 방지). 재독 팝업은 완독 상태가 아닌
                // 책에서도 열릴 수 있어 이 값이 항상 이미 반영돼 있지는 않다.
                currentPage: book.progressUpperBound,
              ),
            );
          case RereadFinishCancelled():
            // 실제 웹 클라이언트(BookRecordPage.tsx)도 완독 취소 시 재독
            // 횟수를 0으로 되돌린다 — 다음에 다시 완독 처리하면 재독
            // 횟수가 이전 값에서 이어지지 않고 새로 시작해야 자연스럽다.
            await controller.updateRecord(
              RecordPatch(
                status: BookStatus.reading.apiValue,
                currentPage: book.status == BookStatus.finished ? 0 : null,
                rereadCount: 0,
              ),
            );
        }
        return;
      }

      // 출처·난이도·평가(별점·한줄평)가 모두 이미 있으면 물어볼 게 없다 —
      // 팝업 없이 바로 완독 처리한다(요구사항: "입력할 항목이 없으면 즉시
      // 완독 처리"). 이 경우 명작/또 볼래는 팝업에서 손대지 않았으니 기존
      // 값을 그대로 둔다 — 완독 후에도 책 기록 화면의 명작/또 볼래 토글로
      // 계속 바꿀 수 있다.
      if (!finishConfirmNeedsDialog(book)) {
        await controller.updateRecord(
          RecordPatch(
            status: tapped.apiValue,
            currentPage: book.progressUpperBound,
          ),
        );
        return;
      }

      final result = await showFinishConfirmDialog(
        context,
        showSource: BookSourceType.fromApiValue(book.sourceType) == null,
        showDifficulty: DifficultyLevel.fromApiValue(book.difficulty) == null,
        showRatingReview: !hasRatingOrReview(book),
        showFinishedAt: true,
        initialWantToReread: book.wantToReread,
        initialIsMasterpiece: book.isMasterpiece,
      );
      if (result == null) return;
      final completedProgress = _completedProgressForSource(
        book,
        result.sourceType,
      );
      await controller.updateRecord(
        RecordPatch(
          status: tapped.apiValue,
          // 완독 팝업에서 새로 고른 출처의 단위를 따른다. 오디오북은 기존
          // 종이책 쪽수가 아니라 100(%)을 저장해야 한다.
          currentPage: completedProgress,
          wantToReread: result.wantToReread,
          isMasterpiece: result.isMasterpiece,
          // 완독 팝업에서 입력하지 않은 항목(이미 값이 있어 팝업에서 제외된
          // 항목 포함)은 아예 보내지 않는다(기존 값 유지) — 빈 값을 지움
          // 신호로 쓰지 않는다. 완독일도 팝업에서 고르지 않았으면(null)
          // 생략한다 — status가 FINISHED인데 finishedAt을 안 보내면 서버가
          // 오늘 날짜로 채운다(api-doc).
          sourceType: patchIfPresent(result.sourceType?.apiValue),
          difficulty: patchIfPresent(result.difficulty),
          myRating: patchIfPresent(result.myRating),
          shortReview: patchIfPresent(result.shortReview),
          finishedAt: patchIfPresent(
            result.finishedAt == null
                ? null
                : _formatApiDate(result.finishedAt!),
          ),
        ),
      );
      return;
    }

    if (tapped == book.status) return;

    await controller.updateRecord(
      RecordPatch(
        status: tapped.apiValue,
        // 완독을 취소하고 읽는 중으로 돌아가면 다음 독서를 새로 시작하는
        // 흐름이므로, 이전 완독 시점의 진행 쪽수를 남기지 않는다.
        currentPage:
            book.status == BookStatus.finished && tapped == BookStatus.reading
            ? 0
            : null,
      ),
    );
  }

  Future<void> _openSourceDialog(
    BuildContext context,
    WidgetRef ref,
    BookRecordController controller,
  ) async {
    Map<String, List<String>> options;
    try {
      options = await ref.read(platformOptionsProvider.future);
    } catch (_) {
      options = const {};
    }
    if (!context.mounted) return;

    final result = await showSourcePlatformDialog(
      context,
      initialSource: BookSourceType.fromApiValue(book.sourceType),
      initialPlatform: book.platformName,
      platformOptions: options,
      initialDisplayTotalPages: book.displayTotalPages,
      initialCurrentPage: book.currentPage,
    );
    if (result == null || !context.mounted) return;

    // 순수 출처 변경이든 전자책 쪽수 변경을 겸하든 항상 리포지토리의 단일
    // 진입점으로 보낸다 — currentPage 정리([BookItem.normalizedCurrentPageForSourceChange]
    // — 출처가 실제로 바뀌고 진행 기록이 있으면 0으로 초기화)를 다이얼로그를
    // 연 시점에 캡처해 둔 [book] 대신 저장 시작 시점의 최신 로컬 행 기준으로
    // 계산하기 위함이다(리포지토리 문서 참고). 사용자에게는
    // [showSourcePlatformDialog]가 출처를 고르는 시점에 미리 경고 확인을
    // 받는다.
    AppLoading.show(context);
    try {
      await controller.updateSourceType(
        sourceType: result.sourceType.apiValue,
        platformName: result.platformName,
        displayTotalPages: result.displayTotalPages,
      );
    } on ApiException catch (e) {
      if (context.mounted) AppSnackBar.error(context, e.message);
    } finally {
      AppLoading.hide();
    }
  }

  Future<void> _openDifficultyDialog(
    BuildContext context,
    BookRecordController controller,
  ) async {
    final value = await showDifficultyDialog(
      context,
      initialDifficulty: book.difficulty,
    );
    if (value == null) return;
    await controller.updateRecord(
      RecordPatch(difficulty: PatchField.value(value)),
    );
  }

  Future<void> _pickDate(
    BuildContext context,
    BookRecordController controller, {
    required DateTime? current,
    required bool isStartedAt,
  }) async {
    final now = DateTime.now();
    // 완독 상태에서 완독일이 아직 없으면 서버가 어차피 오늘로 채운다(아래
    // canClear 주석 참고) — 시트를 열 때도 미리 오늘을 선택해 둬서, 매번
    // 오늘 날짜를 달력에서 다시 찾아 탭하지 않아도 되게 한다.
    final effectiveInitial =
        (!isStartedAt && current == null && book.status == BookStatus.finished)
        ? now
        : current;
    final result = await showReadingDateDialog(
      context,
      initialDate: effectiveInitial,
      lastDate: now,
      isStartedAt: isStartedAt,
      // 완독 상태에서는 완독일을 지울 수 없다 — 서버가 삭제를 무시하고 기존
      // 값(없으면 오늘)을 유지한다(api-doc). 날짜를 없애려면 상태를 먼저
      // 바꿔야 한다.
      canClear: isStartedAt || book.status != BookStatus.finished,
    );
    if (result == null) return;
    // "선택 해제"는 명시적 null(삭제), 날짜 선택은 그 값으로 수정이다.
    // 고르지 않은 쪽(시작일/완독일 중 다른 하나)은 아예 담지 않아 요청에서
    // 빠진다(기존 값 유지).
    final picked = result.cleared
        ? const PatchField<String>.clear()
        : PatchField.value(_formatApiDate(result.date!));
    await controller.updateRecord(
      RecordPatch(
        startedAt: isStartedAt ? picked : null,
        finishedAt: isStartedAt ? null : picked,
      ),
    );
  }

  String _formatApiDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<void> _openDiscoverySourceDialog(
    BuildContext context,
    BookRecordController controller,
  ) async {
    final value = await showDiscoverySourceDialog(
      context,
      initialValue: book.discoverySource,
    );
    if (value == null) return;
    await controller.updateRecord(
      RecordPatch(
        // 입력을 비운 채 저장했으면 "지움"(명시적 null)이다 — 빈 문자열은
        // 서버가 삭제가 아니라 값으로 저장하므로 그대로 보내면 안 된다.
        discoverySource: value.isEmpty
            ? const PatchField.clear()
            : PatchField.value(value),
      ),
    );
  }
}

/// 명작/또 볼래/난이도처럼 값이 아이콘 하나로 요약되는 필드를 텍스트 없이
/// 아이콘만으로 보여주는 열. `RecordFieldTile`과 같은 행 안에서 나란히
/// 쓰이므로 라벨 스타일은 맞추고, 값 자리만 아이콘으로 대신한다. 세 필드가
/// 항상 같은 크기로 보이도록 아이콘·색만 호출부가 넘기고 크기는 고정한다.
/// 부모가 `Expanded`로 감싸 폭을 나눠주므로 여기서는 폭을 직접 제한하지
/// 않아도 라벨이 한없이 늘어나지 않는다.
class _IconField extends StatelessWidget {
  const _IconField({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.placeholder,
    this.toggled,
    this.valueLabel,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String? placeholder;

  /// 명작/또 볼래처럼 값이 예/아니오뿐인 필드만 넘긴다 — 스크린 리더가
  /// 라벨 뒤에 켜짐/꺼짐 상태를 자동으로 읽어준다.
  final bool? toggled;

  /// 난이도처럼 값이 예/아니오가 아닌 필드의 현재 값(예: "쉬움")을 스크린
  /// 리더에 전달한다 — 화면에는 아이콘만 보이고 값 이름 자체는 안 보여서다.
  final String? valueLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: toggled,
      label: valueLabel == null ? label : '$label, $valueLabel',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: AppColors.textStrong,
              ),
            ),
            const SizedBox(height: 6),
            if (placeholder == null)
              Icon(icon, size: 24, color: color)
            else
              Text(
                placeholder!,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 탭 바를 스크롤 상단에 고정하기 위한 델리게이트.
class _TabBarHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _TabBarHeaderDelegate(this.tabBar);

  final TabBar tabBar;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(color: AppColors.pageBackground, child: tabBar);
  }

  @override
  bool shouldRebuild(covariant _TabBarHeaderDelegate oldDelegate) =>
      tabBar != oldDelegate.tabBar;
}

class _Header extends ConsumerWidget {
  const _Header({required this.book, required this.onEditBookInfo});

  final BookItem book;
  final VoidCallback onEditBookInfo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 색을 맞출 카테고리가 애초에 없는 책이면 카테고리 목록 provider를
    // 구독하지 않는다(불필요한 리빌드/조회 방지).
    Color? categoryColor;
    if (book.displayCategoryId != null) {
      final categories = ref.watch(bookCategoriesProvider).valueOrNull;
      if (categories != null) {
        for (final category in categories) {
          if (category.id == book.displayCategoryId) {
            categoryColor = category.color;
            break;
          }
        }
      }
    }

    return RecordSectionCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onEditBookInfo,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 84,
                child: BookCover(
                  imageUrl: book.coverImageUrl,
                  title: book.title,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (book.category != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: (categoryColor ?? AppColors.controlInactive)
                              .withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          book.category!,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textBody,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                        color: AppColors.textStrong,
                      ),
                    ),
                    if (book.author != null && book.author!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        displayAuthor(book.author!),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                    if (book.publisher != null &&
                        book.publisher!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        book.publisher!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
