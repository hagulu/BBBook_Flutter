import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:archive/archive.dart' hide ArchiveException;
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/storage/local_image_store.dart';
import '../../book_note/services/note_memo_image_store.dart';
import '../../book_reflection/services/book_reflection_content_adapter.dart';
import '../../book_reflection/services/reflection_image_store.dart';
import '../../bookshelf/data/bookshelf_database.dart';
import '../../bookshelf/data/finished_cover_cache_manager.dart';
import '../../bookshelf/services/book_cover_image_store.dart';
import '../data/record_archive_dao.dart';
import '../models/record_archive.dart';
import 'archive_html.dart';

class ArchiveExportResult {
  const ArchiveExportResult(this.file, this.missingImages);
  final File file;
  final int missingImages;
}

class RecordArchiveService {
  RecordArchiveService({
    RecordArchiveDao? dao,
    Map<String, LocalImageStore>? stores,
    Future<Directory> Function()? temporaryDirectory,
    Future<File?> Function(String kind, String url)? cachedImage,
  }) : _dao = dao ?? RecordArchiveDao(),
       _stores =
           stores ??
           {
             'cover': bookCoverImageStore,
             'memo': noteMemoImageStore,
             'reflection': reflectionImageStore,
           },
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
       _cachedImage = cachedImage ?? _findCachedImage;
  final Future<File?> Function(String kind, String url) _cachedImage;
  final RecordArchiveDao _dao;
  final Map<String, LocalImageStore> _stores;
  final Future<Directory> Function() _temporaryDirectory;
  static const maxZipBytes = 512 * 1024 * 1024;
  static const maxExpandedBytes = 1024 * 1024 * 1024;
  static const _adapter = BookReflectionContentAdapter();

