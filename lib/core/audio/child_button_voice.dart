import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

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
  static var _contextReady = false;
  static var _singleUntil = DateTime.fromMillisecondsSinceEpoch(0);

  /// [single] ignores a second tap for a moment so a child cannot open
  /// two screens or skip two scenes with one double press.
  static Future<void> press(
    String phrase,
    Future<void> Function() action, {
    bool single = false,
  }) async {
    final now = DateTime.now();
    if (single && now.isBefore(_singleUntil)) return;
    if (single) {
      _singleUntil = now.add(const Duration(milliseconds: 450));
    }

    final asset = childButtonClips[phrase.trim()];
    if (asset != null) {
      unawaited(_playBundled(asset));
    }
    try {
      await action();
    } catch (_) {}
  }

  /// Prepares the local player before the first tap so the story audio
  /// is not interrupted by a late audio-session change.
  static Future<void> warm() async {
    await _ensureContext();
  }

  static Future<void> _ensureContext() async {
    if (_contextReady) return;
    _contextReady = true;
    try {
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
    } catch (_) {}
  }

  static Future<void> _playBundled(String asset) async {
    final id = ++_playId;
    speaking.value = true;
    try {
      await _ensureContext();
      final done = _player.onPlayerComplete.first;
      await _player.play(AssetSource(asset));
      await done.timeout(const Duration(milliseconds: 2500));
    } catch (_) {
    } finally {
      if (id == _playId) speaking.value = false;
    }
  }
}
