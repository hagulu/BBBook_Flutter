import 'dart:developer' as developer;
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// 원격 이미지를 바이트로 내려받는 함수. 테스트에서 네트워크 없이 주입한다.
typedef LocalImageDownloader = Future<List<int>> Function(String url);

/// [LocalImageStore.ensureDownloaded]의 결과. 실패를 하나로 뭉뚱그리지
/// 않는 이유는 호출부의 대응이 정반대이기 때문이다 — 서버에 없는 이미지는
/// 다시 시도해도 같으므로 다음 회차의 자리를 비켜 줘야 하고, 오프라인 등
/// 일시적 실패는 곧 통째로 재시도해야 한다.
enum LocalImageDownloadStatus {
  /// 로컬에 사본이 있다(이미 있었거나 이번에 내려받았다).
  stored,

  /// 서버가 이미지를 주지 않는다(404/403 등). 재시도해도 결과가 같다.
  unavailable,

  /// 네트워크 오류·타임아웃·서버 오류 등 일시적 실패.
  failed,
}

class LocalImageDownload {
  const LocalImageDownload.stored(this.localImagePath)
    : status = LocalImageDownloadStatus.stored;
  const LocalImageDownload.unavailable()
    : status = LocalImageDownloadStatus.unavailable,
      localImagePath = null;
  const LocalImageDownload.failed()
    : status = LocalImageDownloadStatus.failed,
      localImagePath = null;

  final LocalImageDownloadStatus status;

  /// [LocalImageDownloadStatus.stored]일 때의 상대 경로.
  final String? localImagePath;
}

/// 기능별 이미지(메모 사진·독후감 본문 이미지)의 로컬 파일 저장소.
///
/// 이미지는 "로컬 우선"으로 다룬다 — 사용자가 고른 이미지는 서버 업로드 전에
/// 먼저 이 저장소로 복사하고, 서버에서 내려받은 이미지도 여기에 사본을 만들어
/// 이후에는 항상 로컬 파일을 먼저 보여준다. 서버 업로드가 끝나도 로컬 파일은
/// 지우지 않는다(오프라인 조회).
///
/// DB에는 절대 경로가 아니라 `<directoryName>/<파일명>` 상대 경로를 저장한다 —
/// iOS는 앱 업데이트/재설치마다 컨테이너 절대 경로(`.../Application/<UUID>/`)가
/// 바뀌어, 절대 경로를 저장해 두면 그 순간 모든 이미지 참조가 한꺼번에 깨진다.
/// 읽을 때마다 현재 앱 지원 디렉터리를 기준으로 다시 조립한다([resolve]/
/// [resolveSync]).
///
/// 기능마다 폴더를 나눠 인스턴스를 하나씩 둔다(`noteMemoImageStore`,
/// `reflectionImageStore`) — orphan 정리([pruneOrphans])가 "이 폴더의 파일은
/// 모두 이 기능의 DB가 참조해야 한다"를 전제로 동작하기 때문이다.
class LocalImageStore {
  LocalImageStore({
    required this.directoryName,
    required this.logLabel,
    Future<Directory> Function()? resolveRoot,
    LocalImageDownloader? downloader,
  }) : _resolveRoot = resolveRoot ?? getApplicationSupportDirectory,
       _downloader = downloader ?? _downloadBytes;

  /// 앱 지원 디렉터리 아래 이미지 보관 폴더명. 로그아웃 시 전체 삭제
  /// ([clear])도 이 폴더 단위로 이뤄진다.
  final String directoryName;

  /// 로그 접두어(`[메모 사진 ...]`처럼 어느 기능의 이미지인지 구분).
  final String logLabel;

  /// 서버가 jpg/jpeg/png/webp·5MB 이하만 허용하므로(메모 사진 업로드,
  /// 독후감 임시 이미지 업로드 모두 같은 제약), 로컬 저장 시점에 걸러내지
  /// 않으면 저장은 성공한 뒤 업로드가 영원히 400으로 실패하는 행이 남는다.
  static const allowedExtensions = {'.jpg', '.jpeg', '.png', '.webp'};
  static const maxBytes = 5 * 1024 * 1024;

  /// [pruneOrphans]가 "방금 복사됐지만 아직 DB에 기록되지 않은" 파일을
  /// 지우지 않도록 두는 유예 시간.
  static const pruneGrace = Duration(minutes: 10);

  final Future<Directory> Function() _resolveRoot;
  final LocalImageDownloader _downloader;

  String? _directoryPath;

  /// 위젯이 `build()` 안에서 곧바로 파일을 열 수 있도록([resolveSync]) 앱
  /// 시작 시 한 번 호출해 디렉터리 경로를 캐시한다. 실패해도 앱 실행을
  /// 막지 않는다 — 캐시가 없으면 화면은 서버 URL로 대체 표시한다.
  Future<void> warmUp() async {
    try {
      await ensureDirectory();
    } catch (_) {
      developer.log('[$logLabel 저장소 준비] result=FAIL reason=local_file_error');
    }
  }

