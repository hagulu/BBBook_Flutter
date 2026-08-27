import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

import '../../../core/theme/app_theme.dart';
import '../../widgets/app_alert.dart';
import '../../widgets/app_confirm.dart';

/// 이미지 에디터가 노출하는 기능 범위.
enum SharedImageEditorProfile {
  /// 크롭·회전·텍스트 입력·자유 그리기(메모 사진, 독후감 본문 이미지 등
  /// 사용자가 직접 촬영·선택한 일반 이미지).
  general,

  /// 크롭·회전만(OCR 촬영 이미지 — 인식 대상 문장을 텍스트/그리기로 가릴
  /// 이유가 없다).
  cropRotateOnly,
}

/// OCR 프로필에서 크롭 홈 화면을 떠나면서 예약해 두는 다음 동작.
/// [_SharedImageEditorScreenState] 참고.
enum _CropExitAction { closeWhole, finishWhole }

/// 공용 이미지 에디터를 열고 편집 결과를 앱 임시 디렉터리의 JPEG 파일로
/// 저장한 뒤 그 경로를 반환한다. 취소(변경 없이 닫기)하면 null.
Future<String?> openSharedImageEditor(
  BuildContext context, {
  required String imagePath,
  required SharedImageEditorProfile profile,
}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) =>
          _SharedImageEditorScreen(imagePath: imagePath, profile: profile),
    ),
  );
}

class _SharedImageEditorScreen extends StatefulWidget {
  const _SharedImageEditorScreen({
    required this.imagePath,
    required this.profile,
  });

  final String imagePath;
  final SharedImageEditorProfile profile;

  @override
  State<_SharedImageEditorScreen> createState() =>
      _SharedImageEditorScreenState();
}

class _SharedImageEditorScreenState extends State<_SharedImageEditorScreen> {
  // Done을 누르면 pro_image_editor가 onImageEditingComplete에 이어
  // onCloseEditor도 함께 호출한다 — 두 콜백이 모두 pop을 시도하면 화면이
  // 한 단계 더 닫히는 사고로 이어지므로, 이 화면이 이미 pop됐는지 여기서
  // 직접 지킨다.
  bool _hasPopped = false;

  final _editorKey = GlobalKey<ProImageEditorState>();

  /// OCR 프로필에서 크롭 홈 화면을 나가며(완료/닫기) 예약해 둔 다음 동작.
  /// 실제 실행은 크롭 서브 화면이 완전히 닫힌 뒤
  /// [MainEditorCallbacks.onEndCloseSubEditor]에서 한다 — 자세한 이유는
  /// [_cancelFromOcrCrop] 참고. 오직 [_finishFromOcrCrop]/[_cancelFromOcrCrop]
  /// (둘 다 OCR 전용 [_OcrCropAppBar]에서만 호출됨)만 이 값을 채운다 —
  /// 일반 프로필의 텍스트·그리기 편집기 종료에서도 같은
  /// onEndCloseSubEditor가 불리므로, 다른 곳에서 이 필드를 쓰게 되면 관련
  /// 없는 서브 에디터 종료 뒤에 [closeEditor]/[doneEditing]이 잘못
  /// 실행된다.
  _CropExitAction? _pendingCropExit;

  bool get _isCropOnly =>
      widget.profile == SharedImageEditorProfile.cropRotateOnly;

