import 'dart:io';
import 'dart:math';
import 'package:Glow/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import '../animation/story_motion.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/story_timeline.dart';
import '../utils/character_helper.dart';
import 'smart_character_viewer.dart';

class StoryTimelineEditor extends StatefulWidget {
  final File audioFile;
  final StoryTimeline? initialTimeline;
  final ValueChanged<StoryTimeline> onTimelineChanged;
  final ValueNotifier<Duration>? positionNotifier;
  final AudioPlayer? audioPlayer;
  final bool isPlaying;
  final VoidCallback? onTogglePlay;

  const StoryTimelineEditor({
    super.key,
    required this.audioFile,
    this.initialTimeline,
    required this.onTimelineChanged,
    this.positionNotifier,
    this.audioPlayer,
    this.isPlaying = false,
    this.onTogglePlay,
  });

  @override
  State<StoryTimelineEditor> createState() => _StoryTimelineEditorState();
}

class _StoryTimelineEditorState extends State<StoryTimelineEditor> {
  late AudioPlayer _localAudioPlayer; 
  Duration _totalDuration = Duration.zero;
  List<StoryBlock> _blocks = [];
  List<StoryMotionBlock> _motionBlocks = [];
  List<StoryHatBlock> _hatBlocks = [];
  bool _isLoading = true;
  
  double _pixelsPerSecond = 80.0;
  final double _blockHeight = 50.0;
  final double _trackHeight = 60.0;
  final double _waveformHeight = 40.0;

  static const _hatPaletteColors = <Color>[
    Color(0xFF2C2C2E),
    Color(0xFF1A1A1A),
    Color(0xFF4A3728),
    Color(0xFF8B4513),
    Color(0xFFC0392B),
    Color(0xFF277A59),
    Color(0xFF2E86C1),
    Color(0xFFF5F5F5),
  ];
  
  final GlobalKey _trackKey = GlobalKey();
  final GlobalKey _motionTrackKey = GlobalKey();
  final GlobalKey _hatTrackKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();
  
  int? _selectedBlockIndex;
  int? _selectedMotionBlockIndex;
  int? _selectedHatBlockIndex;
  String? _lastPreviewCharacter;
  String? _lastPreviewMotion;

  @override
  void initState() {
    super.initState();
    _localAudioPlayer = AudioPlayer();
    if (widget.initialTimeline != null) {
      if (widget.initialTimeline!.blocks.isNotEmpty) {
        _blocks = List.from(widget.initialTimeline!.blocks);
      }
      if (widget.initialTimeline!.motionBlocks.isNotEmpty) {
        _motionBlocks = List.from(widget.initialTimeline!.motionBlocks);
      }
      if (widget.initialTimeline!.hatBlocks.isNotEmpty) {
        _hatBlocks = List.from(widget.initialTimeline!.hatBlocks);
      }
    }
    _loadAudioDuration();
    
    widget.positionNotifier?.addListener(_onPositionChanged);
  }

