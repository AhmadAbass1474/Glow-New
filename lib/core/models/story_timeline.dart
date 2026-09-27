import 'package:flutter/material.dart';

class StoryBlock {
  final String characterId;
  final double startTime; // In seconds
  final double endTime; // In seconds

  StoryBlock({
    required this.characterId,
    required this.startTime,
    required this.endTime,
  });

  bool isPlaying(double currentTime) {
    return currentTime >= startTime && currentTime <= endTime;
  }

  factory StoryBlock.fromJson(Map<String, dynamic> json) {
    return StoryBlock(
      characterId: json['characterId'] as String,
      startTime: (json['startTime'] as num).toDouble(),
      endTime: (json['endTime'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'characterId': characterId,
      'startTime': startTime,
      'endTime': endTime,
    };
  }
}

class StoryMotionBlock {
  final String motionId; // Usually the clipName of CharacterMotion
  final double startTime; // In seconds
  final double endTime; // In seconds

  StoryMotionBlock({
    required this.motionId,
    required this.startTime,
    required this.endTime,
  });

  bool isPlaying(double currentTime) {
    return currentTime >= startTime && currentTime <= endTime;
  }

  factory StoryMotionBlock.fromJson(Map<String, dynamic> json) {
    return StoryMotionBlock(
      motionId: json['motionId'] as String,
      startTime: (json['startTime'] as num).toDouble(),
      endTime: (json['endTime'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'motionId': motionId,
      'startTime': startTime,
      'endTime': endTime,
    };
  }
}

/// Timed hat overlay. Drag payload uses `hat:RRGGBB`.
class StoryHatBlock {
  final String colorHex; // RRGGBB, no leading #
  final double startTime;
  final double endTime;

  StoryHatBlock({
    required this.colorHex,
    required this.startTime,
    required this.endTime,
  });

  Color get color {
    final normalized = colorHex.replaceAll('#', '').padLeft(6, '0');
    return Color(int.parse('FF$normalized', radix: 16));
  }

  static String dragDataFor(Color color) {
    final hex = (color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
    return 'hat:$hex';
  }

  static String? colorHexFromDrag(String data) {
    if (!data.startsWith('hat:')) return null;
    final hex = data.substring(4).replaceAll('#', '');
    if (hex.length != 6) return null;
    return hex.toLowerCase();
  }

  bool isPlaying(double currentTime) {
    return currentTime >= startTime && currentTime <= endTime;
  }

  factory StoryHatBlock.fromJson(Map<String, dynamic> json) {
    return StoryHatBlock(
      colorHex: (json['colorHex'] as String? ?? '2c2c2e').replaceAll('#', ''),
      startTime: (json['startTime'] as num).toDouble(),
      endTime: (json['endTime'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'colorHex': colorHex,
      'startTime': startTime,
      'endTime': endTime,
    };
  }
}

/// Timed glasses overlay. Drag payload is `glasses`.
class StoryGlassesBlock {
  final double startTime;
  final double endTime;

  StoryGlassesBlock({required this.startTime, required this.endTime});

  static const dragData = 'glasses';

  static bool isDrag(String data) => data == dragData;

  bool isPlaying(double currentTime) {
    return currentTime >= startTime && currentTime <= endTime;
  }

  factory StoryGlassesBlock.fromJson(Map<String, dynamic> json) {
    return StoryGlassesBlock(
      startTime: (json['startTime'] as num).toDouble(),
      endTime: (json['endTime'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'startTime': startTime, 'endTime': endTime};
  }
}

class StoryTimeline {
  final List<StoryBlock> blocks;
  final List<StoryMotionBlock> motionBlocks;
  final List<StoryHatBlock> hatBlocks;
  final List<StoryGlassesBlock> glassesBlocks;
  final double totalDuration; // In seconds

  StoryTimeline({
    required this.blocks,
    this.motionBlocks = const [],
    this.hatBlocks = const [],
    this.glassesBlocks = const [],
    required this.totalDuration,
  });

  /// Returns the character that should be active at the given time.
  /// If multiple blocks overlap, it returns the first one found.
  /// If no block is active, it returns null.
  String? getActiveCharacterAt(double time) {
    for (final block in blocks) {
      if (block.isPlaying(time)) {
        return block.characterId;
      }
    }
    return null;
  }

  /// Returns the motion that should be active at the given time.
  String? getActiveMotionAt(double time) {
    for (final block in motionBlocks) {
      if (block.isPlaying(time)) {
        return block.motionId;
      }
    }
    return null;
  }

  /// Returns the hat block active at [time], or null when the hat is off.
  StoryHatBlock? getActiveHatAt(double time) {
    for (final block in hatBlocks) {
      if (block.isPlaying(time)) return block;
    }
    return null;
  }

  /// Whether the glasses should be on at [time].
  bool glassesOnAt(double time) {
    for (final block in glassesBlocks) {
      if (block.isPlaying(time)) return true;
    }
    return false;
  }

  /// Returns a unique list of all characters used in this timeline
  /// This is useful for preloading models.
  List<String> get allCharacterIds {
    return blocks.map((b) => b.characterId).toSet().toList();
  }

  factory StoryTimeline.fromJson(Map<String, dynamic> json) {
    final blocksList = json['blocks'] as List<dynamic>? ?? [];
    final motionBlocksList = json['motionBlocks'] as List<dynamic>? ?? [];
    final hatBlocksList = json['hatBlocks'] as List<dynamic>? ?? [];
    final glassesBlocksList = json['glassesBlocks'] as List<dynamic>? ?? [];
    return StoryTimeline(
      blocks: blocksList
          .map((b) => StoryBlock.fromJson(b as Map<String, dynamic>))
          .toList(),
      motionBlocks: motionBlocksList
          .map((b) => StoryMotionBlock.fromJson(b as Map<String, dynamic>))
          .toList(),
      hatBlocks: hatBlocksList
          .map((b) => StoryHatBlock.fromJson(b as Map<String, dynamic>))
          .toList(),
      glassesBlocks: glassesBlocksList
          .map((b) => StoryGlassesBlock.fromJson(b as Map<String, dynamic>))
          .toList(),
      totalDuration: (json['totalDuration'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'blocks': blocks.map((b) => b.toJson()).toList(),
      'motionBlocks': motionBlocks.map((b) => b.toJson()).toList(),
      'hatBlocks': hatBlocks.map((b) => b.toJson()).toList(),
      'glassesBlocks': glassesBlocks.map((b) => b.toJson()).toList(),
      'totalDuration': totalDuration,
    };
  }
}
