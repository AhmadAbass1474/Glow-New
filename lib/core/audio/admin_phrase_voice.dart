import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'story_sentence_voice.dart';

/// One soft child voice for admin text fields, stored so the child can hear it.
class AdminPhraseVoice {
  AdminPhraseVoice._();

  static const _bucket = 'story_audio';

  static String fileId(String text) {
    var hash = 0xcbf29ce484222325;
    for (final unit in text.trim().codeUnits) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  static String urlFor(String text) {
    final id = fileId(text);
    return Supabase.instance.client.storage
        .from(_bucket)
        .getPublicUrl('phrase_$id.wav');
  }

  static Future<File> speak(String text) async {
    final clip = await StorySentenceVoice.speakNarrator(text.trim());
    final id = fileId(text);
    try {
      await Supabase.instance.client.storage.from(_bucket).upload(
            'phrase_$id.wav',
            clip.file,
            fileOptions: const FileOptions(
              contentType: 'audio/wav',
              upsert: true,
            ),
          );
    } catch (_) {}
    return clip.file;
  }

  static Future<void> play(File file) async {
    final player = AudioPlayer();
    try {
      await player.setPlayerMode(PlayerMode.mediaPlayer);
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setVolume(1);
      final done = player.onPlayerComplete.first;
      await player.play(DeviceFileSource(file.path));
      await done.timeout(const Duration(seconds: 30));
    } catch (_) {
    } finally {
      await player.dispose();
    }
  }
}