  Future<Directory> ensureDirectory() async {
    final cached = _directoryPath;
    if (cached != null) {
      final directory = Directory(cached);
      if (await directory.exists()) return directory;
    }
    final root = await _resolveRoot();
    final directory = Directory(path.join(root.path, directoryName));
    if (!await directory.exists()) await directory.create(recursive: true);
    _directoryPath = directory.path;
    return directory;
  }

  /// DB에 저장된 값에서 파일명만 뽑는다. 상대 경로(`<폴더>/x.jpg`)가 정상
  /// 형태지만, 마이그레이션 이전에 남은 절대 경로나 `file://` URI도 파일명
  /// 기준으로 읽어 준다.
  String? fileNameOf(String? stored) {
    if (stored == null || stored.isEmpty) return null;
    if (isRemote(stored)) return null;
    final raw = stored.startsWith('file://')
        ? Uri.parse(stored).toFilePath()
        : stored;
    final name = path.basename(raw);
    if (name.isEmpty || name == '.' || name == '..') return null;
    return name;
  }

  Future<File?> resolve(String? stored) async {
    final name = fileNameOf(stored);
    if (name == null) return null;
    final directory = await ensureDirectory();
    return File(path.join(directory.path, name));
  }

  /// [warmUp]으로 디렉터리 경로가 캐시된 뒤에만 파일을 돌려준다. 캐시가
  /// 아직 없으면 null을 반환해 호출부가 서버 URL로 대체하게 한다.
  File? resolveSync(String? stored) {
    final directoryPath = _directoryPath;
    final name = fileNameOf(stored);
    if (directoryPath == null || name == null) return null;
    return File(path.join(directoryPath, name));
  }

  /// 사용자가 촬영/선택한 이미지를 저장소로 복사하고 DB에 넣을 상대 경로를
  /// 반환한다. 형식/용량 위반은 [FileSystemException]으로 알린다(화면이
  /// 그대로 사용자 메시지로 보여준다).
  Future<String> saveSelected(String pickedPath) async {
    final source = File(pickedPath);
    if (!await source.exists()) throw const FileSystemException();
    final extension = path.extension(pickedPath).toLowerCase();
    if (!allowedExtensions.contains(extension)) {
      throw FileSystemException('지원하지 않는 이미지 형식입니다.', pickedPath);
    }
    if (await source.length() > maxBytes) {
      throw FileSystemException('이미지 용량은 5MB 이하만 가능합니다.', pickedPath);
    }
    final directory = await ensureDirectory();
    final fileName = 'local_${DateTime.now().microsecondsSinceEpoch}$extension';
    await source.copy(path.join(directory.path, fileName));
    return relativeOf(fileName);
  }

  /// 서버 이미지를 로컬로 내려받는다. 이미 같은 이미지가 저장돼 있으면 다시
  /// 내려받지 않는다. 실패해도 화면은 서버 URL로 계속 표시되고, 결과의
  /// [LocalImageDownloadStatus]에 따라 호출부가 재시도 여부를 정한다.
  Future<LocalImageDownload> ensureDownloaded(String remoteUrl) async {
    final fileName = remoteFileNameOf(remoteUrl);
    // 경로가 없는 URL은 형태 자체가 이미지를 가리키지 못한다 — 재시도
    // 대상이 아니다.
    if (fileName == null) return const LocalImageDownload.unavailable();
    try {
      final directory = await ensureDirectory();
      final target = File(path.join(directory.path, fileName));
      if (await target.exists() && await target.length() > 0) {
        return LocalImageDownload.stored(relativeOf(fileName));
      }
      final bytes = await _downloader(remoteUrl);
      if (bytes.isEmpty) return const LocalImageDownload.failed();
      // 다운로드가 중간에 끊겨 반쪽짜리 파일이 "이미 있는 이미지"로
      // 남지 않도록 임시 파일에 다 쓴 뒤 이름을 바꾼다.
      final temporary = File('${target.path}.download');
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(target.path);
      return LocalImageDownload.stored(relativeOf(fileName));
    } catch (error) {
      final unavailable = _isUnavailable(error);
      developer.log(
        '[$logLabel 내려받기] result=FAIL '
        'reason=${unavailable ? 'unavailable' : 'download_error'}',
      );
      return unavailable
          ? const LocalImageDownload.unavailable()
          : const LocalImageDownload.failed();
    }
  }

  /// 서버가 "이 이미지는 줄 수 없다"고 답한 경우(404/403 등)만 영구 실패로
  /// 본다. 408/429와 5xx, 그리고 연결 실패·타임아웃은 곧 회복될 수 있으므로
  /// 일시적 실패로 남긴다.
  static bool _isUnavailable(Object error) {
    if (error is! DioException) return false;
    final statusCode = error.response?.statusCode;
    if (statusCode == null) return false;
    if (statusCode == 408 || statusCode == 429) return false;
    return statusCode >= 400 && statusCode < 500;
  }

