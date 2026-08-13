import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../book_detail/screens/book_detail_screen.dart';
import '../../book_record/screens/book_record_screen.dart';
import '../providers/book_search_providers.dart';
import 'barcode_scan_screen.dart';
import 'widgets/custom_book_dialog.dart';
import 'widgets/search_result_card.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// 책 검색 화면(`/search` 대응, book-search.md). 하단 탭 셸의 "+" 버튼으로
/// 진입하는 별도 화면이라 `Navigator.push`로 연다(BookRecordScreen과 동일 패턴).
class BookSearchScreen extends ConsumerStatefulWidget {
  const BookSearchScreen({super.key});

  @override
  ConsumerState<BookSearchScreen> createState() => _BookSearchScreenState();
}

class _BookSearchScreenState extends ConsumerState<BookSearchScreen> {
  final _queryController = TextEditingController();

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  void _submit() {
    FocusManager.instance.primaryFocus?.unfocus();
    ref.read(bookSearchControllerProvider.notifier).search(_queryController.text);
  }

  void _clear() {
    _queryController.clear();
    FocusManager.instance.primaryFocus?.unfocus();
    ref.read(bookSearchControllerProvider.notifier).clear();
    setState(() {});
  }

  Future<void> _openCustomBookDialog() async {
    final result = await showCustomBookDialog(context);
    if (result == null || !mounted) return;
    if (result.synced) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BookRecordScreen(userBookId: result.userBookId),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('등록되었습니다. 목록 반영에 시간이 걸릴 수 있어요. 잠시 후 책장에서 확인해주세요.'),
        ),
      );
    }
  }

  void _openDetail(String isbn) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => BookDetailScreen(isbn: isbn)),
    );
  }

  /// 바코드(ISBN) 스캔에 성공하면 검색 결과를 거치지 않고 바로 책 상세로 이동한다.
  Future<void> _scanBarcode() async {
    final isbn = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const BarcodeScanScreen()));
    if (isbn != null && mounted) _openDetail(isbn);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bookSearchControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('책 검색'),
        backgroundColor: AppColors.pageBackground,
        foregroundColor: AppColors.titleText,
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _queryController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _submit(),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                hintText: '책, 저자, ISBN으로 검색',
                prefixIcon: const Icon(
                  PhosphorIconsRegular.magnifyingGlass,
                  size: 18,
                ),
                suffixIcon: _queryController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(PhosphorIconsRegular.x, size: 18),
                        onPressed: _clear,
                      ),
              ),
            ),
          ),
          if (state.hasQuery)
            Expanded(
              child: _SearchResultsBody(
                state: state,
                onOpenDetail: _openDetail,
                onGoToPage: (page) =>
                    ref.read(bookSearchControllerProvider.notifier).goToPage(page),
                onRetry: _submit,
              ),
            )
          else
            // 검색어가 없을 때만 노출되는 진입점이라 Expanded로 감싸 남는
            // 화면 아래쪽 전체를 차지하지 않고, 버튼 자체 높이만 차지하게 한다.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: _EmptyQueryActions(
                onTapCustomBook: _openCustomBookDialog,
                onTapScan: _scanBarcode,
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyQueryActions extends StatelessWidget {
  const _EmptyQueryActions({required this.onTapCustomBook, required this.onTapScan});

  final VoidCallback onTapCustomBook;
  final VoidCallback onTapScan;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _CompactActionButton(
            icon: PhosphorIconsRegular.notePencil,
            label: '직접 등록',
            onTap: onTapCustomBook,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _CompactActionButton(
            icon: PhosphorIconsRegular.barcode,
            label: '바코드로 등록',
            onTap: onTapScan,
          ),
        ),
      ],
    );
  }
}

class _CompactActionButton extends StatelessWidget {
  const _CompactActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cardBackground,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.accentLight,
                child: Icon(icon, color: AppColors.primary, size: 20),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppColors.titleText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchResultsBody extends StatelessWidget {
  const _SearchResultsBody({
    required this.state,
    required this.onOpenDetail,
    required this.onGoToPage,
    required this.onRetry,
  });

  final BookSearchState state;
  final ValueChanged<String> onOpenDetail;
  final ValueChanged<int> onGoToPage;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (state.isLoading) {
      return const Center(
        child: Text('검색 중...', style: TextStyle(color: AppColors.tertiaryText)),
      );
    }

    final error = state.error;
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_errorMessage(error), style: const TextStyle(color: AppColors.tertiaryText)),
            if (error != BookSearchErrorType.auth) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: onRetry, child: const Text('다시 시도')),
            ],
          ],
        ),
      );
    }

    if (state.items.isEmpty) {
      return const Center(
        child: Text(
          '검색 결과가 없습니다',
          style: TextStyle(color: AppColors.tertiaryText),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        for (final item in state.items) ...[
          SearchResultCard(item: item, onTap: () => onOpenDetail(item.isbn)),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 8),
        _PaginationBar(
          page: state.page,
          totalPages: state.totalPages,
          onGoToPage: onGoToPage,
        ),
      ],
    );
  }

  String _errorMessage(BookSearchErrorType error) => switch (error) {
    BookSearchErrorType.auth => '인증이 만료되었습니다.',
    BookSearchErrorType.server => '검색 중 문제가 발생했습니다.',
    BookSearchErrorType.network => '네트워크 연결을 확인해주세요.',
  };
}

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.page,
    required this.totalPages,
    required this.onGoToPage,
  });

  final int page;
  final int totalPages;
  final ValueChanged<int> onGoToPage;

  /// 최대 3개 페이지 번호 윈도우 + 마지막 페이지 고정 노출 + 말줄임(book-search.md).
  List<int?> _pageItems() {
    if (totalPages <= 1) return const [1];
    var start = page - 1;
    var end = page + 1;
    if (start < 1) {
      end += 1 - start;
      start = 1;
    }
    if (end > totalPages) {
      start -= end - totalPages;
      end = totalPages;
    }
    start = start < 1 ? 1 : start;

    final items = <int?>[for (var p = start; p <= end; p++) p];
    if (end < totalPages) {
      if (end < totalPages - 1) items.add(null);
      items.add(totalPages);
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    if (totalPages <= 1) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: page > 1 ? () => onGoToPage(page - 1) : null,
          icon: const Icon(PhosphorIconsRegular.caretLeft, size: 18),
        ),
        for (final item in _pageItems())
          item == null
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text('···', style: TextStyle(color: AppColors.tertiaryText)),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: _PageNumberButton(
                    page: item,
                    selected: item == page,
                    onTap: () => onGoToPage(item),
                  ),
                ),
        IconButton(
          onPressed: page < totalPages ? () => onGoToPage(page + 1) : null,
          icon: const Icon(PhosphorIconsRegular.caretRight, size: 18),
        ),
      ],
    );
  }
}

class _PageNumberButton extends StatelessWidget {
  const _PageNumberButton({
    required this.page,
    required this.selected,
    required this.onTap,
  });

  final int page;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: selected ? null : onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Text(
          '$page',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.bodyText,
          ),
        ),
      ),
    );
  }
}
