import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// One fixed ElevenLabs voice per character, so every line keeps that tone.
class StorySentenceVoice {
  StorySentenceVoice._();

  static const _apiKey =
      'sk_70ad200afdaeee4ef1fb1a42d9a9af9ca69ec2d01c8e617f';

  static const voices = <String, String>{
    'fort': 'IKne3meq5aSn9XLyUdCD',
    'lort': 'pFZP5JQG7iQjIQuC4Bku',
    'mort': 'FGY2WhTYpPnrIDTdsKH5',
    'port': 'Xb7hH8MSUJpSbSDYk0k2',
    'qort': 'cgSgspJ2msm6clMCkdW9',
  };

  static const _pitch = <String, double>{
    'fort': 1.18,
    'lort': 1.10,
    'mort': 1.15,
    'port': 1.08,
    'qort': 1.12,
  };

  static const _sampleRate = 22050;

  static Future<({File file, double seconds})> speak({
    required String characterId,
    required String text,
  }) {
    return _render(
      voiceId: voices[characterId] ?? voices['qort']!,
      pitch: (_pitch[characterId] ?? 1.12) + 0.06,
      text: text,
    );
  }

  /// One soft child narrator for buttons and field speech.
  static Future<({File file, double seconds})> speakNarrator(String text) {
    return _render(
      voiceId: 'pFZP5JQG7iQjIQuC4Bku',
      pitch: 1.24,
      text: text,
    );
  }

  static Future<({File file, double seconds})> _render({
    required String voiceId,
    required double pitch,
    required String text,
  }) async {
    final response = await http
        .post(
          Uri.parse(
            'https://api.elevenlabs.io/v1/text-to-speech/$voiceId?output_format=pcm_22050',
          ),
          headers: {
            'xi-api-key': _apiKey,
            'Content-Type': 'application/json',
            'Accept': 'application/octet-stream',
          },
          body: jsonEncode({
            'text': text,
            'model_id': 'eleven_multilingual_v2',
            'voice_settings': {
              'stability': 0.8,
              'similarity_boost': 0.62,
              'style': 0.0,
              'use_speaker_boost': false,
            },
            'speed': 0.84,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200 || response.bodyBytes.length < 256) {
      throw Exception('تعذر توليد الصوت');
    }

    final pcm = _childTone(response.bodyBytes, pitch);
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/glow_line_${DateTime.now().microsecondsSinceEpoch}.wav',
    );
    await file.writeAsBytes(_wav(pcm), flush: true);
    return (file: file, seconds: _pcmSeconds(pcm.length));
  }

  static Future<({File file, double seconds})> join(List<File> clips) async {
    final pcm = BytesBuilder(copy: false);
    for (final clip in clips) {
      pcm.add(_pcmFromWav(await clip.readAsBytes()));
    }
    final bytes = pcm.toBytes();
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/glow_scene_${DateTime.now().microsecondsSinceEpoch}.wav',
    );
    await file.writeAsBytes(_wav(bytes), flush: true);
    return (file: file, seconds: _pcmSeconds(bytes.length));
  }

  static Uint8List _childTone(List<int> pcm, double factor) {
    final samples = pcm.length ~/ 2;
    if (samples < 2) return Uint8List.fromList(pcm);
    final input = ByteData.sublistView(Uint8List.fromList(pcm));
    final outCount = (samples / factor).floor();
    final out = Uint8List(outCount * 2);
    final output = ByteData.sublistView(out);
    var smooth = 0.0;
    for (var i = 0; i < outCount; i++) {
      final src = i * factor;
      final i0 = src.floor().clamp(0, samples - 1);
      final i1 = (i0 + 1).clamp(0, samples - 1);
      final t = src - i0;
      final s0 = input.getInt16(i0 * 2, Endian.little);
      final s1 = input.getInt16(i1 * 2, Endian.little);
      final mixed = s0 + (s1 - s0) * t;
      smooth = smooth * 0.35 + mixed * 0.65;
      final soft = (smooth * 0.82).round().clamp(-32768, 32767);
      output.setInt16(i * 2, soft, Endian.little);
    }
    return out;
  }

  static double _pcmSeconds(int byteLength) {
    final seconds = byteLength / (_sampleRate * 2);
    return seconds < 0.05 ? 0.05 : seconds;
  }

  static Uint8List _pcmFromWav(List<int> wav) {
    if (wav.length > 12 &&
        wav[0] == 0x52 &&
        wav[1] == 0x49 &&
        wav[2] == 0x46 &&
        wav[3] == 0x46) {
      var offset = 12;
      while (offset + 8 <= wav.length) {
        final size = wav[offset + 4] |
            (wav[offset + 5] << 8) |
            (wav[offset + 6] << 16) |
            (wav[offset + 7] << 24);
        final isData = wav[offset] == 0x64 &&
            wav[offset + 1] == 0x61 &&
            wav[offset + 2] == 0x74 &&
            wav[offset + 3] == 0x61;
        final start = offset + 8;
        if (isData) {
          final end = (start + size).clamp(start, wav.length);
          return Uint8List.fromList(wav.sublist(start, end));
        }
        offset = start + size + (size.isOdd ? 1 : 0);
      }
    }
    return Uint8List.fromList(wav);
  }

  static Uint8List _wav(List<int> pcm) {
    final dataSize = pcm.length;
    final out = BytesBuilder(copy: false);
    out.add('RIFF'.codeUnits);
    out.add(_le32(36 + dataSize));
    out.add('WAVE'.codeUnits);
    out.add('fmt '.codeUnits);
    out.add(_le32(16));
    out.add(_le16(1));
    out.add(_le16(1));
    out.add(_le32(_sampleRate));
    out.add(_le32(_sampleRate * 2));
    out.add(_le16(2));
    out.add(_le16(16));
    out.add('data'.codeUnits);
    out.add(_le32(dataSize));
    out.add(pcm);
    return out.toBytes();
  }

  static List<int> _le16(int value) => [value & 0xff, (value >> 8) & 0xff];

  static List<int> _le32(int value) => [
        value & 0xff,
        (value >> 8) & 0xff,
        (value >> 16) & 0xff,
        (value >> 24) & 0xff,
      ];
}