  @override
  void initState() {
    super.initState();
    if (_isCropOnly) {
      // OCR 프로필은 크롭이 유일한 기능이라, "자르기" 버튼 하나뿐인 중간
      // 메인 화면을 거치지 않고 곧장 크롭 화면으로 들어간다. 그 화면의
      // 완료/닫기가 곧 이 편집 전체의 완료/취소가 된다(아래
      // [_cropRotateEditorConfigs] 참고).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _editorKey.currentState?.openCropRotateEditor();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ProImageEditor.file(
      File(widget.imagePath),
      key: _editorKey,
      configs: ProImageEditorConfigs(
        i18n: _i18n,
        mainEditor: MainEditorConfigs(
          tools: _toolsFor(widget.profile),
          widgets: MainEditorWidgets(
            closeWarningDialog: (editor) => _confirmCloseWhole(editor.context),
            // OCR 프로필은 이 메인 화면이 정상적으로는 보이지 않는다(진입
            // 즉시 크롭 화면이 뜬다) — 유일하게 노출되는 경우가 고해상도
            // 이미지 디코딩을 기다리는 짧은 창인데, 우리 커스텀 완료
            // 버튼은 그 시점을 가리는 라이브러리 내부 플래그를 읽을 수
            // 없어 항상 활성 상태다. 그 틈에 탭하면 완료 처리와 자동 크롭
            // 진입이 동시에 진행되며 라우트가 꼬일 수 있어, OCR에서는 이
            // 커스텀 상단바 자체를 쓰지 않고(null) 디코딩 중엔 완료 버튼
            // 대신 스피너를 보여주는 라이브러리 기본 동작에 맡긴다.
            appBar: _isCropOnly
                ? null
                : (editor, stream) {
                    // 기본 MainEditorAppBar와 동일하게, 레이어를 선택
                    // 중이고 hideToolbarOnInteraction이 켜져 있으면
                    // 상단바를 숨긴다(커스텀 appBar를 넘기면 라이브러리가
                    // 이 조건을 대신 평가해 주지 않아 직접 재현해야 한다).
                    if (editor.hasSelectedLayers &&
                        editor
                            .configs
                            .layerInteraction
                            .hideToolbarOnInteraction) {
                      return null;
                    }
                    return ReactiveAppbar(
                      stream: stream,
                      builder: (context) => _MainAppBar(editor: editor),
                    );
                  },
          ),
        ),
        cropRotateEditor: _cropRotateEditorConfigs,
        paintEditor: _paintEditorConfigs,
        imageGeneration: _imageGenerationFor(widget.profile),
      ),
      callbacks: ProImageEditorCallbacks(
        onImageEditingComplete: (bytes) => _finish(context, bytes),
        onCloseEditor: (mode) => _handleCloseEditor(context, mode),
        mainEditorCallbacks: MainEditorCallbacks(
          // 서브 에디터가 완전히 닫힌(dismiss 애니메이션까지 끝난) 시점의
          // 신호. OCR 크롭 홈 화면에서 예약해 둔 동작이 있으면 그것을
          // 실행한다. OCR 프로필은 `enableGesturePop: false`로 뒤로 가기
          // 제스처 자체를 막아 두었기 때문에 예약 없이 이 콜백이 불리는
          // 경우는 정상적으로는 생기지 않는다 — 혹시 모를 경로 누락에
          // 대비한 방어적 처리로, 크롭 화면을 그대로 다시 연다.
          onEndCloseSubEditor: (editor) {
            final pending = _pendingCropExit;
            _pendingCropExit = null;
            switch (pending) {
              case _CropExitAction.closeWhole:
                _editorKey.currentState?.closeEditor();
                return;
              case _CropExitAction.finishWhole:
                _editorKey.currentState?.doneEditing();
                return;
              case null:
                // _hasPopped면 이미 편집기 전체를 닫는 중이라는 뜻이라
                // 중복 호출할 필요가 없다.
                if (_isCropOnly && !_hasPopped) {
                  _editorKey.currentState?.openCropRotateEditor();
                }
            }
          },
        ),
      ),
    );
  }

  List<SubEditorMode> _toolsFor(SharedImageEditorProfile profile) {
    switch (profile) {
      case SharedImageEditorProfile.general:
        return const [
          SubEditorMode.cropRotate,
          SubEditorMode.text,
          SubEditorMode.paint,
        ];
      case SharedImageEditorProfile.cropRotateOnly:
        return const [SubEditorMode.cropRotate];
    }
  }