  @override
  void didUpdateWidget(covariant StoryTimelineEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audioFile.path != widget.audioFile.path) {
      _loadAudioDuration();
    }
    if (oldWidget.positionNotifier != widget.positionNotifier) {
      oldWidget.positionNotifier?.removeListener(_onPositionChanged);
      widget.positionNotifier?.addListener(_onPositionChanged);
    }
  }

  void _onPositionChanged() {
    if (!mounted) return;
    setState(() {}); // Re-render playhead
    
    if (_scrollController.hasClients && widget.positionNotifier != null) {
      final currentTime = widget.positionNotifier!.value.inMilliseconds / 1000.0;
      final playheadPos = currentTime * _pixelsPerSecond;
      final offset = _scrollController.offset;
      final width = _scrollController.position.viewportDimension;
      
      // Keep playhead within the visible 80% of the screen
      if (playheadPos > offset + width * 0.8) {
        _scrollController.jumpTo(playheadPos - width * 0.8);
      } else if (playheadPos < offset) {
        _scrollController.jumpTo(playheadPos);
      }
    }
  }

  Future<void> _loadAudioDuration() async {
    setState(() => _isLoading = true);
    try {
      await _localAudioPlayer.setSourceDeviceFile(widget.audioFile.path);
      final duration = await _localAudioPlayer.getDuration();
      if (duration != null && mounted) {
        setState(() {
          _totalDuration = duration;
          _isLoading = false;
        });
        
        final totalSeconds = duration.inMilliseconds / 1000.0;
        
        // Timeline starts empty by default
        if (_blocks.isEmpty) {
          _notifyChanged();
        }
      }
    } catch (e) {
      debugPrint('Error loading audio: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    widget.positionNotifier?.removeListener(_onPositionChanged);
    _localAudioPlayer.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _notifyChanged() {
    _blocks.sort((a, b) => a.startTime.compareTo(b.startTime));
    _motionBlocks.sort((a, b) => a.startTime.compareTo(b.startTime));
    _hatBlocks.sort((a, b) => a.startTime.compareTo(b.startTime));
    widget.onTimelineChanged(StoryTimeline(
      blocks: _blocks,
      motionBlocks: _motionBlocks,
      hatBlocks: _hatBlocks,
      totalDuration: _totalDuration.inMilliseconds / 1000.0,
    ));
  }

  String _formatTime(double seconds) {
    final d = Duration(milliseconds: (seconds * 1000).round());
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _addBlockAtTime(String characterId, double timeInSeconds) {
    final totalSeconds = _totalDuration.inMilliseconds / 1000.0;
    if (totalSeconds == 0) return;

    if (timeInSeconds < 0) timeInSeconds = 0;
    double end = timeInSeconds + 3.0;
    if (end > totalSeconds) end = totalSeconds;

    final List<StoryBlock> updatedBlocks = [];
    for (var b in _blocks) {
      if (b.endTime <= timeInSeconds || b.startTime >= end) {
        updatedBlocks.add(b);
      } else if (b.startTime < timeInSeconds && b.endTime > end) {
        updatedBlocks.add(StoryBlock(characterId: b.characterId, startTime: b.startTime, endTime: timeInSeconds));
        updatedBlocks.add(StoryBlock(characterId: b.characterId, startTime: end, endTime: b.endTime));
      } else if (b.startTime < timeInSeconds && b.endTime <= end) {
        updatedBlocks.add(StoryBlock(characterId: b.characterId, startTime: b.startTime, endTime: timeInSeconds));
      } else if (b.startTime >= timeInSeconds && b.endTime > end) {
        updatedBlocks.add(StoryBlock(characterId: b.characterId, startTime: end, endTime: b.endTime));
      }
    }
    updatedBlocks.add(StoryBlock(characterId: characterId, startTime: timeInSeconds, endTime: end));
    
    setState(() {
      _blocks = updatedBlocks;
      _selectedBlockIndex = _blocks.indexWhere((b) => b.startTime == timeInSeconds);
    });
    _notifyChanged();
  }

  void _updateBlockStart(int index, double deltaSeconds) {
    final block = _blocks[index];
    double newStart = block.startTime + deltaSeconds;
    
    if (newStart < 0) newStart = 0;
    if (newStart > block.endTime - 0.5) newStart = block.endTime - 0.5;
    
    if (index > 0) {
      final prevBlock = _blocks[index - 1];
      if (newStart < prevBlock.endTime) newStart = prevBlock.endTime;
    }

    setState(() {
      _blocks[index] = StoryBlock(
        characterId: block.characterId,
        startTime: newStart,
        endTime: block.endTime,
      );
    });
    _notifyChanged();
  }

  void _updateBlockEnd(int index, double deltaSeconds) {
    final block = _blocks[index];
    double newEnd = block.endTime + deltaSeconds;
    
    final totalSeconds = _totalDuration.inMilliseconds / 1000.0;
    if (newEnd > totalSeconds) newEnd = totalSeconds;
    if (newEnd < block.startTime + 0.5) newEnd = block.startTime + 0.5;
    
    if (index < _blocks.length - 1) {
      final nextBlock = _blocks[index + 1];
      if (newEnd > nextBlock.startTime) newEnd = nextBlock.startTime;
    }

    setState(() {
      _blocks[index] = StoryBlock(
        characterId: block.characterId,
        startTime: block.startTime,
        endTime: newEnd,
      );
    });
    _notifyChanged();
  }

  void _moveBlock(int index, double deltaSeconds) {
    final block = _blocks[index];
    double newStart = block.startTime + deltaSeconds;
    double duration = block.endTime - block.startTime;
    
    if (newStart < 0) newStart = 0;
    
    final totalSeconds = _totalDuration.inMilliseconds / 1000.0;
    if (newStart + duration > totalSeconds) newStart = totalSeconds - duration;

    if (index > 0 && newStart < _blocks[index - 1].endTime) {
      newStart = _blocks[index - 1].endTime;
    }
    if (index < _blocks.length - 1 && (newStart + duration) > _blocks[index + 1].startTime) {
      newStart = _blocks[index + 1].startTime - duration;
    }

    setState(() {
      _blocks[index] = StoryBlock(
        characterId: block.characterId,
        startTime: newStart,
        endTime: newStart + duration,
      );
    });
    _notifyChanged();
  }

  void _splitBlock() {
    if (_selectedBlockIndex == null) return;
    final time = (widget.positionNotifier?.value.inMilliseconds ?? 0) / 1000.0;
    final index = _selectedBlockIndex!;
    final block = _blocks[index];

    if (time > block.startTime + 0.1 && time < block.endTime - 0.1) {
      setState(() {
        _blocks[index] = StoryBlock(characterId: block.characterId, startTime: block.startTime, endTime: time);
        _blocks.insert(index + 1, StoryBlock(characterId: block.characterId, startTime: time, endTime: block.endTime));
        _selectedBlockIndex = index + 1;
      });
      _notifyChanged();
    }
  }

  void _deleteBlock() {
    if (_selectedBlockIndex != null) {
      setState(() {
        _blocks.removeAt(_selectedBlockIndex!);
        _selectedBlockIndex = null;
      });
      _notifyChanged();
    } else if (_selectedMotionBlockIndex != null) {
      setState(() {
        _motionBlocks.removeAt(_selectedMotionBlockIndex!);
        _selectedMotionBlockIndex = null;
      });
      _notifyChanged();
    } else if (_selectedHatBlockIndex != null) {
      setState(() {
        _hatBlocks.removeAt(_selectedHatBlockIndex!);
        _selectedHatBlockIndex = null;
      });
      _notifyChanged();
    }
  }

  String? _getActiveCharacterAt(double time) {
    for (var b in _blocks) {
      if (time >= b.startTime && time <= b.endTime) return b.characterId;
    }
    return null;
  }

  String? _getActiveMotionAt(double time) {
    for (var b in _motionBlocks) {
      if (time >= b.startTime && time <= b.endTime) return b.motionId;
    }
    return null;
  }

  StoryHatBlock? _getActiveHatAt(double time) {
    for (var b in _hatBlocks) {
      if (time >= b.startTime && time <= b.endTime) return b;
    }
    return null;
  }

  void _addMotionBlockAtTime(String motionId, double timeInSeconds) {
    final totalSeconds = _totalDuration.inMilliseconds / 1000.0;
    if (totalSeconds == 0) return;

    if (timeInSeconds < 0) timeInSeconds = 0;
    double end = timeInSeconds + 3.0;
    if (end > totalSeconds) end = totalSeconds;

    final List<StoryMotionBlock> updatedBlocks = [];
    for (var b in _motionBlocks) {
      if (b.endTime <= timeInSeconds || b.startTime >= end) {
        updatedBlocks.add(b);
      } else if (b.startTime < timeInSeconds && b.endTime > end) {
        updatedBlocks.add(
          StoryMotionBlock(motionId: b.motionId, startTime: b.startTime, endTime: timeInSeconds),
        );
        updatedBlocks.add(
          StoryMotionBlock(motionId: b.motionId, startTime: end, endTime: b.endTime),
        );
      } else if (b.startTime < timeInSeconds && b.endTime <= end) {
        updatedBlocks.add(
          StoryMotionBlock(motionId: b.motionId, startTime: b.startTime, endTime: timeInSeconds),
        );
      } else if (b.startTime >= timeInSeconds && b.endTime > end) {
        updatedBlocks.add(
          StoryMotionBlock(motionId: b.motionId, startTime: end, endTime: b.endTime),
        );
      }
    }
    updatedBlocks.add(
      StoryMotionBlock(motionId: motionId, startTime: timeInSeconds, endTime: end),
    );

    setState(() {
      _motionBlocks = updatedBlocks;
      _selectedMotionBlockIndex = _motionBlocks.indexWhere((b) => b.startTime == timeInSeconds);
      _selectedBlockIndex = null;
      _selectedHatBlockIndex = null;
    });
    _notifyChanged();
  }

  void _updateMotionBlockStart(int index, double deltaSeconds) {
    final block = _motionBlocks[index];
    double newStart = block.startTime + deltaSeconds;
    if (newStart < 0) newStart = 0;
    if (newStart > block.endTime - 0.5) newStart = block.endTime - 0.5;
    if (index > 0) {
      final prevBlock = _motionBlocks[index - 1];
      if (newStart < prevBlock.endTime) newStart = prevBlock.endTime;
    }
    setState(() {
      _motionBlocks[index] = StoryMotionBlock(
        motionId: block.motionId,
        startTime: newStart,
        endTime: block.endTime,
      );
    });
    _notifyChanged();
  }

  void _updateMotionBlockEnd(int index, double deltaSeconds) {
    final block = _motionBlocks[index];
    double newEnd = block.endTime + deltaSeconds;
    final totalSeconds = _totalDuration.inMilliseconds / 1000.0;
    if (newEnd > totalSeconds) newEnd = totalSeconds;
    if (newEnd < block.startTime + 0.5) newEnd = block.startTime + 0.5;
    if (index < _motionBlocks.length - 1) {
      final nextBlock = _motionBlocks[index + 1];
      if (newEnd > nextBlock.startTime) newEnd = nextBlock.startTime;
    }
    setState(() {
      _motionBlocks[index] = StoryMotionBlock(
        motionId: block.motionId,
        startTime: block.startTime,
        endTime: newEnd,
      );
    });
    _notifyChanged();
  }

  void _moveMotionBlock(int index, double deltaSeconds) {
    final block = _motionBlocks[index];
    double newStart = block.startTime + deltaSeconds;
    double duration = block.endTime - block.startTime;
    if (newStart < 0) newStart = 0;
    final totalSeconds = _totalDuration.inMilliseconds / 1000.0;
    if (newStart + duration > totalSeconds) newStart = totalSeconds - duration;
    if (index > 0 && newStart < _motionBlocks[index - 1].endTime) {
      newStart = _motionBlocks[index - 1].endTime;
    }
    if (index < _motionBlocks.length - 1 && (newStart + duration) > _motionBlocks[index + 1].startTime) {
      newStart = _motionBlocks[index + 1].startTime - duration;
    }
    setState(() {
      _motionBlocks[index] = StoryMotionBlock(
        motionId: block.motionId,
        startTime: newStart,
        endTime: newStart + duration,
      );
    });
    _notifyChanged();
  }

  void _addHatBlockAtTime(String colorHex, double timeInSeconds) {
    final totalSeconds = _totalDuration.inMilliseconds / 1000.0;
    if (totalSeconds == 0) return;

    if (timeInSeconds < 0) timeInSeconds = 0;
    double end = timeInSeconds + 3.0;
    if (end > totalSeconds) end = totalSeconds;

    final List<StoryHatBlock> updatedBlocks = [];
    for (var b in _hatBlocks) {
      if (b.endTime <= timeInSeconds || b.startTime >= end) {
        updatedBlocks.add(b);
      } else if (b.startTime < timeInSeconds && b.endTime > end) {
        updatedBlocks.add(
          StoryHatBlock(colorHex: b.colorHex, startTime: b.startTime, endTime: timeInSeconds),
        );
        updatedBlocks.add(
          StoryHatBlock(colorHex: b.colorHex, startTime: end, endTime: b.endTime),
        );
      } else if (b.startTime < timeInSeconds && b.endTime <= end) {
        updatedBlocks.add(
          StoryHatBlock(colorHex: b.colorHex, startTime: b.startTime, endTime: timeInSeconds),
        );
      } else if (b.startTime >= timeInSeconds && b.endTime > end) {
        updatedBlocks.add(
          StoryHatBlock(colorHex: b.colorHex, startTime: end, endTime: b.endTime),
        );
      }
    }
    updatedBlocks.add(
      StoryHatBlock(colorHex: colorHex, startTime: timeInSeconds, endTime: end),
    );

    setState(() {
      _hatBlocks = updatedBlocks;
      _selectedHatBlockIndex = _hatBlocks.indexWhere((b) => b.startTime == timeInSeconds);
      _selectedBlockIndex = null;
      _selectedMotionBlockIndex = null;
    });
    _notifyChanged();
  }

  void _updateHatBlockStart(int index, double deltaSeconds) {
    final block = _hatBlocks[index];
    double newStart = block.startTime + deltaSeconds;
    if (newStart < 0) newStart = 0;
    if (newStart > block.endTime - 0.5) newStart = block.endTime - 0.5;
    if (index > 0) {
      final prevBlock = _hatBlocks[index - 1];
      if (newStart < prevBlock.endTime) newStart = prevBlock.endTime;
    }
    setState(() {
      _hatBlocks[index] = StoryHatBlock(
        colorHex: block.colorHex,
        startTime: newStart,
        endTime: block.endTime,
      );
    });
    _notifyChanged();
  }

  void _updateHatBlockEnd(int index, double deltaSeconds) {
    final block = _hatBlocks[index];
    double newEnd = block.endTime + deltaSeconds;
    final totalSeconds = _totalDuration.inMilliseconds / 1000.0;
    if (newEnd > totalSeconds) newEnd = totalSeconds;
    if (newEnd < block.startTime + 0.5) newEnd = block.startTime + 0.5;
    if (index < _hatBlocks.length - 1) {
      final nextBlock = _hatBlocks[index + 1];
      if (newEnd > nextBlock.startTime) newEnd = nextBlock.startTime;
    }
    setState(() {
      _hatBlocks[index] = StoryHatBlock(
        colorHex: block.colorHex,
        startTime: block.startTime,
        endTime: newEnd,
      );
    });
    _notifyChanged();
  }

  void _moveHatBlock(int index, double deltaSeconds) {
    final block = _hatBlocks[index];
    double newStart = block.startTime + deltaSeconds;
    double duration = block.endTime - block.startTime;
    if (newStart < 0) newStart = 0;
    final totalSeconds = _totalDuration.inMilliseconds / 1000.0;
    if (newStart + duration > totalSeconds) newStart = totalSeconds - duration;
    if (index > 0 && newStart < _hatBlocks[index - 1].endTime) {
      newStart = _hatBlocks[index - 1].endTime;
    }
    if (index < _hatBlocks.length - 1 && (newStart + duration) > _hatBlocks[index + 1].startTime) {
      newStart = _hatBlocks[index + 1].startTime - duration;
    }
    setState(() {
      _hatBlocks[index] = StoryHatBlock(
        colorHex: block.colorHex,
        startTime: newStart,
        endTime: newStart + duration,
      );
    });
    _notifyChanged();
  }
  
  void _duplicateBlock() {
    if (_selectedBlockIndex != null) {
      final block = _blocks[_selectedBlockIndex!];
      final totalSeconds = _totalDuration.inMilliseconds / 1000.0;
      final duration = block.endTime - block.startTime;
      double newStart = block.endTime;
      double newEnd = newStart + duration;
      
      if (newStart >= totalSeconds) return; 
      if (newEnd > totalSeconds) newEnd = totalSeconds;
      
      _addBlockAtTime(block.characterId, newStart);
    }
  }

  void _zoom(double factor) {
    setState(() {
      _pixelsPerSecond = (_pixelsPerSecond * factor).clamp(20.0, 300.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final totalSeconds = _totalDuration.inMilliseconds / 1000.0;
    final trackWidth = totalSeconds * _pixelsPerSecond;
    final currentTime = (widget.positionNotifier?.value.inMilliseconds ?? 0) / 1000.0;

    // Dark Mode Theme Wrapper
    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.white,
        colorScheme: const ColorScheme.light(
          surface: Colors.white,
          primary: Colors.white,
        ),
      ),
      child: Builder(builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppColors.border_radius),
            border: Border.all(color: AppColors.inputBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

              Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Embedded 3D Viewer
                    Container(
                      height: 200,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppColors.border_radius),
                        border: BoxBorder.all(color: AppColors.inputBorder)
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _getActiveCharacterAt(currentTime) != null 
                          ? SmartCharacterViewer(
                              characterName: _getActiveCharacterAt(currentTime)!,
                              isPlaying: widget.isPlaying,
                              isSpeaking: widget.isPlaying && widget.audioFile.existsSync(),
                              playbackPosition: widget.positionNotifier,
                              motion: _getActiveMotionAt(currentTime) != null 
                                  ? CharacterMotion.values.firstWhere((m) => m.name == _getActiveMotionAt(currentTime)!, orElse: () => CharacterMotion.idle) 
                                  : null,
                              showHat: _getActiveHatAt(currentTime) != null,
                              hatColor: _getActiveHatAt(currentTime)?.color ?? const Color(0xFF2C2C2E),
                            )
                          : const Center(
                              child: Text(
                                'لا توجد شخصية في هذا الوقت',
                                style: TextStyle(color: Colors.black, fontSize: 14),
                              ),
                            ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.zoom_out, color: Colors.black, size: 20),
                              onPressed: () => _zoom(0.8),
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            IconButton(
                              icon: const Icon(Icons.zoom_in, color: Colors.black, size: 20),
                              onPressed: () => _zoom(1.2),
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${_formatTime(currentTime)} / ${_formatTime(totalSeconds)}',
                              style: const TextStyle(color: Colors.black, fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      margin: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppColors.border_radius),
                        border: Border.all(color: AppColors.inputBorder),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            height: 50,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: CharacterHelper.characters.keys.map((key) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
                                  child: Draggable<String>(
                                    data: key,
                                    feedback: Material(
                                      color: Colors.transparent,
                                      child: Container(
                                        width: 80,
                                        height: _blockHeight,
                                        decoration: BoxDecoration(
                                          color: CharacterHelper.getColor(key).withOpacity(0.8),
                                          borderRadius: BorderRadius.circular(AppColors.border_radius),
                                        ),
                                        child: Center(
                                          child: Text(
                                            CharacterHelper.getCleanName(key),
                                            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ),
                                    ),
                                    childWhenDragging: Opacity(
                                      opacity: 0.3,
                                      child: _buildPaletteItem(key),
                                    ),
                                    child: _buildPaletteItem(key),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          const Divider(height: 1, color: AppColors.inputBorder),
                          SizedBox(
                            height: 50,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: CharacterMotion.values.map((motion) {
                                final isSelected = _selectedMotionBlockIndex != null && _motionBlocks.isNotEmpty && _selectedMotionBlockIndex! < _motionBlocks.length && _motionBlocks[_selectedMotionBlockIndex!].motionId == motion.name;
                                return Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
                                  child: Draggable<String>(
                                    data: motion.name,
                                    feedback: Material(
                                      color: Colors.transparent,
                                      child: Container(
                                        width: 80,
                                        height: _blockHeight,
                                        decoration: BoxDecoration(
                                          color: Colors.white, 
                                          borderRadius: BorderRadius.circular(AppColors.border_radius),
                                          border: Border.all(color: AppColors.inputBorder),
                                        ),
                                        child: Center(child: Text(motion.arabicLabel, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold))),
                                      ),
                                    ),
                                    childWhenDragging: Opacity(
                                      opacity: 0.3,
                                      child: Container(
                                        width: 80,
                                        height: _blockHeight,
                                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppColors.border_radius), border: Border.all(color: AppColors.inputBorder)),
                                        child: Center(child: Text(motion.arabicLabel, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold))),
                                      ),
                                    ),
                                    child: Container(
                                      width: 80,
                                      height: _blockHeight,
                                      decoration: BoxDecoration(
                                        color: isSelected ? Colors.teal.shade300 : Colors.white, 
                                        borderRadius: BorderRadius.circular(AppColors.border_radius), 
                                        border: Border.all(color: isSelected ? Colors.teal.shade300 : AppColors.inputBorder)
                                      ),
                                      child: Center(child: Text(motion.arabicLabel, style: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontWeight: FontWeight.bold))),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          const Divider(height: 1, color: AppColors.inputBorder),
                          SizedBox(
                            height: 50,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                                  child: Text(
                                    'قبعة',
                                    style: TextStyle(
                                      color: Colors.black54,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                ..._hatPaletteColors.map((color) {
                                  final dragData = StoryHatBlock.dragDataFor(color);
                                  final selectedHex = _selectedHatBlockIndex != null &&
                                          _selectedHatBlockIndex! < _hatBlocks.length
                                      ? _hatBlocks[_selectedHatBlockIndex!].colorHex.toLowerCase()
                                      : null;
                                  final isSelected = selectedHex ==
                                      ((color.toARGB32() & 0xFFFFFF)
                                          .toRadixString(16)
                                          .padLeft(6, '0'));
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
                                    child: Draggable<String>(
                                      data: dragData,
                                      feedback: Material(
                                        color: Colors.transparent,
                                        child: Container(
                                          width: 48,
                                          height: _blockHeight,
                                          decoration: BoxDecoration(
                                            color: color,
                                            borderRadius: BorderRadius.circular(AppColors.border_radius),
                                            border: Border.all(color: Colors.black26),
                                          ),
                                          child: const Icon(Icons.face_retouching_natural, color: Colors.white70, size: 22),
                                        ),
                                      ),
                                      childWhenDragging: Opacity(
                                        opacity: 0.3,
                                        child: _buildHatPaletteItem(color, false),
                                      ),
                                      child: _buildHatPaletteItem(color, isSelected),
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

              // Toolbar & Playback Controls
              Container(
                margin: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppColors.border_radius),
                  border: Border.all(color: AppColors.inputBorder),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Playback controls
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppColors.border_radius),
                        border: Border.all(color: AppColors.inputBorder),
                      ),
                      child: Row(
                        children: [
                          Row(
                            children: [
                              if (widget.audioPlayer != null) ...[
                                IconButton(
                                  icon: const Icon(Icons.replay, color: Colors.black, size: 20,),
                                  onPressed: () {
                                    widget.audioPlayer?.seek(Duration.zero);
                                    if (!widget.isPlaying && widget.onTogglePlay != null) widget.onTogglePlay!();
                                  },
                                ),
                                IconButton(
                                  icon: Icon(widget.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.black, size: 25),
                                  onPressed: widget.onTogglePlay,
                                ),
                              ]
                            ],
                          )
                        ],
                      ),
                    ),
                    // Editing tools
                    Row(
                      children: [
                        _buildToolButton(Icons.call_split, 'تقسيم', _selectedBlockIndex != null ? _splitBlock : null),
                        const SizedBox(width: 5),
                        _buildToolButton(Icons.copy, 'تكرار', _selectedBlockIndex != null ? _duplicateBlock : null),
                        const SizedBox(width: 5),
                        _buildToolButton(
                          Icons.delete_outline,
                          'حذف',
                          (_selectedBlockIndex != null ||
                                  _selectedMotionBlockIndex != null ||
                                  _selectedHatBlockIndex != null)
                              ? _deleteBlock
                              : null,
                          isDestructive: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Timeline Track Area
              Directionality(
                textDirection: TextDirection.ltr,
                child: SizedBox(
                  height: 320,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SizedBox(
                      width: trackWidth,
                      child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppColors.border_radius),
                        border: Border.all(color: AppColors.inputBorder),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // Ruler marks
                            for (double s = 0; s <= totalSeconds; s += 1)
                              Positioned(
                                left: s * _pixelsPerSecond,
                                top: 0,
                                bottom: 0,
                                child: Container(
                                  width: 1,
                                  color: s % 5 == 0 ? Colors.white30 : Colors.white10,
                                  child: s % 5 == 0
                                      ? Transform.translate(
                                          offset: const Offset(4, 2),
                                          child: Text('${s.toInt()}s', style: const TextStyle(fontSize: 10, color: Colors.white54)),
                                        )
                                      : null,
                                ),
                              ),

                            // Audio Waveform Track
                            Positioned(
                              left: 0,
                              top: 25,
                              width: trackWidth,
                              height: _waveformHeight,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(AppColors.border_radius),
                                  border: BoxBorder.all(
                                    color: AppColors.inputBorder
                                  )
                                ),
                                child: CustomPaint(
                                  painter: _WaveformPainter(
                                    duration: totalSeconds,
                                    seed: widget.audioFile.path.hashCode,
                                  ),
                                ),
                              ),
                            ),

                            // Character Blocks Track
                            Positioned(
                              left: 0,
                              top: 25 + _waveformHeight + 5,
                              width: trackWidth,
                              height: _trackHeight,
                              child: DragTarget<String>(
                                onAcceptWithDetails: (details) {
                                  if (CharacterHelper.characters.keys.contains(details.data)) {
                                    if (_trackKey.currentContext != null) {
                                      final RenderBox box = _trackKey.currentContext!.findRenderObject() as RenderBox;
                                      final Offset localOffset = box.globalToLocal(details.offset);
                                      final double time = localOffset.dx / _pixelsPerSecond;
                                      _addBlockAtTime(details.data, time);
                                    }
                                  }
                                },
                                builder: (context, candidateData, rejectedData) {
                                  return Container(
                                    key: _trackKey,
                                    decoration: BoxDecoration(
                                      color: candidateData.isNotEmpty ? Colors.blue.withOpacity(0.2) : Colors.white.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(AppColors.border_radius),
                                      border: Border.all(color: candidateData.isNotEmpty ? Colors.blue : Colors.transparent, width: 2),
                                    ),
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: _blocks.asMap().entries.map((entry) {
                                        return _buildTimelineBlock(entry.key, entry.value);
                                      }).toList(),
                                    ),
                                  );
                                },
                              ),
                            ),

                            // Motion Blocks Track
                            Positioned(
                              left: 0,
                              top: 25 + _waveformHeight + 5 + _trackHeight + 5,
                              width: trackWidth,
                              height: _trackHeight,
                              child: DragTarget<String>(
                                onAcceptWithDetails: (details) {
                                  if (CharacterMotion.values.any((m) => m.name == details.data)) {
                                    if (_motionTrackKey.currentContext != null) {
                                      final RenderBox box = _motionTrackKey.currentContext!.findRenderObject() as RenderBox;
                                      final Offset localOffset = box.globalToLocal(details.offset);
                                      final double time = localOffset.dx / _pixelsPerSecond;
                                      _addMotionBlockAtTime(details.data, time);
                                    }
                                  }
                                },
                                builder: (context, candidateData, rejectedData) {
                                  return Container(
                                    key: _motionTrackKey,
                                    decoration: BoxDecoration(
                                      color: candidateData.isNotEmpty ? Colors.teal.withOpacity(0.2) : Colors.white.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(AppColors.border_radius),
                                      border: Border.all(color: candidateData.isNotEmpty ? Colors.teal : Colors.transparent, width: 2),
                                    ),
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: _motionBlocks.asMap().entries.map((entry) {
                                        return _buildMotionBlockWidget(entry.key, entry.value);
                                      }).toList(),
                                    ),
                                  );
                                },
                              ),
                            ),

                            // Hat Blocks Track
                            Positioned(
                              left: 0,
                              top: 25 + _waveformHeight + 5 + (_trackHeight + 5) * 2,
                              width: trackWidth,
                              height: _trackHeight,
                              child: DragTarget<String>(
                                onAcceptWithDetails: (details) {
                                  final hex = StoryHatBlock.colorHexFromDrag(details.data);
                                  if (hex == null) return;
                                  if (_hatTrackKey.currentContext != null) {
                                    final RenderBox box = _hatTrackKey.currentContext!.findRenderObject() as RenderBox;
                                    final Offset localOffset = box.globalToLocal(details.offset);
                                    final double time = localOffset.dx / _pixelsPerSecond;
                                    _addHatBlockAtTime(hex, time);
                                  }
                                },
                                builder: (context, candidateData, rejectedData) {
                                  final canAccept = candidateData
                                      .whereType<String>()
                                      .any((d) => StoryHatBlock.colorHexFromDrag(d) != null);
                                  return Container(
                                    key: _hatTrackKey,
                                    decoration: BoxDecoration(
                                      color: canAccept ? Colors.deepOrange.withOpacity(0.2) : Colors.white.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(AppColors.border_radius),
                                      border: Border.all(color: canAccept ? Colors.deepOrange : Colors.transparent, width: 2),
                                    ),
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: _hatBlocks.asMap().entries.map((entry) {
                                        return _buildHatBlockWidget(entry.key, entry.value);
                                      }).toList(),
                                    ),
                                  );
                                },
                              ),
                            ),

                            // Playhead
                            if (widget.positionNotifier != null)
                              Positioned(
                                left: currentTime * _pixelsPerSecond,
                                top: 0,
                                bottom: 0,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onHorizontalDragUpdate: (details) {
                                    if (widget.audioPlayer != null) {
                                      final RenderBox? box = _trackKey.currentContext?.findRenderObject() as RenderBox?;
                                      if (box != null) {
                                        final localOffset = box.globalToLocal(details.globalPosition);
                                        double time = localOffset.dx / _pixelsPerSecond;
                                        if (time < 0) time = 0;
                                        if (time > totalSeconds) time = totalSeconds;
                                        widget.audioPlayer!.seek(Duration(milliseconds: (time * 1000).toInt()));
                                      }
                                    }
                                  },
                                  child: Container(
                                    width: 60,
                                    transform: Matrix4.translationValues(-30, 0, 0), // center the 60px container
                                    child: Column(
                                      children: [
                                        Container(
                                          width: 22,
                                          height: 22,
                                          decoration: const BoxDecoration(
                                            color: Colors.black,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black26, 
                                                blurRadius: 4, 
                                                offset: Offset(0, 2)
                                              )
                                            ],
                                          ),
                                        ),
                                        Expanded(
                                          child: Container(
                                            width: 2.5,
                                            decoration: const BoxDecoration(
                                              color: Colors.black87,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              ),
            ]
          )
        );
      }),
    );
  }

  Widget _buildPaletteItem(String key) {
    return Container(
      width: 60,
      decoration: BoxDecoration(
        color: CharacterHelper.getColor(key),
        borderRadius: BorderRadius.circular(AppColors.border_radius),
        border: Border.all(color: AppColors.inputBorder),
      ),
      child: Center(
        child: Text(
          CharacterHelper.getCleanName(key),
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildHatPaletteItem(Color color, bool isSelected) {
    return Container(
      width: 48,
      height: _blockHeight,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppColors.border_radius),
        border: Border.all(
          color: isSelected ? Colors.deepOrange : AppColors.inputBorder,
          width: isSelected ? 2.5 : 1,
        ),
      ),
      child: Icon(
        Icons.face_retouching_natural,
        color: color.computeLuminance() > 0.55 ? Colors.black54 : Colors.white70,
        size: 22,
      ),
    );
  }

  Widget _buildToolButton(IconData icon, String label, VoidCallback? onPressed, {bool isDestructive = false}) {
    final color = onPressed == null 
        ? Colors.black
        : (isDestructive ? Colors.redAccent : Colors.black);
    
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(AppColors.border_radius),
      child: Container(
       decoration: BoxDecoration(
         color: Colors.white,
         borderRadius: BorderRadius.circular(AppColors.border_radius),
         border: Border.all(color: AppColors.inputBorder),
       ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 5),
          child: Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(color: color, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimelineBlock(int index, StoryBlock block) {
    final left = block.startTime * _pixelsPerSecond;
    final width = (block.endTime - block.startTime) * _pixelsPerSecond;
    final isSelected = _selectedBlockIndex == index;

    return Positioned(
      left: left,
      top: 5,
      width: width,
      height: _blockHeight,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedBlockIndex = index;
            _selectedMotionBlockIndex = null;
            _selectedHatBlockIndex = null;
          });
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Main Body
            GestureDetector(
              onHorizontalDragUpdate: (details) {
                _moveBlock(index, details.delta.dx / _pixelsPerSecond);
              },
              child: Container(
                decoration: BoxDecoration(
                  color: CharacterHelper.getColor(block.characterId).withOpacity(0.9),
                  borderRadius: BorderRadius.circular(AppColors.border_radius),
                  border: Border.all(
                    color: isSelected ? AppColors.inputBorder : Colors.black54,
                    width: isSelected ? 2.5 : 1.0,
                  ),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                ),
                child: Center(
                  child: Text(
                    CharacterHelper.getCleanName(block.characterId),
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            
            // Handles only show when selected
            if (isSelected) ...[
              // Left Handle
              Positioned(
                left: -10,
                top: 0,
                bottom: 0,
                width: 20,
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    _updateBlockStart(index, details.delta.dx / _pixelsPerSecond);
                  },
                  child: Container(
                    color: Colors.transparent,
                    child: Center(
                      child: Container(
                        width: 10,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 2)],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Right Handle
              Positioned(
                right: -10,
                top: 0,
                bottom: 0,
                width: 20,
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    _updateBlockEnd(index, details.delta.dx / _pixelsPerSecond);
                  },
                  child: Container(
                    color: Colors.transparent,
                    child: Center(
                      child: Container(
                        width: 10,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 2)],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
  Widget _buildMotionBlockWidget(int index, StoryMotionBlock block) {
    final left = block.startTime * _pixelsPerSecond;
    final width = (block.endTime - block.startTime) * _pixelsPerSecond;
    final isSelected = _selectedMotionBlockIndex == index;

    final motion = CharacterMotion.values.firstWhere((m) => m.name == block.motionId, orElse: () => CharacterMotion.idle);

    return Positioned(
      left: left,
      top: 5,
      width: width,
      height: _blockHeight,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedMotionBlockIndex = index;
            _selectedBlockIndex = null;
            _selectedHatBlockIndex = null;
          });
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Main Body
            GestureDetector(
              onHorizontalDragUpdate: (details) {
                _moveMotionBlock(index, details.delta.dx / _pixelsPerSecond);
              },
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.teal.shade300,
                  borderRadius: BorderRadius.circular(AppColors.border_radius),
                  border: Border.all(
                    color: isSelected ? Colors.teal.shade800 : Colors.teal.shade400,
                    width: isSelected ? 2.5 : 1.0,
                  ),
                  boxShadow: const [BoxShadow(color: Colors.teal, blurRadius: 4, offset: Offset(0, 2))],
                ),
                child: Center(
                  child: Text(
                    motion.arabicLabel,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),

            // Start Drag Handle
            if (isSelected)
              Positioned(
                left: -10,
                top: 0,
                bottom: 0,
                width: 20,
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    _updateMotionBlockStart(index, details.delta.dx / _pixelsPerSecond);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.black, width: 0.5),
                    ),
                    child: const Icon(Icons.drag_indicator, size: 12, color: Colors.black),
                  ),
                ),
              ),
            
            // End Drag Handle
            if (isSelected)
              Positioned(
                right: -10,
                top: 0,
                bottom: 0,
                width: 20,
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    _updateMotionBlockEnd(index, details.delta.dx / _pixelsPerSecond);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.black, width: 0.5),
                    ),
                    child: const Icon(Icons.drag_indicator, size: 12, color: Colors.black),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHatBlockWidget(int index, StoryHatBlock block) {
    final left = block.startTime * _pixelsPerSecond;
    final width = (block.endTime - block.startTime) * _pixelsPerSecond;
    final isSelected = _selectedHatBlockIndex == index;
    final labelColor =
        block.color.computeLuminance() > 0.55 ? Colors.black87 : Colors.white;

    return Positioned(
      left: left,
      top: 5,
      width: width,
      height: _blockHeight,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedHatBlockIndex = index;
            _selectedBlockIndex = null;
            _selectedMotionBlockIndex = null;
          });
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            GestureDetector(
              onHorizontalDragUpdate: (details) {
                _moveHatBlock(index, details.delta.dx / _pixelsPerSecond);
              },
              child: Container(
                decoration: BoxDecoration(
                  color: block.color,
                  borderRadius: BorderRadius.circular(AppColors.border_radius),
                  border: Border.all(
                    color: isSelected ? Colors.deepOrange : Colors.black54,
                    width: isSelected ? 2.5 : 1.0,
                  ),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                  ],
                ),
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.face_retouching_natural, size: 14, color: labelColor),
                      const SizedBox(width: 4),
                      Text(
                        'قبعة',
                        style: TextStyle(
                          color: labelColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (isSelected)
              Positioned(
                left: -10,
                top: 0,
                bottom: 0,
                width: 20,
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    _updateHatBlockStart(index, details.delta.dx / _pixelsPerSecond);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.black, width: 0.5),
                    ),
                    child: const Icon(Icons.drag_indicator, size: 12, color: Colors.black),
                  ),
                ),
              ),
            if (isSelected)
              Positioned(
                right: -10,
                top: 0,
                bottom: 0,
                width: 20,
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    _updateHatBlockEnd(index, details.delta.dx / _pixelsPerSecond);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.black, width: 0.5),
                    ),
                    child: const Icon(Icons.drag_indicator, size: 12, color: Colors.black),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final double duration;
  final int seed;

  _WaveformPainter({required this.duration, required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width == 0 || size.height == 0) return;

    final paint = Paint()
      ..color = Colors.blueAccent.withOpacity(0.8)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final random = Random(seed);
    final int points = (size.width / 4).floor(); // 1 line every 4 pixels

    for (int i = 0; i < points; i++) {
      final x = i * 4.0;
      // Add a slight envelope based on sine wave to make it look like speech
      final envelope = (sin(i / points * pi * 8) + 1.0) / 2.0; 
      final noise = random.nextDouble();
      
      final magnitude = (noise * 0.8 + 0.2) * envelope * size.height;
      final y1 = (size.height - magnitude) / 2;
      final y2 = y1 + magnitude;

      canvas.drawLine(Offset(x, y1), Offset(x, y2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