  Future<ArchiveExportResult> exportRecords(int ownerUserId) async {
    final generation = BookshelfDatabase.sessionGeneration;
    final snapshot = await _dao.snapshot(ownerUserId);
    final records = snapshot.records;
    final zip = Archive();
    var missing = 0;
    final resolved = <String, String?>{};
    Future<String?> addImage(String key, ArchiveImageSource source) async {
      final store = _stores[source.kind]!;
      final cacheKey = '${source.kind}:${source.local ?? source.remote}';
      if (resolved.containsKey(cacheKey)) return resolved[cacheKey];
      try {
        var file = await store.resolve(source.local);
        if (file == null || !await file.exists() || await file.length() == 0) {
          final remote = source.remote;
          if (remote != null && LocalImageStore.isRemote(remote)) {
            file = await _cachedImage(source.kind, remote);
            if (file == null ||
                !await file.exists() ||
                await file.length() == 0) {
              final result = await store.ensureDownloaded(remote);
              file = await store.resolve(result.localImagePath);
            }
          }
        }
        if (file != null &&
            await file.exists() &&
            await file.length() > 0 &&
            await file.length() <= 32 * 1024 * 1024) {
          final bytes = await file.readAsBytes();
          final extension = _imageExtension(bytes);
          if (extension != null) {
            final name = 'images/$key$extension';
            zip.addFile(ArchiveFile(name, bytes.length, bytes));
            resolved[cacheKey] = name;
            return name;
          }
        }
      } catch (_) {
        developer.log('[내 기록 이미지 확보] result=FAIL reason=image_unavailable');
      }
      missing++;
      resolved[cacheKey] = null;
      return null;
    }

    for (final book in records.books) {
      final key = book['coverImage'] as String?;
      book.values['coverImage'] = key == null
          ? null
          : await addImage(key, snapshot.images[key]!);
    }
    for (final memo in records.memos) {
      final key = memo['image'] as String?;
      memo.values['image'] = key == null
          ? null
          : await addImage(key, snapshot.images[key]!);
    }
    for (final reflection in records.reflections) {
      final content = reflection['content'] as Map<String, dynamic>?;
      if (content == null) continue;
      final replacements = <String, String>{};
      final missingSources = <String>{};
      var index = 0;
      for (final source in _adapter.imageSources(content).toSet()) {
        final image =
            snapshot.images['reflection_${reflection.id}_$source'] ??
            ArchiveImageSource('reflection', source, source);
        final name = await addImage(
          'reflection_${reflection.id}_${index++}',
          image,
        );
        if (name == null) {
          missingSources.add(source);
        } else {
          replacements[source] = name;
        }
      }
      reflection.values['content'] = _removeMissingImages(
        _adapter.replaceImageSources(content, replacements),
        missingSources,
      );
    }
    void addText(String name, String text) {
      final bytes = utf8.encode(text);
      if (name == 'bookkureomi.json' && bytes.length > 32 * 1024 * 1024) {
        throw const ArchiveException('기록 정보 파일이 너무 커서 내보낼 수 없습니다.');
      }
      zip.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    addText('bookkureomi.json', jsonEncode(records.toJson()));
    final headers = [
      ...archiveBookFields.keys.where((k) => k != 'tags'),
      'tags',
    ];
    addText(
      'books.csv',
      archiveCsv([
        headers,
        for (final book in records.books)
          [
            for (final key in headers)
              key == 'tags' ? (book['tags'] as List).join('|') : book[key],
          ],
      ]),
    );
    final bookFolders = ArchiveNames();
    final folders = {
      for (final book in records.books)
        book.id: bookFolders.take(book['title'] as String?),
    };
    final noteNames = <String, ArchiveNames>{};
    for (final note in records.notes) {
      final book = records.books.firstWhere((b) => b.id == note['bookId']);
      final name = (noteNames[book.id] ??= ArchiveNames()).take(
        note['title'] as String?,
        extension: '.html',
      );
      final memos = records.memos.where((m) => m['noteId'] == note.id).toList()
        ..sort(
          (a, b) => (a['sortOrder'] as int).compareTo(b['sortOrder'] as int),
        );
      final body = StringBuffer(
        '<h1>${htmlEscape(note['title'] ?? '제목 없음')}</h1><p>${htmlEscape(book['title'])}</p><small>${htmlEscape(note['createdAt'])}</small>',
      );
      for (final memo in memos) {
        final type =
            const {
              'SUMMARY': '책 내용',
              'QUOTE': '발췌',
              'THOUGHT': '내 생각',
              'PHOTO': '사진',
            }[memo['type']] ??
            memo['type'];
        final start = memo['startPage'];
        final end = memo['endPage'];
        final page = start == null
            ? (end == null ? '' : '$end쪽')
            : end == null || start == end
            ? '$start쪽'
            : '$start~$end쪽';
        body.write(
          '<section><small>${htmlEscape(type)} · $page${memo['isImportant'] == true ? ' · 중요 메모' : ''}</small><p>${memoHtml(memo['content'] as String?)}</p>',
        );
        if (memo['image'] != null) {
          body.write(
            '<img src="../../${htmlEscape(memo['image'])}" alt="메모 사진">',
          );
        }
        body.write('</section>');
      }
      addText(
        'notes/${folders[book.id]}/$name',
        archiveHtml(note['title'] as String? ?? '제목 없음', body.toString()),
      );
    }
    final reflectionNames = ArchiveNames();
    for (final reflection in records.reflections) {
      final book = records.books.firstWhere(
        (b) => b.id == reflection['bookId'],
      );
      final title = reflection['title'] as String? ?? '독후감';
      final name = reflectionNames.take(
        '${book['title']} - $title',
        extension: '.html',
      );
      addText(
        'reflections/$name',
        archiveHtml(
          title,
          '<h1>${htmlEscape(title)}</h1><p>${htmlEscape(book['title'])} · ${htmlEscape(book['author'])}</p><small>${htmlEscape(reflection['createdAt'])}</small>${reflectionHtml(reflection['content'] as Map<String, dynamic>?, reflection['contentText'] as String?)}',
        ),
      );
    }
    if (generation != BookshelfDatabase.sessionGeneration) {
      throw const ArchiveException('계정 상태가 변경되어 내보내기를 중단했습니다.');
    }
    if (zip.length > 50000 ||
        zip.files.fold<int>(0, (total, file) => total + file.size) >
            maxExpandedBytes) {
      throw const ArchiveException('기록의 크기가 너무 커서 내보낼 수 없습니다.');
    }
    final directory = await (await _temporaryDirectory()).createTemp(
      'bookkureomi_export_',
    );
    try {
      final date = DateTime.now().toIso8601String().substring(0, 10);
      final file = File(path.join(directory.path, '북꾸러미_내보내기_$date.zip'));
      final encoded = await compute(_encodeZip, zip);
      if (encoded.length > maxZipBytes) {
        throw const ArchiveException('내보내기 ZIP은 512MB까지 지원합니다.');
      }
      await file.writeAsBytes(encoded, flush: true);
      if (generation != BookshelfDatabase.sessionGeneration) {
        throw const ArchiveException('계정 상태가 변경되어 내보내기를 중단했습니다.');
      }
      developer.log('[내 기록 내보내기] result=SUCCESS missingImages=$missing');
      return ArchiveExportResult(file, missing);
    } catch (_) {
      await directory.delete(recursive: true);
      rethrow;
    } finally {
      await zip.clear();
    }
  }

  /// 사용자 파일을 디스크에 풀지 않는다. 허용한 JSON/이미지만 메모리에서 읽는다.
  Future<void> importRecords(Uint8List bytes, int ownerUserId) async {
    final generation = BookshelfDatabase.sessionGeneration;
    if (bytes.length > maxZipBytes) {
      throw const ArchiveException('가져올 파일이 너무 큽니다. ZIP 파일은 512MB까지 지원합니다.');
    }
    final zip = await compute(_decodeZip, bytes);
    final created = <(LocalImageStore, String)>[];
    try {
      final names = <String>{};
      var expanded = 0;
      for (final file in zip.files) {
        expanded += file.size;
        if (expanded > maxExpandedBytes || zip.length > 50000) {
          throw const ArchiveException('압축을 푼 기록의 크기가 너무 큽니다.');
        }
        if (!names.add(file.name) ||
            file.isSymbolicLink ||
            file.name.startsWith('/') ||
            file.name.contains('\\') ||
            file.name.split('/').contains('..')) {
          throw const ArchiveException('안전하게 읽을 수 없는 ZIP 파일입니다.');
        }
      }
      final manifest = zip.findFile('bookkureomi.json');
      if (manifest == null || !manifest.isFile) {
        throw const ArchiveException(
          '북꾸러미 전체 기록 파일이 아닙니다. bookkureomi.json이 포함된 내보내기 ZIP을 선택해 주세요.',
        );
      }
      if (manifest.size > 32 * 1024 * 1024) {
        throw const ArchiveException('기록 정보 파일이 너무 큽니다.');
      }
      final records = RecordArchive.parse(
        utf8.decode(_verifiedContent(manifest)),
      );
      final kinds = <String, String>{};
      void image(String? source, String kind) {
        if (source == null) return;
        if (kinds.containsKey(source) && kinds[source] != kind) {
          throw const ArchiveException('이미지 연결 정보가 올바르지 않습니다.');
        }
        kinds[source] = kind;
      }

      for (final book in records.books) {
        image(book['coverImage'] as String?, 'cover');
      }
      for (final memo in records.memos) {
        image(memo['image'] as String?, 'memo');
      }
      for (final reflection in records.reflections) {
        for (final source in _adapter.imageSources(
          reflection['content'] as Map<String, dynamic>?,
        )) {
          image(source, 'reflection');
        }
      }
      // 전체 이미지 존재/형식을 먼저 확인한 후 쓰기를 시작한다.
      for (final entry in kinds.entries) {
        final file = zip.findFile(entry.key);
        if (file == null ||
            !file.isFile ||
            file.size == 0 ||
            file.size > 32 * 1024 * 1024 ||
            _imageExtension(_verifiedContent(file)) == null) {
          throw const ArchiveException('기록에 연결된 이미지가 없거나 손상되었습니다.');
        }
      }
      final localPaths = <String, String>{};
      for (final entry in kinds.entries) {
        final store = _stores[entry.value]!;
        final directory = await store.ensureDirectory();
        final bytes = zip.findFile(entry.key)!.content;
        final name = 'archive_${const Uuid().v4()}${_imageExtension(bytes)}';
        final relative = store.relativeOf(name);
        created.add((store, relative));
        await File(
          path.join(directory.path, name),
        ).writeAsBytes(bytes, flush: true);
        localPaths[entry.key] = relative;
      }
      for (final reflection in records.reflections) {
        final content = reflection['content'] as Map<String, dynamic>?;
        if (content != null) {
          reflection.values['content'] = _adapter.replaceImageSources(
            content,
            localPaths,
          );
        }
      }
      final usedImages = await _dao.restore(
        records,
        ownerUserId,
        localPaths,
        sessionValid: () => generation == BookshelfDatabase.sessionGeneration,
      );
      for (final entry in created) {
        if (!usedImages.contains(entry.$2)) await entry.$1.delete(entry.$2);
      }
      created.clear();
      developer.log('[내 기록 가져오기] result=SUCCESS');
    } catch (_) {
      for (final entry in created) {
        await entry.$1.delete(entry.$2);
      }
      rethrow;
    } finally {
      await zip.clear();
    }
  }

  String? _imageExtension(List<int> bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return '.jpg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 137 &&
        bytes[1] == 80 &&
        bytes[2] == 78 &&
        bytes[3] == 71 &&
        bytes[4] == 13 &&
        bytes[5] == 10 &&
        bytes[6] == 26 &&
        bytes[7] == 10) {
      return '.png';
    }
    if (bytes.length >= 12 &&
        ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
        ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP') {
      return '.webp';
    }
    return null;
  }

