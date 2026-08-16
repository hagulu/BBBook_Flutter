import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../book_search/models/book_search_item.dart';
import '../../../book_search/providers/book_search_providers.dart';
import '../../../book_search/screens/widgets/search_result_card.dart';
import '../../../bookshelf/providers/bookshelf_providers.dart';
import '../../providers/book_record_providers.dart';
import 'bulk_link_progress_bar.dart';
import 'pill_option.dart';

/// [showIsbnLinkSearchSheet] 결과 종류. [picked]만 [isbn]이 채워진다.
/// [savedDirectly]는 "즉시 저장"이 켜진 상태에서 고른 뒤 이 시트가 연결
/// PATCH 응답까지 기다려 스스로 반영을 끝냈다는 뜻이다 — 호출부는 책 정보
/// 수정 시트를 열 필요 없이 그냥 다음으로 넘어가면 된다.
enum IsbnSearchAction { picked, skip, stop, savedDirectly }

/// [showIsbnLinkSearchSheet]의 결과. 바텀시트를 바깥 탭/뒤로가기로 그냥
/// 닫으면(취소) 이 타입 자체가 아니라 `null`이 반환된다 — [skip]/[stop]은
/// 일괄 연결 흐름에서 진행/중단 버튼을 명시적으로 눌렀을 때만 나온다.
class IsbnSearchResult {
  const IsbnSearchResult.picked(this.isbn) : action = IsbnSearchAction.picked;
  const IsbnSearchResult.skip() : isbn = null, action = IsbnSearchAction.skip;
  const IsbnSearchResult.stop() : isbn = null, action = IsbnSearchAction.stop;
  const IsbnSearchResult.savedDirectly()
    : isbn = null,
      action = IsbnSearchAction.savedDirectly;

  final String? isbn;
  final IsbnSearchAction action;
}

/// "책 정보 수정 > ISBN > 변경"(및 미연결 책의 최초 연결) 전용 검색·선택
/// 바텀시트. `BookSearchScreen`은 결과를 탭하면 책 상세로 이동하지만, 이
/// 시트는 탭한 책의 ISBN을 바로 `Navigator.pop`으로 돌려주고 닫힌다.
///
/// [bulkProgress]가 non-null이면(완독 목록의 ISBN 일괄 연결 흐름 —
/// `bulk_isbn_link_banner.dart`) 진행 상황과 "건너뛰기"/"중단" 버튼, "즉시
/// 저장"·"목록에서 제외" 토글을 함께 보여준다. [immediateSave]가 켜져
/// 있으면 [userBookId]로 연결 PATCH 응답까지 기다린 뒤에만(로딩 표시)
/// 닫힌다 — 다음 책으로 넘어가기 전에 이 책이 실제로 저장됐다는 걸
/// 보장한다. [excludeFromList]가 켜진 채로 "건너뛰기"를 누르면 이 책을
/// 로컬에 기록해 다음부터 완독 목록의 "ISBN 미연결" 배너/일괄 연결 흐름에
/// 아예 나오지 않게 한다.
///
/// `bookSearchControllerProvider`(패밀리가 아닌 단일 autoDispose provider)를
/// 그대로 재사용하면, 검색 화면이 이미 열려 있는 상태에서 이 시트를 겹쳐
/// 열었을 때 두 화면이 같은 인스턴스를 공유해 서로의 검색 상태를 덮어쓸 수
/// 있다 — 그래서 `BookSearchApi`만 직접 불러 시트 자체 상태로 검색을 관리한다.
Future<IsbnSearchResult?> showIsbnLinkSearchSheet(
  BuildContext context, {
  required String initialQuery,
  ({int index, int total})? bulkProgress,
  int? userBookId,
  ValueNotifier<bool>? immediateSave,
  ValueNotifier<bool>? excludeFromList,
}) {
  return showModalBottomSheet<IsbnSearchResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _IsbnLinkSearchSheet(
      initialQuery: initialQuery,
      bulkProgress: bulkProgress,
      userBookId: userBookId,
      immediateSave: immediateSave,
      excludeFromList: excludeFromList,
    ),
  );
}

class _IsbnLinkSearchSheet extends ConsumerStatefulWidget {
  const _IsbnLinkSearchSheet({
    required this.initialQuery,
    this.bulkProgress,
    this.userBookId,
    this.immediateSave,
    this.excludeFromList,
  });

  final String initialQuery;
  final ({int index, int total})? bulkProgress;
  final int? userBookId;
  final ValueNotifier<bool>? immediateSave;
  final ValueNotifier<bool>? excludeFromList;

