import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../di/injection_container.dart';
import '../services/resource_manager.dart';
import 'admin_phrase_voice.dart';
import 'child_button_clips.dart';

/// Plays a clip bundled in the app, then runs the button action.
/// Nothing is downloaded at runtime.
class ChildButtonVoice {
  ChildButtonVoice._();

  static final AudioPlayer _player = AudioPlayer()
    ..setReleaseMode(ReleaseMode.stop);

  /// True while a button clip is playing.
  static final speaking = ValueNotifier<bool>(false);

  static var _playId = 0;
  static var _busy = false;
  static var _contextReady = false;
  static var _playerReady = false;
  static var _singleUntil = DateTime.fromMillisecondsSinceEpoch(0);
  static final _durations = <String, Duration>{};

  /// [single] ignores another tap until this clip finishes and the screen moves.
  static Future<void> press(
    String phrase,
    Future<void> Function() action, {
    bool single = false,
  }) async {
    if (_busy) return;
    final now = DateTime.now();
    if (single && now.isBefore(_singleUntil)) return;
    _busy = true;
    if (single) {
      _singleUntil = now.add(const Duration(milliseconds: 450));
    }

    try {
      await _playLocal(phrase.trim()).timeout(const Duration(seconds: 12));
    } catch (_) {}
    try {
      await action();
    } catch (_) {}
    finally {
      _busy = false;
    }
  }

  /// Plays bundled clips one after another. A later [press] stops the sequence.
  static Future<void> playSequence(List<String> phrases) async {
    final id = ++_playId;
    final sources = [
      for (final phrase in phrases) _localSource(phrase.trim()),
    ].whereType<Source>().toList();
    if (sources.isEmpty) return;
    speaking.value = true;
    try {
      await _ensureContext();
      for (final source in sources) {
        if (id != _playId) return;
        await _playSource(source, id, _sourceKey(source));
        if (id != _playId) return;
        await Future<void>.delayed(const Duration(milliseconds: 320));
      }
    } catch (_) {
    } finally {
      if (id == _playId) speaking.value = false;
    }
  }

  /// Prepares the local player before the first tap so the story audio
  /// is not interrupted by a late audio-session change.
  static Future<void> warm() async {
    await _ensureContext();
  }

  static Future<void> _ensureContext() async {
    if (_playerReady) return;
    try {
      if (!_contextReady) {
        await _player
            .setAudioContext(
              AudioContext(
                android: const AudioContextAndroid(
                  contentType: AndroidContentType.sonification,
                  usageType: AndroidUsageType.assistanceSonification,
                  audioFocus: AndroidAudioFocus.gainTransientMayDuck,
                ),
                iOS: AudioContextIOS(
                  category: AVAudioSessionCategory.playback,
                  options: const {
                    AVAudioSessionOptions.mixWithOthers,
                    AVAudioSessionOptions.duckOthers,
                  },
                ),
              ),
            )
            .timeout(const Duration(milliseconds: 400));
        _contextReady = true;
      }
      await _player.setPlayerMode(PlayerMode.mediaPlayer);
      await _player.setReleaseMode(ReleaseMode.stop);
      _playerReady = true;
    } catch (_) {}
  }

  /// Plays a clip that is already on the device. A missing clip stays silent
  /// so a tap never waits on the network.
  static Future<void> _playLocal(String phrase) async {
    if (phrase.isEmpty) return;
    final Source? source = _localSource(phrase);
    if (source == null) return;
    final id = ++_playId;
    speaking.value = true;
    try {
      await _ensureContext();
      await _playSource(source, id, phrase);
    } catch (_) {
    } finally {
      if (id == _playId) speaking.value = false;
    }
  }

  /// Plays [source] and waits for its length. The completion event on this
  /// player often never arrives, which left every button locked.
  static Future<void> _playSource(
    Source source,
    int id,
    String cacheKey,
  ) async {
    await _player.play(source).timeout(const Duration(seconds: 2));
    if (id != _playId) return;
    var duration = _durations[cacheKey];
    if (duration == null) {
      try {
        duration = await _player
            .getDuration()
            .timeout(const Duration(milliseconds: 400));
        if (duration != null && duration > Duration.zero) {
          _durations[cacheKey] = duration;
        }
      } catch (_) {}
    }
    final wait = duration == null || duration <= Duration.zero
        ? const Duration(milliseconds: 900)
        : duration;
    await Future<void>.delayed(wait);
  }

  static String _sourceKey(Source source) {
    if (source is AssetSource) return source.path;
    if (source is DeviceFileSource) return source.path;
    return source.toString();
  }

  static Source? _localSource(String phrase) {
    final asset = childButtonClips[phrase];
    if (asset != null) return AssetSource(asset);
    if (kIsWeb) return null;
    final path = sl<ResourceManager>().getLocalFilePath(
      AdminPhraseVoice.urlFor(phrase),
    );
    if (path == null || !File(path).existsSync()) return null;
    return DeviceFileSource(path);
  }
}
