import 'dart:io';
import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class ResourceManager {
  final Box cacheBox;
  Directory? _baseDir;

  // In-memory cache of verified local file paths to avoid repeated disk stat syscalls
  final Set<String> _verifiedLocalPaths = <String>{};

  // Coalesce simultaneous download requests for the same URL
  final Map<String, Future<String?>> _inFlightDownloads =
      <String, Future<String?>>{};

  ResourceManager(this.cacheBox);

  /// Remote uploads are prefetched with story media. Built-in identities are
  /// bundled in the app and never enter the network/cache download path.
  void cacheCharacterModels(String character, String? timelineJson) {
    final models = <String>{character};
    if (timelineJson != null && timelineJson.isNotEmpty) {
      try {
        final timeline = jsonDecode(timelineJson);
        if (timeline is Map && timeline['blocks'] is List) {
          for (final block in timeline['blocks']) {
            if (block is Map && block['characterId'] is String) {
              models.add(block['characterId'] as String);
            }
          }
        }
      } catch (_) {
        // Malformed optional timeline data must not prevent the story syncing.
      }
    }
    for (final model in models) {
      final uri = Uri.tryParse(model.trim());
      if (uri?.scheme == 'https' || uri?.scheme == 'http') {
        downloadAndCacheInBackground(model, folder: 'models');
      }
    }
  }

  Future<void> init() async {
    if (_baseDir == null) {
      final appDir = await getApplicationDocumentsDirectory();
      _baseDir = Directory('${appDir.path}/offline_resources');
      if (!await _baseDir!.exists()) {
        await _baseDir!.create(recursive: true);
      }
    }
  }

  String _generateFileName(String url, String folder) {
    final cleanHash = url.hashCode.abs().toString();
    final uri = Uri.tryParse(url);
    String ext = '';
    if (uri != null && uri.pathSegments.isNotEmpty) {
      final last = uri.pathSegments.last;
      if (last.contains('.')) {
        ext = '.${last.split('.').last.split('?').first}';
      }
    }
    if (ext.isEmpty) {
      if (folder == 'audio') ext = '.mp3';
      if (folder == 'images') ext = '.png';
    }
    return '${folder}_$cleanHash$ext';
  }

  /// High-speed O(1) path resolver with zero unnecessary disk I/O on UI thread
  String? getLocalFilePath(String? url) {
    if (url == null || url.trim().isEmpty) return null;
    final cachedPath = cacheBox.get(url.trim()) as String?;
    if (cachedPath == null) return null;

    // First check in-memory verified cache
    if (_verifiedLocalPaths.contains(cachedPath)) {
      return cachedPath;
    }

    // Verify on disk once and remember in memory
    if (File(cachedPath).existsSync()) {
      _verifiedLocalPaths.add(cachedPath);
      return cachedPath;
    }
    return null;
  }

  bool isFileCached(String? url) {
    return getLocalFilePath(url) != null;
  }

  /// Download and cache with in-flight deduplication to avoid redundant HTTP requests
  Future<String?> downloadAndCacheFile(
    String url, {
    String folder = 'media',
  }) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty || !cleanUrl.startsWith('http')) return null;

    // Check if already verified and cached
    final existing = getLocalFilePath(cleanUrl);
    if (existing != null) return existing;

    // If an identical download is already in progress, share the future
    if (_inFlightDownloads.containsKey(cleanUrl)) {
      return _inFlightDownloads[cleanUrl]!;
    }

    final downloadFuture = _executeDownload(cleanUrl, folder);
    _inFlightDownloads[cleanUrl] = downloadFuture;

    try {
      return await downloadFuture;
    } finally {
      _inFlightDownloads.remove(cleanUrl);
    }
  }

  Future<String?> _executeDownload(String cleanUrl, String folder) async {
    try {
      await init();
      final subFolder = Directory('${_baseDir!.path}/$folder');
      if (!await subFolder.exists()) {
        await subFolder.create(recursive: true);
      }

      final fileName = _generateFileName(cleanUrl, folder);
      final file = File('${subFolder.path}/$fileName');

      final response = await http
          .get(Uri.parse(cleanUrl))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200 && _looksLikeAudio(response.bodyBytes)) {
        await file.writeAsBytes(response.bodyBytes);
        await cacheBox.put(cleanUrl, file.path);
        _verifiedLocalPaths.add(file.path);
        return file.path;
      }
    } catch (e) {
      // Failed to download or save, continue silently
    }
    return null;
  }

  Future<void> invalidate(String url) async {
    final cleanUrl = url.trim();
    final cachedPath = cacheBox.get(cleanUrl) as String?;
    _verifiedLocalPaths.remove(cachedPath);
    await cacheBox.delete(cleanUrl);
    if (cachedPath == null) return;
    final file = File(cachedPath);
    if (await file.exists()) await file.delete();
  }

  bool _looksLikeAudio(List<int> bytes) {
    if (bytes.length < 12) return false;
    final riff = bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46;
    final id3 = bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33;
    final mp3 = bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0;
    final m4a = bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70;
    return riff || id3 || mp3 || m4a;
  }

  /// Fire-and-forget download in background without awaiting.
  /// Excellent for performance where we want to show a URL instantly
  /// but silently cache it for future offline uses.
  void downloadAndCacheInBackground(String url, {String folder = 'media'}) {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty || !cleanUrl.startsWith('http')) return;

    if (isFileCached(cleanUrl)) return;

    // Don't wait, let it run in background
    downloadAndCacheFile(cleanUrl, folder: folder);
  }
}