  @override
  ConsumerState<_IsbnLinkSearchSheet> createState() =>
      _IsbnLinkSearchSheetState();
}

enum _LoadState { idle, loading, loaded, error }

class _IsbnLinkSearchSheetState extends ConsumerState<_IsbnLinkSearchSheet> {
  late final _queryController = TextEditingController(
    text: widget.initialQuery,
  );

  static const _size = 10;

  int _requestId = 0;
  _LoadState _loadState = _LoadState.idle;
  List<BookSearchItem> _items = const [];
  int _page = 1;
  int _totalResults = 0;
  bool _isSkipping = false;

  int get _totalPages =>
      _totalResults <= 0 ? 1 : (_totalResults / _size).ceil();

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  void _search() {
    FocusManager.instance.primaryFocus?.unfocus();
    _fetch(page: 1);
  }

  Future<void> _fetch({required int page}) async {
    final query = _queryController.text.trim();
    if (query.isEmpty) return;
    final requestId = ++_requestId;
    setState(() => _loadState = _LoadState.loading);
    try {
      final result = await ref
          .read(bookSearchApiProvider)
          .searchBooks(query: query, page: page, size: _size);
      if (requestId != _requestId || !mounted) return;
      setState(() {
        _items = result.items;
        _page = result.page;
        _totalResults = result.totalResults;
        _loadState = _LoadState.loaded;
      });
    } on ApiException {
      if (requestId != _requestId || !mounted) return;
      setState(() => _loadState = _LoadState.error);
    }
  }

  /// 결과 카드를 골랐을 때. "즉시 저장"이 켜져 있으면 이 시트가 직접
  /// 연결 PATCH 응답까지 기다린 뒤 닫는다 — 그러지 않으면 평소처럼 고른
  /// isbn만 바로 돌려주고, 책 정보 수정 시트가 필드를 채워 사용자가
  /// 검토·저장하게 한다.
  Future<void> _handlePick(String isbn) async {
    if (widget.userBookId != null && (widget.immediateSave?.value ?? false)) {
      await _saveDirectly(isbn);
      return;
    }
    Navigator.of(context).pop(IsbnSearchResult.picked(isbn));
  }

  Future<void> _saveDirectly(String isbn) async {
    AppLoading.show(context);
    try {
      await ref
          .read(bookRecordControllerProvider(widget.userBookId!).notifier)
          .linkBook(isbn13: isbn);
      if (mounted) {
        Navigator.of(context).pop(const IsbnSearchResult.savedDirectly());
      }
    } on ApiException catch (e) {
      if (mounted) {
        AppSnackBar.error(context, e.message);
        Navigator.of(context).pop(const IsbnSearchResult.skip());
      }
    } finally {
      AppLoading.hide();
    }
  }

