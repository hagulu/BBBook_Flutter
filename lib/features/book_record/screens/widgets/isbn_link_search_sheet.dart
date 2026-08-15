import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../book_search/models/book_search_item.dart';
import '../../../book_search/providers/book_search_providers.dart';
import '../../../book_search/screens/widgets/search_result_card.dart';

/// "책 정보 수정 > ISBN > 변경"(및 미연결 책의 최초 연결) 전용 검색·선택
/// 바텀시트. `BookSearchScreen`은 결과를 탭하면 책 상세로 이동하지만, 이
/// 시트는 탭한 책의 ISBN을 바로 `Navigator.pop`으로 돌려주고 닫힌다.
///
/// `bookSearchControllerProvider`(패밀리가 아닌 단일 autoDispose provider)를
/// 그대로 재사용하면, 검색 화면이 이미 열려 있는 상태에서 이 시트를 겹쳐
/// 열었을 때 두 화면이 같은 인스턴스를 공유해 서로의 검색 상태를 덮어쓸 수
/// 있다 — 그래서 `BookSearchApi`만 직접 불러 시트 자체 상태로 검색을 관리한다.
Future<String?> showIsbnLinkSearchSheet(
  BuildContext context, {
  required String initialQuery,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _IsbnLinkSearchSheet(initialQuery: initialQuery),
  );
}

class _IsbnLinkSearchSheet extends ConsumerStatefulWidget {
  const _IsbnLinkSearchSheet({required this.initialQuery});

  final String initialQuery;

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
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '책 연결',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.titleText,
                  ),
                ),
              ),
            ),
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
                onTap: () => Navigator.of(context).pop(item.isbn),
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
