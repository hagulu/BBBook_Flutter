import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_alert.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../book_record/models/record_labels.dart';
import '../../bookshelf/models/book_status.dart';
import '../../bookshelf/providers/bookshelf_providers.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// 책 뒷면 바코드(ISBN-13/EAN-13)를 카메라로 스캔하는 화면. 검색 화면의
/// "바코드로 등록" 버튼에서 진입한다(사용자 직접 요청 — book_search.md에는
/// 없는 기능).
///
/// 두 가지 모드로 동작한다.
/// - 기본(빠른 등록 미체크): 스캔에 성공하면 ISBN 문자열을 pop하고, 호출부가
///   책 상세 화면으로 이동해 상세 확인 후 서재 담기를 진행한다.
/// - 빠른 등록 체크: 화면을 닫지 않고 스캔한 책을 선택한 상태로 바로 서재에
///   담은 뒤 계속 스캔한다(여러 권을 연달아 등록하는 용도).
///
/// 뒤로가기로 닫으면 null을 반환한다.
class BarcodeScanScreen extends ConsumerStatefulWidget {
  const BarcodeScanScreen({super.key});

  @override
  ConsumerState<BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

class _BarcodeScanScreenState extends ConsumerState<BarcodeScanScreen> {
  // ISBN-13은 EAN-13 바코드 값과 그대로 같다(978/979로 시작하는 13자리).
  static final _isbn13Pattern = RegExp(r'^(978|979)\d{10}$');
  static const _quickStatuses = [
    BookStatus.wantToRead,
    BookStatus.reading,
    BookStatus.finished,
  ];

  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.ean13],
  );
  bool _handled = false;

  /// 바코드는 인식됐지만 ISBN 형식이 아닐 때 잠깐 안내 문구로 바꿔 보여준다.
  /// 스캔 자체는 멈추지 않고(`onDetect`가 다음 프레임에도 계속 불림) 계속
  /// 시도되므로 별도의 "재시도" 트리거는 필요 없다.
  bool _sawNonIsbnBarcode = false;

  bool _quickRegister = false;
  BookStatus _quickStatus = BookStatus.finished;

  /// 빠른 등록 API 호출이 진행 중인 동안 같은 프레임에서 또 감지된 바코드로
  /// 중복 요청을 보내지 않게 막는다.
  bool _processing = false;

  /// 카메라가 같은 바코드를 계속 비추고 있는 동안(사용자가 아직 다음 책으로
  /// 넘어가지 않음) 매 프레임 중복 등록 요청을 보내지 않기 위한 마지막 처리
  /// 값. 다른 바코드가 잡히면 그 값으로 교체된다.
  String? _lastProcessedIsbn;

  /// 안드로이드 네이티브 구현은 바코드를 하나도 못 찾은 프레임에서는 이벤트
  /// 자체를 보내지 않는다(플러그인 소스 확인:
  /// `MobileScanner.kt`의 `if (barcodeMap.isEmpty()) { ...; return }`) — 즉
  /// [BarcodeCapture.barcodes]가 빈 상태로 [_onDetect]가 불리는 경우는 사실상
  /// 없다고 봐야 한다. 그래서 "ISBN이 아닌 바코드가 잡힘" 안내는 카메라가
  /// 다른 곳을 비춰 감지가 끊겨도 자동으로 사라지지 않으므로, 이 타이머로
  /// 일정 시간 뒤 스스로 지운다.
  Timer? _clearWarningTimer;

  @override
  void dispose() {
    _controller.dispose();
    _clearWarningTimer?.cancel();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled || _processing || !mounted) return;

    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && _isbn13Pattern.hasMatch(value)) {
        _clearWarningTimer?.cancel();
        if (_sawNonIsbnBarcode) setState(() => _sawNonIsbnBarcode = false);

        if (_quickRegister) {
          if (value == _lastProcessedIsbn) return;
          _lastProcessedIsbn = value;
          unawaited(_quickRegisterBook(value));
        } else {
          _handled = true;
          Navigator.of(context).pop(value);
        }
        return;
      }
    }

    if (capture.barcodes.isEmpty) return;

    // 바코드는 잡혔지만(예: 다른 상품 바코드) 978/979로 시작하는 13자리가
    // 아니다 — 등록을 시도하지 않고 안내만 보여준 채 계속 스캔한다. 이후
    // 2초간 같은 상황이 이어지지 않으면(다른 유효한 프레임이 없어도) 안내를
    // 스스로 지운다.
    if (!_sawNonIsbnBarcode) setState(() => _sawNonIsbnBarcode = true);
    _lastProcessedIsbn = null;
    _clearWarningTimer?.cancel();
    _clearWarningTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _sawNonIsbnBarcode = false);
    });
  }

  /// 스캔 성공(→ 여기 도달한 시점) → 등록 중(로딩 오버레이) → 등록완료(스낵바)
  /// 흐름. 화면을 닫지 않으므로 완료/실패 어느 쪽이든 바로 다음 바코드를
  /// 이어서 스캔할 수 있다.
  Future<void> _quickRegisterBook(String isbn13) async {
    // 요청 도중 사용자가 상태 pill을 바꿀 수 있으므로, 실제로 등록에 쓰인
    // 상태를 고정해 완료 스낵바 라벨이 어긋나지 않게 한다.
    final status = _quickStatus;
    setState(() => _processing = true);
    try {
      final result = await ref
          .read(bookshelfRepositoryProvider)
          .createIsbnBook(
            isbn13: isbn13,
            title: 'ISBN $isbn13',
            status: status,
          );
      ref.read(bookshelfSyncVersionProvider.notifier).state++;
      // 서버 반영 여부(serverId)와 무관하게 "서재에 담겼다"는 사실은 로컬
      // 저장 시점에 확정된다 — 오프라인이나 로컬 저장 모드에서는 serverId가
      // 계속 null이라, 이 조건을 걸면 연속 스캔 화면에 아무 피드백이 없다.
      if (mounted) {
        AppSnackBar.success(
          context,
          '\'${result.title}\' 책 등록완료 (${status.label})',
          duration: const Duration(seconds: 2),
          replaceCurrent: true,
        );
      }
    } on ApiException catch (e) {
      // 409(이미 서재에 있음)는 같은 책을 계속 비추고 있는 한 재시도해도
      // 결과가 같으니 _lastProcessedIsbn을 유지해 중복 요청을 막는다. 그 외
      // 실패(네트워크 오류 등)는 풀어줘서 같은 책을 바로 재시도할 수 있게 한다.
      if (e.statusCode != 409) _lastProcessedIsbn = null;
      if (mounted) {
        AppSnackBar.error(
          context,
          e.message,
          duration: const Duration(seconds: 2),
          replaceCurrent: true,
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('바코드로 등록'),
      ),
      // 카메라/스캔 프레임 영역은 원래대로 화면 전체를 채우고, 빠른 등록
      // 컨트롤은 별도 구획 없이 그 위에 오버레이로 얹는다(배경 패널 없음).
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '카메라를 사용할 수 없습니다.\n설정에서 카메라 권한을 허용해주세요.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),
          ),
          const _ScanFrame(),
          // 바코드 인식(스캔 성공) 직후부터 등록 API 응답이 올 때까지("등록
          // 중") 프레임 자리에 겹쳐 보여준다. 끝나면 스낵바로 결과를 알리고
          // 사라진다.
          if (_processing)
            const Positioned.fill(
              child: IgnorePointer(
                child: Center(child: _RegisteringIndicator()),
              ),
            ),
          Positioned(
            // AppBar 뒤로가기 버튼과 겹치지 않게, 상단에 여유 있게 간격을 둔다.
            top: 32,
            left: 16,
            right: 16,
            child: SafeArea(
              bottom: false,
              child: _ControlBar(
                quickRegister: _quickRegister,
                onQuickRegisterChanged: (v) =>
                    setState(() => _quickRegister = v ?? false),
                quickStatus: _quickStatus,
                quickStatuses: _quickStatuses,
                onStatusSelected: (status) =>
                    setState(() => _quickStatus = status),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 32,
            child: Text(
              _sawNonIsbnBarcode
                  ? 'ISBN 바코드가 아닙니다. 다른 바코드를 스캔해주세요.'
                  : '책 뒷면의 바코드를 화면 중앙에 맞춰주세요',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _sawNonIsbnBarcode
                    ? AppColors.highlightGold
                    : Colors.white,
                fontWeight: _sawNonIsbnBarcode
                    ? FontWeight.w600
                    : FontWeight.normal,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void _showQuickRegisterHelp(BuildContext context) {
  AppAlert.show(
    context,
    title: '빠른 등록',
    message:
        '스캔한 책을 별도의 확인 과정없이 바로 서재에 담아요\n'
        '다음책 바코드를 이어서 비추면 연속해서 등록 할 수 있어요',
  );
}

class _ControlBar extends StatelessWidget {
  const _ControlBar({
    required this.quickRegister,
    required this.onQuickRegisterChanged,
    required this.quickStatus,
    required this.quickStatuses,
    required this.onStatusSelected,
  });

  final bool quickRegister;
  final ValueChanged<bool?> onQuickRegisterChanged;
  final BookStatus quickStatus;
  final List<BookStatus> quickStatuses;
  final ValueChanged<BookStatus> onStatusSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () => onQuickRegisterChanged(!quickRegister),
              borderRadius: BorderRadius.circular(10),
              child: Row(
                children: [
                  Transform.scale(
                    scale: 1.3,
                    child: Checkbox(
                      value: quickRegister,
                      onChanged: onQuickRegisterChanged,
                      activeColor: AppColors.accentFill,
                      checkColor: AppColors.textStrong,
                      side: const BorderSide(color: Colors.white, width: 2),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    '빠른 등록',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: [Shadow(blurRadius: 6, color: Colors.black)],
                    ),
                  ),
                ],
              ),
            ),
            InkWell(
              onTap: () => _showQuickRegisterHelp(context),
              borderRadius: BorderRadius.circular(999),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(
                  PhosphorIconsRegular.question,
                  size: 20,
                  color: Colors.white,
                  shadows: [Shadow(blurRadius: 6, color: Colors.black)],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final status in quickStatuses) ...[
              Expanded(
                child: _StatusPill(
                  label: status.label,
                  selected: status == quickStatus,
                  enabled: quickRegister,
                  onTap: () => onStatusSelected(status),
                ),
              ),
              if (status != quickStatuses.last) const SizedBox(width: 8),
            ],
          ],
        ),
      ],
    );
  }
}

class _RegisteringIndicator extends StatelessWidget {
  const _RegisteringIndicator();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 10),
          Text(
            '등록 중...',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanFrame extends StatelessWidget {
  const _ScanFrame();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Container(
          width: 260,
          height: 160,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white, width: 2),
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 선택 표시는 enabled와 별개로 항상 보인다 — "빠른 등록"이 꺼져 있어도
    // 켰을 때 어떤 상태로 등록될지 미리 알 수 있어야 한다. 카메라 화면
    // 위에 얹는 오버레이라 배경은 반투명만 준다(불투명 패널 없음).
    final Color background;
    final Color foreground;
    if (selected) {
      background = AppColors.accentFill.withValues(alpha: enabled ? 1.0 : 0.4);
      // enabled일 땐 불투명 accentFill 위라 진한 텍스트가 잘 읽히지만, 비활성
      // 상태(반투명 0.4)는 카메라 화면이 그대로 비쳐 배경을 예측할 수 없어
      // 흰 글씨를 유지한다.
      foreground = enabled ? AppColors.textStrong : Colors.white;
    } else {
      background = Colors.white.withValues(alpha: enabled ? 0.22 : 0.1);
      foreground = enabled ? Colors.white : Colors.white38;
    }

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: foreground,
            ),
          ),
        ),
      ),
    );
  }
}
