import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/character_helper.dart';

/// Stages the mobile Three.js shell and shared GLB under app support so the
/// WebView loads them as local files — no base64 bridge, fully offline.
class CharacterOfflinePack {
  CharacterOfflinePack({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  static final instance = CharacterOfflinePack();

  static const htmlAsset = 'assets/3d/character_mobile.html';
  static const jsAsset = 'assets/3d/character_mobile.js';
  static const modelAsset = CharacterHelper.sharedModelPath;

  static const htmlFileName = 'character_mobile.html';
  static const jsFileName = 'character_mobile.js';
  static const modelFileName = 'glow_mascot.glb';
  static const overrideFileName = 'override.glb';
  static const stampFileName = 'pack.stamp.json';

  final AssetBundle _bundle;
  Future<Directory>? _ready;

  File htmlFile(Directory dir) => File('${dir.path}/$htmlFileName');
  File modelFile(Directory dir) => File('${dir.path}/$modelFileName');
  File overrideFile(Directory dir) => File('${dir.path}/$overrideFileName');

  /// Idempotent: copies assets once (or when the stamp changes).
  Future<Directory> ensureReady() => _ready ??= _stage();

  /// Warm the on-disk pack during app startup.
  Future<void> prewarm() async {
    if (kIsWeb) return;
    try {
      await ensureReady();
    } catch (error, stack) {
      _ready = null;
      debugPrint('CharacterOfflinePack prewarm failed: $error\n$stack');
    }
  }

  /// Place a custom model beside the shell so WebView can read it locally.
  Future<String> stageOverride(Uint8List bytes) async {
    final dir = await ensureReady();
    final file = overrideFile(dir);
    await file.writeAsBytes(bytes, flush: true);
    return overrideFileName;
  }

  /// Copy an already-downloaded custom model into the pack directory.
  Future<String> stageOverrideFile(String path) async {
    final dir = await ensureReady();
    final file = overrideFile(dir);
    await File(path).copy(file.path);
    return overrideFileName;
  }

  Future<Directory> _stage() async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}/character_runtime');
    await dir.create(recursive: true);

    final planned = <String, int>{
      htmlFileName: await _assetLength(htmlAsset),
      jsFileName: await _assetLength(jsAsset),
      modelFileName: await _assetLength(modelAsset),
      // Bumps the stamp when the shell is rewritten as one offline file.
      'inlineScript': 1,
    };
    final stampFile = File('${dir.path}/$stampFileName');
    if (await _stampMatches(stampFile, planned) &&
        await htmlFile(dir).exists() &&
        await modelFile(dir).exists()) {
      return dir;
    }

    await _writeOfflineShell(htmlFile(dir));
    await _copyAsset(modelAsset, modelFile(dir));
    await stampFile.writeAsString(jsonEncode(planned), flush: true);
    return dir;
  }

  Future<int> _assetLength(String assetPath) async {
    final data = await _bundle.load(assetPath);
    return data.lengthInBytes;
  }

  Future<bool> _stampMatches(File stampFile, Map<String, int> planned) async {
    if (!await stampFile.exists()) return false;
    try {
      final raw = jsonDecode(await stampFile.readAsString());
      if (raw is! Map) return false;
      for (final entry in planned.entries) {
        if (raw[entry.key] != entry.value) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// One HTML file with the viewer script inside it, so the WebView never
  /// requests a second file or the network.
  Future<void> _writeOfflineShell(File destination) async {
    final html = await _assetText(htmlAsset);
    final script = (await _assetText(jsAsset)).replaceAll(
      '</script',
      '<\\/script',
    );
    final shell = html
        .replaceFirst("script-src 'self'", "script-src 'unsafe-inline'")
        .replaceFirst(
          '<script src="character_mobile.js"></script>',
          '<script>$script</script>',
        );
    if (shell.contains('src="character_mobile.js"')) {
      throw StateError('Character shell script was not inlined');
    }
    await destination.writeAsString(shell, flush: true);
  }

  Future<String> _assetText(String assetPath) async {
    final data = await _bundle.load(assetPath);
    return utf8.decode(data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    ));
  }

  Future<void> _copyAsset(String assetPath, File destination) async {
    final data = await _bundle.load(assetPath);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    await destination.writeAsBytes(bytes, flush: true);
  }
}
