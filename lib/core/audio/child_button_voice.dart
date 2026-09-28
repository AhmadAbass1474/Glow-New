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
  static String? _queuedPhrase;
  static Future<void> Function()? _queuedAction;
  static final _durations = <String, Duration>{};

  /// Plays [phrase], then runs [action].
  /// A tap while another clip is playing is kept and runs after it,
  /// so a button is never ignored.
  /// Returns false when the tap was only queued.
  static Future<bool> press(
    String phrase,
    Future<void> Function() action, {
    bool single = false,
  }) async {
    if (_busy) {
      _queuedPhrase = phrase;
      _queuedAction = action;
      return false;
    }
    _busy = true;

    try {
      await _playLocal(phrase.trim()).timeout(const Duration(seconds: 12));
    } catch (_) {}
    try {
      await action();
    } catch (_) {}
    finally {
      _busy = false;
    }

    final nextPhrase = _queuedPhrase;
    final nextAction = _queuedAction;
    _queuedPhrase = null;
    _queuedAction = null;
    if (nextPhrase != null && nextAction != null) {
      await press(nextPhrase, nextAction, single: single);
    }
    return true;
  }

  /// Stops whatever is playing so a closed screen does not keep talking.
  static Future<void> stop() async {
    ++_playId;
    _queuedPhrase = null;
    _queuedAction = null;
    speaking.value = false;
    try {
      await _player.stop();
    } catch (_) {}
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
    try {
      await _player.stop().timeout(const Duration(milliseconds: 300));
    } catch (_) {}
    if (id != _playId) return;
    await _player.play(source).timeout(const Duration(seconds: 2));
    if (id != _playId) return;
    var duration = _durations[cacheKey];
    if (duration == null) {
      try {
        duration = await _player
            .getDuration()
            .timeout(const Duration(milliseconds: 400));
        if (duration != null &&
            duration > Duration.zero &&
            duration < const Duration(seconds: 20)) {
          _durations[cacheKey] = duration;
        } else {
          duration = null;
        }
      } catch (_) {}
    }
    final wait = duration == null || duration <= Duration.zero
        ? const Duration(milliseconds: 900)
        : duration;
    final end = DateTime.now().add(wait);
    while (id == _playId && DateTime.now().isBefore(end)) {
      final left = end.difference(DateTime.now());
      final step = left < const Duration(milliseconds: 120)
          ? left
          : const Duration(milliseconds: 120);
      if (step <= Duration.zero) break;
      await Future<void>.delayed(step);
    }
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