  // 크롭 화면은 90도 단위 회전·플립·초기화만 제공한다(세밀한 각도 회전인
  // tilt, 비율 선택 시트는 제외). 핸들 강조색은 앱의 브랜드 그린 중 어두운
  // 편집기 배경 위에서도 잘 보이는 밝은 라임(accentFill)을 사용한다.
  //
  // OCR 프로필(cropRotateOnly)은 크롭이 유일한 기능이라 이 화면의 완료/
  // 닫기를 편집 전체의 완료/취소로 직접 연결한다(일반 프로필은 텍스트·
  // 그리기가 더 있어 크롭 화면의 완료/닫기는 그 단계만 확정/취소하고
  // 메인 화면으로 돌아가는 기본 동작을 그대로 둔다).
  CropRotateEditorConfigs get _cropRotateEditorConfigs =>
      CropRotateEditorConfigs(
        tools: const [
          CropRotateTool.rotate,
          CropRotateTool.flip,
          CropRotateTool.reset,
        ],
        style: const CropRotateEditorStyle(
          cropCornerColor: AppColors.accentFill,
        ),
        // OCR 프로필은 크롭 화면이 곧 첫 화면이라 "이전"이 없다. 시스템
        // 뒤로 가기 제스처가 이 라우트를 그냥 pop 해버리면 같은 화면이
        // 다시 열리는 것처럼 보여 혼란스러우므로, 제스처 자체를 무효화하고
        // 종료는 오직 명시적 완료/닫기 버튼(_OcrCropAppBar)으로만 하게 한다.
        enableGesturePop: !_isCropOnly,
        widgets: !_isCropOnly
            ? const CropRotateEditorWidgets()
            : CropRotateEditorWidgets(
                appBar: (state, stream) => ReactiveAppbar(
                  stream: stream,
                  builder: (context) => _OcrCropAppBar(
                    state: state,
                    onDone: () => _finishFromOcrCrop(state),
                    onClose: () => _cancelFromOcrCrop(state),
                  ),
                ),
              ),
      );

  // 그리기 도구는 선/점선/화살표/사각형/원/자유 그리기/블러만 노출하고,
  // 도형 채우기 토글은 제거한다. 기본 선 두께는 라이브러리 기본값(10)보다
  // 훨씬 얇게 낮춘다. 선택된 도구 색은 기본값(진한 파란색) 대신 앱 브랜드
  // 그린을 쓰되, 크롭 핸들에 쓴 밝은 라임(accentFill)이 아니라 조금 더 진한
  // accentGraphic을 쓴다 — 미선택 아이콘 색(연회색 0xFFEEEEEE)과 밝기 차이가
  // 있어야 선택 상태가 또렷이 구분된다(라임은 미선택 색과 밝기가 비슷해
  // 색상 차이만으로 구분해야 함).
  PaintEditorConfigs get _paintEditorConfigs => const PaintEditorConfigs(
    tools: [
      PaintMode.line,
      PaintMode.dashLine,
      PaintMode.arrow,
      PaintMode.rect,
      PaintMode.circle,
      PaintMode.freeStyle,
      PaintMode.blur,
    ],
    initialPaintMode: PaintMode.line,
    showToggleFillButton: false,
    style: PaintEditorStyle(
      initialStrokeWidth: 4,
      bottomBarActiveItemColor: AppColors.accentGraphic,
    ),
  );

  static const _i18n = I18n(
    cancel: '취소',
    undo: '실행 취소',
    redo: '다시 실행',
    done: '완료',
    remove: '삭제',
    doneLoadingMsg: '적용하는 중이에요',
    // closeEditorWarning* 문구는 mainEditor.widgets.closeWarningDialog에서
    // AppConfirm으로 대체하므로 여기서는 지정하지 않는다.
    various: I18nVarious(loadingDialogMsg: '잠시만 기다려 주세요...'),
    layerInteraction: I18nLayerInteraction(
      remove: '삭제',
      edit: '편집',
      rotateScale: '회전 및 크기 조절',
    ),
    textEditor: I18nTextEditor(
      inputHintText: '텍스트를 입력하세요',
      bottomNavigationBarText: '텍스트',
      back: '뒤로',
      done: '완료',
      textAlign: '정렬',
      fontScale: '글자 크기',
      backgroundMode: '배경 모드',
      smallScreenMoreTooltip: '더보기',
    ),
    cropRotateEditor: I18nCropRotateEditor(
      bottomNavigationBarText: '자르기',
      rotate: '회전',
      flip: '플립',
      back: '뒤로',
      done: '완료',
      cancel: '취소',
      undo: '실행 취소',
      redo: '다시 실행',
      reset: '초기화',
      smallScreenMoreTooltip: '더보기',
    ),
    paintEditor: I18nPaintEditor(
      bottomNavigationBarText: '그리기',
      moveAndZoom: '이동 및 확대',
      freestyle: '자유 그리기',
      arrow: '화살표',
      line: '선',
      rectangle: '사각형',
      circle: '원',
      dashLine: '점선',
      blur: '블러',
      lineWidth: '선 두께',
      changeOpacity: '투명도 조절',
      opacity: '투명도',
      color: '색상',
      strokeWidth: '선 두께',
      undo: '실행 취소',
      redo: '다시 실행',
      done: '완료',
      back: '뒤로',
      cancel: '취소',
      smallScreenMoreTooltip: '더보기',
    ),
  );