  /// [except]와 같은 파일을 가리키면 지우지 않는다(교체 전후가 같은 이미지).
  Future<void> delete(String? stored, {String? except}) async {
    final name = fileNameOf(stored);
    if (name == null || name == fileNameOf(except)) return;
    try {
      final directory = await ensureDirectory();
      final file = File(path.join(directory.path, name));
      if (await file.exists()) await file.delete();
    } catch (_) {
      developer.log('[$logLabel 정리] result=FAIL reason=local_file_error');
    }
  }

  Future<Set<String>> listFileNames() async {
    try {
      final directory = await ensureDirectory();
      final names = <String>{};
      await for (final entity in directory.list()) {
        if (entity is File) names.add(path.basename(entity.path));
      }
      return names;
    } catch (_) {
      developer.log('[$logLabel 목록] result=FAIL reason=local_file_error');
      return const {};
    }
  }

  /// DB의 어떤 행도 더 이상 참조하지 않는 파일을 지운다(이미지 교체·행
  /// 삭제·서버에서 사라진 항목 정리 등으로 남은 파일). 반환값은 지운 개수.
  Future<int> pruneOrphans(Iterable<String> referenced) async {
    var removed = 0;
    try {
      final keep = referenced.map(fileNameOf).whereType<String>().toSet();
      final directory = await ensureDirectory();
      final now = DateTime.now();
      await for (final entity in directory.list()) {
        if (entity is! File) continue;
        if (keep.contains(path.basename(entity.path))) continue;
        final modified = await entity.lastModified();
        if (now.difference(modified) < pruneGrace) continue;
        await entity.delete();
        removed++;
      }
    } catch (_) {
      developer.log('[$logLabel 정리] result=FAIL reason=local_file_error');
    }
    return removed;
  }

  /// 로그아웃 등으로 계정 데이터를 비울 때 이미지 폴더를 통째로 지운다.
  Future<void> clear() async {
    try {
      final directory = Directory(
        _directoryPath ?? path.join((await _resolveRoot()).path, directoryName),
      );
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (_) {
      developer.log('[$logLabel 전체 정리] result=FAIL reason=local_file_error');
    } finally {
      _directoryPath = null;
    }
  }

  String relativeOf(String fileName) => path.join(directoryName, fileName);

  /// 원격 URL의 경로(path)만으로 파일명을 만든다 — 쿼리 문자열(서명/만료
  /// 등)이 붙거나 호스트가 바뀌어도 같은 이미지면 같은 파일명이 되어
  /// 중복 다운로드를 피한다. 아직 DB 행과 연결되지 않은 사본을 orphan
  /// 정리가 지켜야 할 때도([pruneOrphans]) 이 이름으로 판단한다.
  String? remoteFileNameOf(String remoteUrl) {
    final segments =
        Uri.tryParse(remoteUrl)?.pathSegments
            .where((segment) => segment.isNotEmpty)
            .toList(growable: false) ??
        const <String>[];
    if (segments.isEmpty) return null;
    final joined = segments
        .join('_')
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final trimmed = joined.length <= 120
        ? joined
        : joined.substring(joined.length - 120);
    return 'remote_$trimmed';
  }

  static bool isRemote(String value) =>
      value.startsWith('http://') || value.startsWith('https://');

  /// 인증이 필요 없는 공개 이미지 URL이므로 [ApiClient]의 Dio를 쓰지 않는다
  /// (외부 호스트로 액세스 토큰이 함께 나가지 않게 한다 — 화면의
  /// `Image.network`도 헤더 없이 같은 URL을 읽는다).
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  static Future<List<int>> _downloadBytes(String url) async {
    final response = await _dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    return response.data ?? const [];
  }
}

/// 여러 이미지를 한 번에 확보했을 때의 결과 요약.
///
/// 실패를 [unavailable](서버에 더 이상 없는 이미지)과 [failed](오프라인 등
/// 일시적 실패)로 나누는 이유는 호출부의 판단이 다르기 때문이다 — 로컬
/// 저장 모드 전환은 [failed]가 하나라도 있으면 중단해야 하지만,
/// [unavailable]은 서버에 남겨 둬도 되찾을 수 없으므로 안내만 하고 진행한다.
class LocalImageSyncReport {
  const LocalImageSyncReport({
    this.stored = 0,
    this.unavailable = 0,
    this.failed = 0,
  });

  /// 이번에 로컬로 확보한 이미지 수.
  final int stored;

  /// 서버가 더 이상 주지 않아 확보하지 못한 이미지 수(404/403 등).
  final int unavailable;

  /// 일시적 실패로 확보하지 못한 이미지 수. 재시도하면 받을 수 있다.
  final int failed;

  int get total => stored + unavailable + failed;

  LocalImageSyncReport operator +(LocalImageSyncReport other) {
    return LocalImageSyncReport(
      stored: stored + other.stored,
      unavailable: unavailable + other.unavailable,
      failed: failed + other.failed,
    );
  }
}
