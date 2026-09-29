import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/ai_generating_view.dart';
import '../../../../shared/widgets/app_bar_title.dart';
import '../../../../shared/widgets/app_snackbar.dart';

const _aiMemoMinLength = 20;
const _aiMemoMaxLength = 3000;

/// AI 메모 생성 전용 긴 텍스트 입력 화면.
///
/// 생성 버튼을 누르면 [onGenerate]를 호출해 실제 API 요청·로컬 저장을
/// 맡긴다(화면은 입력 상태와 생성 중 표시만 책임진다). 생성이 실패해도
/// 입력한 텍스트와 화면은 그대로 남아 사용자가 바로 재시도할 수 있다.
/// 성공하면 `true`를 반환하며 화면을 닫는다.
class BookNoteAiMemoComposerScreen extends StatefulWidget {
  const BookNoteAiMemoComposerScreen({super.key, required this.onGenerate});

  final Future<void> Function(String text) onGenerate;

  @override
  State<BookNoteAiMemoComposerScreen> createState() =>
      _BookNoteAiMemoComposerScreenState();
}

class _BookNoteAiMemoComposerScreenState
    extends State<BookNoteAiMemoComposerScreen> {
  final _textController = _NoComposingUnderlineTextController();
  bool _isGenerating = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  bool get _canGenerate {
    final length = _textController.text.trim().characters.length;
    return !_isGenerating &&
        length >= _aiMemoMinLength &&
        length <= _aiMemoMaxLength;
  }

  Future<void> _generate() async {
    final text = _textController.text.trim();
    if (text.characters.length < _aiMemoMinLength) {
      AppSnackBar.error(context, '내용을 $_aiMemoMinLength자 이상 입력해 주세요.');
      return;
    }
    setState(() => _isGenerating = true);
    AppAiLoading.show(context, message: 'AI 메모 생성 중');
    try {
      await widget.onGenerate(text);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) AppSnackBar.error(context, error.message);
    } catch (_) {
      if (mounted) AppSnackBar.error(context, '메모를 생성하지 못했습니다.');
    } finally {
      AppAiLoading.hide();
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isGenerating,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: _isGenerating ? null : () => Navigator.of(context).pop(),
            tooltip: '닫기',
            icon: const Icon(PhosphorIconsRegular.x),
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                PhosphorIconsFill.sparkle,
                size: 18,
                color: AppColors.of(context).accentForeground,
              ),
              const SizedBox(width: 6),
              const AppBarTitle('AI로 메모 만들기'),
            ],
          ),
          backgroundColor: AppColors.of(context).pageBackground,
          foregroundColor: AppColors.of(context).textStrong,
          elevation: 0,
          actions: [
            TextButton(
              onPressed: _canGenerate ? _generate : null,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.of(context).accentForeground,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              child: Text(_isGenerating ? '생성 중' : '생성'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    autofocus: true,
                    enabled: !_isGenerating,
                    expands: true,
                    minLines: null,
                    maxLines: null,
                    maxLength: _aiMemoMaxLength,
                    textAlignVertical: TextAlignVertical.top,
                    keyboardType: TextInputType.multiline,
                    style: TextStyle(
                      color: AppColors.of(context).textBody,
                      fontSize: 15,
                      height: 1.5,
                    ),
                    decoration: InputDecoration(
                      hintText: '정리할 내용을 자유롭게 적으면 AI가 요약·발췌·생각 메모로 만들어드려요',
                      hintStyle: TextStyle(
                        color: AppColors.of(context).textMuted,
                        fontSize: 15,
                        height: 1.5,
                      ),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      counterText: '',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${_formatCount(_textController.text.characters.length)} / '
                    '${_formatCount(_aiMemoMaxLength)}',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: AppColors.of(context).textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
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

/// 천 단위 구분 쉼표를 넣는다(예: 3000 → "3,000"). 이 화면은 최대 길이가
/// 고정값이라 별도 패키지 없이 자리수만 세어 넣는 것으로 충분하다.
String _formatCount(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final remaining = digits.length - i;
    if (i > 0 && remaining % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// IME 조합 중인 구간에 시스템이 그리는 밑줄을 없앤다. 긴 글을 오래
/// 입력·붙여넣는 화면이라 그 밑줄이 계속 거슬리게 눈에 띄기 때문이다
/// (`book_reflection_editor_screen.dart`의 같은 이름 클래스와 동일한
/// 처리).
class _NoComposingUnderlineTextController extends TextEditingController {
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    return super.buildTextSpan(
      context: context,
      style: style,
      withComposing: false,
    );
  }
}