  ImageGenerationConfigs _imageGenerationFor(SharedImageEditorProfile profile) {
    switch (profile) {
      case SharedImageEditorProfile.general:
        return const ImageGenerationConfigs(
          outputFormat: OutputFormat.jpg,
          jpegQuality: 85,
          // 편집 없이 바로 완료를 눌러도 결과가 반환되도록 명시한다. false면
          // pro_image_editor가 완료 버튼을 취소와 동일하게 처리해 아무
          // 결과도 돌려주지 않는다.
          allowEmptyEditingCompletion: true,
        );
      case SharedImageEditorProfile.cropRotateOnly:
        // OCR은 인식률을 위해 원본 해상도를 최대한 보존한다 — 일반
        // 프로필의 기본 상한(2000×2000)을 그대로 쓰면 고해상도 촬영본·
        // 갤러리 이미지가 작은 글자를 읽기 어려운 크기로 줄어든다.
        return const ImageGenerationConfigs(
          outputFormat: OutputFormat.jpg,
          jpegQuality: 90,
          maxOutputSize: Size(6000, 6000),
          allowEmptyEditingCompletion: true,
        );
    }
  }

  /// 결과 바이트가 비어 있거나(캡처 실패) 임시 파일 쓰기가 실패하면
  /// 사용자가 취소한 것처럼 조용히 넘기지 않고 실패를 알린다. "Done"을
  /// 누르면 pro_image_editor가 이 콜백 다음에 [onCloseEditor]도 호출해
  /// 화면을 닫으므로, 여기서는 pop하지 않고 알림만 보여준 뒤 그 close가
  /// 자연스럽게 화면을 정리하게 둔다.
  Future<void> _finish(BuildContext context, Uint8List bytes) async {
    if (_hasPopped) return;
    if (bytes.isEmpty) {
      if (context.mounted) {
        await AppAlert.show(
          context,
          title: '이미지를 만들지 못했습니다',
          message: '다시 시도해 주세요.',
        );
      }
      return;
    }
    String? savedPath;
    try {
      final temporaryDirectory = await getTemporaryDirectory();
      final candidatePath = path.join(
        temporaryDirectory.path,
        'edited_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await File(candidatePath).writeAsBytes(bytes, flush: true);
      savedPath = candidatePath;
    } catch (_) {
      savedPath = null;
    }
    if (savedPath == null) {
      if (context.mounted) {
        await AppAlert.show(
          context,
          title: '이미지를 저장하지 못했습니다',
          message: '잠시 후 다시 시도해 주세요.',
        );
      }
      return;
    }
    _hasPopped = true;
    if (context.mounted) Navigator.of(context).pop(savedPath);
  }

  /// 그리기 하위 편집 화면(텍스트는 자체 pop을 쓰고, 크롭은 일반 프로필만
  /// 기본 동작을 쓴다 — OCR 프로필은 아래 [_cancelFromOcrCrop] 참고)의 자체
  /// 뒤로가기 버튼은 pro_image_editor 내부에서 이 [onCloseEditor] 하나로
  /// 위임된다 — 이때 [mode]는 [EditorMode.main]이 아니며, 라이브러리가 직접
  /// pop하지 않고 전부 이 콜백에 맡긴다. mode를 구분하지 않고 항상 화면
  /// 전체를 닫으면, 하위 화면에서 뒤로가기를 눌렀을 때 메인 에디터로 못
  /// 돌아가고 편집기 전체가 닫혀버린다.
  ///
  /// 하위 편집기는 메인 에디터와 같은(중첩 Navigator를 쓰지 않는 기본 설정)
  /// 라우트 스택에 얹히므로, 하위 화면일 때는 최상단 라우트만 pop해 메인
  /// 에디터(일반 프로필은 자르기·텍스트·그리기가 동등하게 보이는 화면)로
  /// 복귀시킨다.
  void _handleCloseEditor(BuildContext context, EditorMode mode) {
    if (mode != EditorMode.main) {
      if (context.mounted) Navigator.of(context).pop();
      return;
    }
    _cancel(context);
  }

  void _cancel(BuildContext context) {
    if (_hasPopped) return;
    _hasPopped = true;
    if (context.mounted) Navigator.of(context).pop();
  }

  /// OCR 크롭 홈 화면의 완료(✓) — 대기 중인 회전·플립을 먼저 커밋한 뒤(크롭
  /// 서브 화면을 pop해 메인 에디터로 복귀) 편집기 전체를 완료 처리한다.
  /// 실제 [ProImageEditorState.doneEditing] 호출은 크롭 서브 화면이 완전히
  /// 닫힌 뒤 [MainEditorCallbacks.onEndCloseSubEditor]에서 수행한다 — 이유는
  /// [_cancelFromOcrCrop] 참고. [state.done]이 pop을 마치기 전까지도 버튼이
  /// 계속 탭 가능해 연속 입력에 취약하므로 처리 중에는 재입력을 막는다.
  ///
  /// [CropRotateEditorState.done]은 크롭 영역을 드래그하는 등 제스처가
  /// 진행 중이면(라이브러리 내부 `_interactionActive`, 외부에서 확인 불가)
  /// 아무 것도 하지 않고 즉시 반환한다 — pop도, 그에 따른
  /// onEndCloseSubEditor도 오지 않아 위에서 세운 예약이 영영 소비되지
  /// 않고 완료·닫기 버튼을 모두 잠가버린다. 정상 경로라면 크롭 서브
  /// 화면은 pop 직후 시작되는 전환 애니메이션(기본 300ms) 안에
  /// dispose되므로, 그보다 넉넉한 시간이 지나도 여전히 살아있으면 실패로
  /// 보고 예약을 풀어 재시도할 수 있게 한다.
  Future<void> _finishFromOcrCrop(CropRotateEditorState state) async {
    if (_pendingCropExit != null) return;
    _pendingCropExit = _CropExitAction.finishWhole;
    await state.done();
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted && state.mounted && _pendingCropExit == _CropExitAction.finishWhole) {
      _pendingCropExit = null;
    }
  }

