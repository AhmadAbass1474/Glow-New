import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/character_helper.dart';
import 'character_offline_pack.dart';

/// Shared immutable asset bytes for native/web three_js viewers.
/// Mobile WebView uses [CharacterOfflinePack] instead of these bytes.
class CharacterAssetCache {
  CharacterAssetCache({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  static final instance = CharacterAssetCache();
  final AssetBundle _bundle;
  final _assets = <String, Future<Uint8List>>{};

  Future<Uint8List> load(String path) {
    final cached = _assets[path];
    if (cached != null) return cached;
    final pending = _read(path);
    _assets[path] = pending;
    return pending;
  }

  Future<Uint8List> _read(String path) async {
    try {
      final data = await _bundle.load(path);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (_) {
      _assets.remove(path);
      rethrow;
    }
  }

  /// Prefetch shared model bytes (web/desktop) and stage the mobile disk pack.
  Future<void> prewarm() async {
    try {
      await Future.wait([
        load(CharacterHelper.sharedModelPath),
        if (!kIsWeb) CharacterOfflinePack.instance.prewarm(),
      ]);
    } catch (_) {
      // Visible viewers own retry/error UI.
    }
  }
}