  /// "건너뛰기" — "목록에서 제외"가 켜져 있으면 이 책을 로컬에 기록해
  /// 완독 목록의 "ISBN 미연결" 배너/개수에서 다음부터 빠지게 한다. 로컬
  /// 쓰기라도 실패할 수 있으니(디스크 오류 등) 응답을 기다린 뒤에만
  /// 시트를 닫는다 — 실패하면 사용자가 "건너뛰기를 안 눌린 셈"이 되는 걸
  /// 모른 채 다음 책으로 넘어가지 않도록 스낵바로 알리고 시트를 그대로
  /// 둬서 다시 시도할 수 있게 한다. [_isSkipping]으로 처리 중 중복 탭도 막는다.
  Future<void> _handleSkip() async {
    if (_isSkipping) return;
    if (!(widget.userBookId != null && (widget.excludeFromList?.value ?? false))) {
      Navigator.of(context).pop(const IsbnSearchResult.skip());
      return;
    }
    setState(() => _isSkipping = true);
    try {
      await ref
          .read(bookshelfRepositoryProvider)
          .markIsbnLinkDismissed(widget.userBookId!);
      ref.read(bookshelfSyncVersionProvider.notifier).state++;
      if (mounted) Navigator.of(context).pop(const IsbnSearchResult.skip());
    } catch (_) {
      if (mounted) {
        setState(() => _isSkipping = false);
        AppSnackBar.error(context, '건너뛰기 처리에 실패했습니다. 다시 시도해주세요.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 흰 배경 컨테이너가 화면 맨 아래까지 이어지도록 SafeArea로 감싸 크기를
    // 줄이는 대신, 하단 세이프 에어리어(홈 인디케이터 등)만큼을 컨테이너
    // 내부 패딩에 더한다(record_dialog_shell.dart와 동일한 처리) — 검색
    // 결과 목록은 길이가 가변적이라 다른 바텀시트처럼 내용에 맞춰 크기를
    // 줄이는 대신 화면의 85%를 고정 높이로 잡고 그 안에서 목록만 스크롤한다.
    return Material(
      color: Colors.transparent,
      child: Container(
        height: MediaQuery.sizeOf(context).height * 0.85,
        decoration: const BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(
          top: 12,
          bottom:
              MediaQuery.viewInsetsOf(context).bottom +
              MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: Column(
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 제목은 왼쪽, 진행 개수 + 건너뛰기/중단은 오른쪽에 묶는다
            // (좁은 화면·큰 글자 배율에서는 `Wrap`이 오른쪽 묶음을 다음
            // 줄로 자연스럽게 내린다).
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              // 이 시트를 감싼 바깥 `Column`이 `crossAxisAlignment`를
              // 지정하지 않아(기본값 center) `Wrap`이 그냥 두면 자기
              // 콘텐츠 폭만큼만 차지해 `spaceBetween`이 벌릴 여유 공간이
              // 없다 — `SizedBox(width: double.infinity)`로 가로 폭을
              // 강제로 꽉 채운다.
              child: SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    const Text(
                      '책 연결',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.titleText,
                      ),
                    ),
                    if (widget.bulkProgress != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${widget.bulkProgress!.index} / ${widget.bulkProgress!.total}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.tertiaryText,
                            ),
                          ),
                          const SizedBox(width: 10),
                          SkipStopButtons(
                            onSkip: _handleSkip,
                            onStop: () => Navigator.of(
                              context,
                            ).pop(const IsbnSearchResult.stop()),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            if (widget.bulkProgress != null &&
                widget.userBookId != null &&
                (widget.immediateSave != null ||
                    widget.excludeFromList != null)) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                // 위 제목 행과 같은 이유로 `SizedBox`로 가로 폭을 꽉
                // 채워야 `spaceBetween`이 두 토글을 양 끝으로 벌린다.
                child: SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ?widget.immediateSave != null
                          ? ValueListenableBuilder<bool>(
                              valueListenable: widget.immediateSave!,
                              builder: (context, checked, _) => PillOption(
                                label: '즉시 저장',
                                icon: PhosphorIconsRegular.lightning,
                                selected: checked,
                                onTap: () =>
                                    widget.immediateSave!.value = !checked,
                              ),
                            )
                          : null,
                      ?widget.excludeFromList != null
                          ? ValueListenableBuilder<bool>(
                              valueListenable: widget.excludeFromList!,
                              builder: (context, checked, _) => PillOption(
                                label: '연결 대상 목록에서 제외',
                                icon: PhosphorIconsRegular.eyeSlash,
                                selected: checked,
                                onTap: () =>
                                    widget.excludeFromList!.value = !checked,
                              ),
                            )
                          : null,
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TextField(
                controller: _queryController,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '책, 저자, ISBN으로 검색',
                  prefixIcon: Icon(
                    PhosphorIconsRegular.magnifyingGlass,
                    size: 18,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    switch (_loadState) {
      case _LoadState.idle:
        return const Center(
          child: Text(
            '검색어를 입력해주세요',
            style: TextStyle(color: AppColors.tertiaryText),
          ),
        );
      case _LoadState.loading:
        return const Center(
          child: Text('검색 중...', style: TextStyle(color: AppColors.tertiaryText)),
        );
      case _LoadState.error:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '검색 중 문제가 발생했습니다.',
                style: TextStyle(color: AppColors.tertiaryText),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: _search, child: const Text('다시 시도')),
            ],
          ),
        );
      case _LoadState.loaded:
        if (_items.isEmpty) {
          return const Center(
            child: Text(
              '검색 결과가 없습니다',
              style: TextStyle(color: AppColors.tertiaryText),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          children: [
            for (final item in _items) ...[
              SearchResultCard(
                item: item,
                onTap: () => _handlePick(item.isbn),
              ),
              const SizedBox(height: 10),
            ],
            if (_totalPages > 1) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: _page > 1 ? () => _fetch(page: _page - 1) : null,
                    icon: const Icon(PhosphorIconsRegular.caretLeft, size: 18),
                  ),
                  Text(
                    '$_page / $_totalPages',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.tertiaryText,
                    ),
                  ),
                  IconButton(
                    onPressed: _page < _totalPages
                        ? () => _fetch(page: _page + 1)
                        : null,
                    icon: const Icon(PhosphorIconsRegular.caretRight, size: 18),
                  ),
                ],
              ),
            ],
          ],
        );
    }
  }
}