  /// OCR 크롭 홈 화면의 닫기(X) — 대기 중인 크롭 변경은 버리고 편집기
  /// 전체를 취소한다. [ProImageEditorState.closeEditor] 호출은 크롭 서브
  /// 화면이 실제로 완전히 닫힌 뒤([_pendingCropExit]을 통해
  /// [MainEditorCallbacks.onEndCloseSubEditor]가 실행) 이뤄진다 — pop 직후
  /// 바로 부르면 메인 에디터의 이력 유무 확인이 아직 dismiss 애니메이션이
  /// 끝나지 않은 라우트 상태와 뒤섞일 수 있다. 이력이 있어 확인 다이얼로그가
  /// 뜨고 사용자가 취소하면 [_confirmCloseWhole]이 크롭 화면을 다시 연다.
  void _cancelFromOcrCrop(CropRotateEditorState state) {
    if (_pendingCropExit != null) return;
    _pendingCropExit = _CropExitAction.closeWhole;
    Navigator.of(state.context).pop();
  }

  /// 편집기 전체를 닫기 전 확인 팝업(공용 [AppConfirm]). OCR 프로필에서
  /// 사용자가 취소를 선택하면 이미 pop된 크롭 홈 화면을 다시 열어 "크롭
  /// 화면 외에 다른 화면 없음" 불변식이 취소 경로에서도 깨지지 않게 한다.
  Future<bool> _confirmCloseWhole(BuildContext context) async {
    final confirmed = await AppConfirm.show(
      context,
      title: '편집기를 닫을까요?',
      message: '변경 사항이 저장되지 않습니다.',
      confirmText: '닫기',
      cancelText: '취소',
    );
    if (!confirmed && _isCropOnly) {
      // 확인 다이얼로그 라우트가 아직 닫히는 중일 수 있어 한 프레임
      // 미룬다(다음 라우트를 push하는 것 자체는 안전하지만, 굳이 겹쳐
      // 그릴 이유가 없다).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _editorKey.currentState?.openCropRotateEditor();
      });
    }
    return confirmed;
  }
}