  Map<String, dynamic> _removeMissingImages(
    Map<String, dynamic> content,
    Set<String> missing,
  ) {
    if (missing.isEmpty) {
      return content;
    }
    dynamic clean(dynamic value) {
      if (value is List) {
        return value
            .where((e) {
              if (e is! Map) return true;
              if (e['insert'] case final Map insert) {
                if (missing.contains(insert['image'])) return false;
              }
              if (e['type'] == 'image' &&
                  e['attrs'] is Map &&
                  missing.contains(e['attrs']['src'])) {
                return false;
              }
              return true;
            })
            .map(clean)
            .toList();
      }
      if (value is Map) {
        return value.map((k, v) => MapEntry(k as String, clean(v)));
      }
      return value;
    }

    return Map<String, dynamic>.from(clean(content) as Map);
  }
}

// 압축 CPU 작업만 일회성 isolate로 옮겨 공통 진행 UI가 계속 갱신되게 한다.
List<int> _encodeZip(Archive archive) => ZipEncoder().encode(archive);

Archive _decodeZip(Uint8List bytes) {
  // Decoder는 중복 이름을 합치고 symlink 내용을 미리 읽으므로 원본 헤더를 먼저 검사한다.
  final directory = ZipDirectory()..read(InputMemoryStream(bytes));
  final names = <String>{};
  var expanded = 0;
  for (final header in directory.fileHeaders) {
    expanded += header.uncompressedSize;
    final name = header.filename;
    if (directory.fileHeaders.length > 50000 ||
        expanded > RecordArchiveService.maxExpandedBytes) {
      throw const ArchiveException('압축을 푼 기록의 크기가 너무 큽니다.');
    }
    if (!names.add(name) ||
        (header.externalFileAttributes >> 16) & 0xf000 == 0xa000 ||
        name.startsWith('/') ||
        name.contains('\\') ||
        name.split('/').contains('..') ||
        RegExp(r'^[A-Za-z]:').hasMatch(name)) {
      throw const ArchiveException('안전하게 읽을 수 없는 ZIP 파일입니다.');
    }
  }
  return ZipDecoder().decodeBytes(bytes);
}

Uint8List _verifiedContent(ArchiveFile file) {
  final bytes = file.content;
  if (bytes.length != file.size || getCrc32(bytes) != file.crc32) {
    throw const ArchiveException('내보내기 파일의 내용이 손상되었습니다.');
  }
  return bytes;
}

Future<File?> _findCachedImage(String kind, String url) async {
  try {
    if (kind == 'cover') {
      final cached = await FinishedCoverCacheManager.instance.getFileFromCache(
        url,
      );
      if (cached != null && await cached.file.exists()) return cached.file;
    }
    return (await DefaultCacheManager().getFileFromCache(url))?.file;
  } catch (_) {
    // 캐시 DB를 열 수 없어도 기존 LocalImageStore의 다운로드 경로를 계속 사용한다.
    return null;
  }
}