/// 메인 에디터 상단바. 기본 [MainEditorAppBar]는 라이브러리 내부 위젯이라
/// 재사용할 수 없어(공개 API가 아님) 같은 아이콘·색상 토큰으로 직접 그린다.
/// 완료 버튼만 체크 아이콘 대신 "완료" 텍스트로 바꾼 점이 기본 구현과 다르다
/// — 이 버튼이 실제로 편집 결과를 이미지로 적용해 반환하는 동작이라,
/// 사진을 고르는 체크 표시와 헷갈리지 않도록 명시적인 문구를 쓴다(하위
/// 크롭 화면 자체의 완료 체크는 크롭 한 단계만 확정하는 동작이라 그대로
/// 둔다).
///
/// 기본 구현은 이미지 디코딩이 끝나기 전([ProImageEditorState]의
/// 비공개 `_isInitialized`)에는 완료 버튼 자리에 로딩 스피너를 보여준다.
/// 그 플래그를 밖에서 읽을 방법이 없어 여기서는 재현하지 않았다 — 로컬
/// 파일이라 그 창이 매우 짧고, 그 사이 눌려도 [_finish]가 빈 바이트를
/// 실패로 처리해 안내를 띄우므로 크래시로 이어지지는 않는다.
class _MainAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _MainAppBar({required this.editor});

  final ProImageEditorState editor;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final mainEditorConfigs = editor.configs.mainEditor;
    final style = mainEditorConfigs.style;
    final icons = mainEditorConfigs.icons;
    final i18n = editor.i18n;
    final foregroundColor = style.appBarColor;
    return AppBar(
      foregroundColor: foregroundColor,
      backgroundColor: style.appBarBackground,
      leading: mainEditorConfigs.enableCloseButton
          ? IconButton(
              tooltip: i18n.cancel,
              icon: Icon(icons.closeEditor),
              onPressed: editor.closeEditor,
            )
          : null,
      actions: [
        IconButton(
          tooltip: i18n.undo,
          icon: Icon(
            icons.undoAction,
            color: editor.stateManager.canUndo
                ? foregroundColor
                : foregroundColor.withAlpha(80),
          ),
          onPressed: editor.undoAction,
        ),
        IconButton(
          tooltip: i18n.redo,
          icon: Icon(
            icons.redoAction,
            color: editor.stateManager.canRedo
                ? foregroundColor
                : foregroundColor.withAlpha(80),
          ),
          onPressed: editor.redoAction,
        ),
        // doneEditing()은 재진입 방지 가드(_isProcessingFinalImage)를 자체
        // 내장하고 있어 여기서 별도로 막지 않아도 된다.
        TextButton(
          onPressed: editor.doneEditing,
          child: Text(
            i18n.done,
            style: TextStyle(
              color: foregroundColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

/// OCR 프로필의 크롭 홈 화면 상단바. 기본 [CropEditorAppbar]는 라이브러리
/// 내부 위젯이라 재사용할 수 없어(공개 API가 아님) 같은 아이콘·색상 토큰으로
/// 직접 그린다. 완료/닫기가 크롭 한 단계가 아니라 편집기 전체를 대상으로
/// 한다는 점, 완료 버튼이 체크 아이콘 대신 "완료" 텍스트라는 점이 기본
/// 구현과 다르다(이 버튼이 실제로 편집 결과를 이미지로 적용해 반환하므로).
class _OcrCropAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _OcrCropAppBar({
    required this.state,
    required this.onDone,
    required this.onClose,
  });

  final CropRotateEditorState state;
  final VoidCallback onDone;
  final VoidCallback onClose;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final style = state.configs.cropRotateEditor.style;
    final icons = state.configs.cropRotateEditor.icons;
    final i18n = state.i18n.cropRotateEditor;
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: style.appBarBackground,
      foregroundColor: style.appBarColor,
      leading: IconButton(
        icon: Icon(icons.backButton),
        tooltip: i18n.back,
        onPressed: onClose,
      ),
      actions: [
        IconButton(
          icon: Icon(icons.undoAction),
          tooltip: i18n.undo,
          onPressed: state.canUndo ? state.undoAction : null,
        ),
        IconButton(
          icon: Icon(icons.redoAction),
          tooltip: i18n.redo,
          onPressed: state.canRedo ? state.redoAction : null,
        ),
        TextButton(
          onPressed: onDone,
          child: Text(
            i18n.done,
            style: TextStyle(
              color: style.appBarColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}
