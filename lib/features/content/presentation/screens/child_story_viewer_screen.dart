import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../../../core/widgets/smart_character_viewer.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/services/resource_manager.dart';
import '../../domain/entities/mission_entity.dart';
import '../../domain/entities/story_entity.dart';
import '../bloc/content_bloc.dart';
import '../bloc/content_event.dart';
import '../bloc/content_state.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/utils/character_helper.dart';
import '../../../../core/widgets/shimmer_loading.dart';
import 'dart:convert';
import '../../../../core/models/story_timeline.dart';
import '../../../../core/animation/story_motion.dart';

class ChildStoryViewerScreen extends StatefulWidget {
  final MissionEntity mission;

  const ChildStoryViewerScreen({super.key, required this.mission});

  @override
  State<ChildStoryViewerScreen> createState() => _ChildStoryViewerScreenState();
}

class _ChildStoryViewerScreenState extends State<ChildStoryViewerScreen>
    with WidgetsBindingObserver {
  late ContentBloc _contentBloc;

  List<StoryEntity> _stories = [];
  int _currentIndex = 0;

  // Audio Player and Progress
  AudioPlayer? _audioPlayer;
  final List<StreamSubscription<dynamic>> _audioSubscriptions = [];
  Future<void> _audioCommands = Future<void>.value();
  final ValueNotifier<Duration> _positionNotifier = ValueNotifier<Duration>(
    Duration.zero,
  );
  bool _isPlaying = false;
  Duration _totalDuration = const Duration(seconds: 10); // default if no audio
  bool _hasAudio = false;
  bool _isMuted = false;
  bool _playRequested = true;
  bool _isAppActive = true;
  bool _audioCompleted = false;
  bool _leaving = false;
  int _sceneGeneration = 0;
  StoryTimeline? _currentTimeline;

  Timer? _fallbackTimer;
  final Stopwatch _fallbackClock = Stopwatch();
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _isAppActive = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _contentBloc = sl<ContentBloc>();
    _contentBloc.add(
      ContentEvent.getStories(widget.mission.id),
    );
  }

  bool _isCurrentScene(int generation) =>
      mounted && !_leaving && generation == _sceneGeneration;

  void _listenToAudio(AudioPlayer player, int generation) {
    _audioSubscriptions.addAll([
      player.onDurationChanged.listen((duration) {
        if (_isCurrentScene(generation) && duration > Duration.zero) {
          setState(() => _totalDuration = duration);
        }
      }, onError: (Object error) => _onAudioError(error, generation)),
      player.onPositionChanged.listen((position) {
        if (_isCurrentScene(generation) && _hasAudio) {
          _positionNotifier.value = position;
        }
      }, onError: (Object error) => _onAudioError(error, generation)),
      player.onPlayerStateChanged.listen((state) {
        if (_isCurrentScene(generation) && _hasAudio) {
          setState(() {
            _isPlaying =
                state == PlayerState.playing && _playRequested && _isAppActive;
          });
          if (_isPlaying) {
            _startPositionPolling(player, generation);
          }
        }
      }),
      player.onPlayerComplete.listen((_) {
        if (!_isCurrentScene(generation) || !_hasAudio) return;
        _audioCompleted = true;
        if (_playRequested && _isAppActive) {
          _nextStory();
        } else {
          setState(() => _isPlaying = false);
        }
      }, onError: (Object error) => _onAudioError(error, generation)),
    ]);
  }

  void _startPositionPolling(AudioPlayer player, int generation) {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 100), (
      timer,
    ) async {
      if (!mounted || !_isPlaying || !_isCurrentScene(generation)) {
        timer.cancel();
        return;
      }
      try {
        final pos = await player.getCurrentPosition();
        if (pos != null && _hasAudio) {
          _positionNotifier.value = pos;
        }
      } catch (_) {}
    });
  }

  void _onAudioError(Object error, int generation) {
    // Preparation errors are handled by _loadAudio, which tries the next source.
    if (_isCurrentScene(generation) && _hasAudio) {
      debugPrint('Story audio stream failed: $error');
      _startFallbackTimer(generation);
    }
  }

  void _detachAudio() {
    for (final subscription in _audioSubscriptions) {
      unawaited(subscription.cancel());
    }
    _audioSubscriptions.clear();
    _pollingTimer?.cancel();
    final player = _audioPlayer;
    _audioPlayer = null;
    _audioCommands = Future<void>.value();
    if (player != null) unawaited(_disposePlayer(player));
  }

  Future<void> _disposePlayer(AudioPlayer player) async {
    try {
      await player.dispose();
    } catch (error) {
      debugPrint('Story audio disposal failed: $error');
    }
  }

  void _startStory() {
    if (!mounted || _leaving || _stories.isEmpty) return;
    final generation = ++_sceneGeneration;
    _fallbackTimer?.cancel();
    _fallbackClock
      ..stop()
      ..reset();
    _detachAudio();
    setState(() {
      _isCharacterReady = false;
      _playRequested = true;
      _isPlaying = false;
      _hasAudio = false;
      _audioCompleted = false;
      _totalDuration = const Duration(seconds: 10);
    });
    _positionNotifier.value = Duration.zero;

    final currentStory = _stories[_currentIndex];
    final audioUrl = currentStory.audioUrl?.trim() ?? '';
    if (currentStory.timelineData != null) {
      try {
        _currentTimeline = StoryTimeline.fromJson(
          jsonDecode(currentStory.timelineData!),
        );
      } catch (e, stack) {
        debugPrint('Error parsing timeline data: $e\n$stack');
        _currentTimeline = null;
      }
    } else {
      _currentTimeline = null;
    }

    // Pre-cache next scene's audio in the background for instant transition
    if (_currentIndex + 1 < _stories.length) {
      final nextStory = _stories[_currentIndex + 1];
      final nextAudio = nextStory.audioUrl?.trim() ?? '';
      if (nextAudio.startsWith('http')) {
        sl<ResourceManager>().downloadAndCacheInBackground(
          nextAudio,
          folder: 'audio',
        );
      }
    }

    if (audioUrl.isEmpty) {
      _startFallbackTimer(generation);
      return;
    }

    // Each scene owns its player so a delayed load cannot replace new audio.
    final player = AudioPlayer();
    _audioPlayer = player;
    _listenToAudio(player, generation);
    unawaited(_loadAudio(player, audioUrl, generation));
  }

  Future<void> _loadAudio(
    AudioPlayer player,
    String audioUrl,
    int generation,
  ) async {
    final resourceManager = sl<ResourceManager>();
    final localPath = resourceManager.getLocalFilePath(audioUrl);
    final sources = <Source>[
      if (localPath != null) DeviceFileSource(localPath),
      if (audioUrl.startsWith('http')) UrlSource(audioUrl),
    ];
    for (final source in sources) {
      try {
        await player.setSource(source);
        if (!_isCurrentScene(generation)) return;
        await player.setVolume(_isMuted ? 0 : 1);
        if (!_isCurrentScene(generation)) return;
        setState(() => _hasAudio = true);
        _syncPlayback();
        resourceManager.downloadAndCacheInBackground(audioUrl, folder: 'audio');
        return;
      } catch (error) {
        if (!_isCurrentScene(generation)) return;
        debugPrint('Story audio source unavailable: $error');
      }
    }
    if (_isCurrentScene(generation)) _startFallbackTimer(generation);
  }

  bool _isCharacterReady = false;

  void _startFallbackTimer(int generation) {
    if (!_isCurrentScene(generation)) return;
    _detachAudio();
    _fallbackTimer?.cancel();
    _fallbackClock
      ..stop()
      ..reset();
    setState(() {
      _hasAudio = false;
      _totalDuration = _currentTimeline != null
          ? Duration(
              milliseconds: (_currentTimeline!.totalDuration * 1000).round(),
            )
          : const Duration(seconds: 10);
      _isPlaying = _playRequested && _isAppActive && _isCharacterReady;
    });
    if (_isPlaying) _fallbackClock.start();
    _positionNotifier.value = Duration.zero;
    _fallbackTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!_isCurrentScene(generation)) {
        timer.cancel();
        return;
      }
      if (!_isPlaying) return;
      final next = _fallbackClock.elapsed;
      _positionNotifier.value = next > _totalDuration ? _totalDuration : next;
      if (next >= _totalDuration) {
        timer.cancel();
        _nextStory();
      }
    });
  }

  void _queueAudioCommand(Future<void> Function(AudioPlayer) command) {
    final player = _audioPlayer;
    final generation = _sceneGeneration;
    if (player == null) return;
    _audioCommands = _audioCommands.then((_) async {
      if (!_isCurrentScene(generation) || player != _audioPlayer) return;
      try {
        await command(player);
      } catch (error) {
        if (_isCurrentScene(generation) && player == _audioPlayer) {
          debugPrint('Story audio playback failed: $error');
          _startFallbackTimer(generation);
        }
      }
    });
  }

  void _syncPlayback() {
    if (!mounted || _leaving) return;
    final shouldPlay = _playRequested && _isAppActive && _isCharacterReady;
    if (_hasAudio) {
      if (!shouldPlay) setState(() => _isPlaying = false);
      _queueAudioCommand((player) async {
        if (shouldPlay) {
          if (_audioCompleted) {
            _nextStory();
          } else {
            await player.resume();
          }
        } else {
          await player.pause();
        }
      });
    } else if (_fallbackTimer?.isActive ?? false) {
      setState(() => _isPlaying = shouldPlay);
      if (shouldPlay) {
        _fallbackClock.start();
      } else {
        _fallbackClock.stop();
      }
    }
  }

  void _togglePlayPause() {
    setState(() => _playRequested = !_playRequested);
    _syncPlayback();
  }

  void _onCharacterReady(int generation) {
    if (!_isCurrentScene(generation)) return;
    setState(() => _isCharacterReady = true);
    _syncPlayback();
  }

  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
    _queueAudioCommand((player) => player.setVolume(_isMuted ? 0 : 1));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isAppActive = state == AppLifecycleState.resumed;
    _syncPlayback();
  }

  void _restartMission() {
    setState(() {
      _currentIndex = 0;
    });
    _startStory();
  }

  void _nextStory() {
    if (!mounted || _leaving) return;
    if (_currentIndex < _stories.length - 1) {
      setState(() {
        _currentIndex++;
      });
      _startStory();
    } else {
      // Finished all stories
      _stopPlayback();
      context.pushReplacement('/child/quiz-intro', extra: widget.mission);
    }
  }

  void _previousStory() {
    if (!mounted || _leaving) return;
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
      });
      _startStory();
    }
  }

  void _stopPlayback() {
    _leaving = true;
    ++_sceneGeneration;
    _playRequested = false;
    _isPlaying = false;
    _fallbackTimer?.cancel();
    _fallbackClock.stop();
    _detachAudio();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPlayback();
    _positionNotifier.dispose();
    unawaited(_contentBloc.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _contentBloc,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFE0F7FA), // Light Blue
                Color(0xFFF3E5F5), // Light Purple
                Color(0xFFFFF3E0), // Light Orange
              ],
            ),
          ),
          child: SafeArea(
            top: true,
            bottom: true,
            child: BlocConsumer<ContentBloc, ContentState>(
              listener: (context, state) {
                state.maybeWhen(
                  storiesLoaded: (stories) {
                    if (stories.isNotEmpty) {
                      setState(() {
                        _stories = stories;
                        _currentIndex = 0;
                      });
                      _startStory();
                    }
                  },
                  orElse: () {},
                );
              },
              builder: (context, state) {
                return state.maybeWhen(
                  loading: () => const ShimmerLoading(type: ShimmerType.card),
                  error: (msg) => Center(
                    child: Text(
                      'خطأ: $msg',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                  storiesLoaded: (stories) {
                    if (stories.isEmpty) {
                      return const Center(
                        child: Text(
                          'لا توجد قصص في هذه المهمة بعد.',
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      );
                    }

                    final story = _stories[_currentIndex];

                    return Column(
                      children: [
                        // Top Bar (Segmented Progress + Title + Back Button)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 8.0,
                          ),
                          child: Column(
                            children: [
                              // Progress Bars
                              Row(
                                children: List.generate(_stories.length, (
                                  index,
                                ) {
                                  return Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 2.0,
                                      ),
                                      child: _buildProgressBar(
                                        index,
                                        CharacterHelper.getColor(
                                          story.characterName,
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              ),
                              const SizedBox(height: 16),
                              // Header
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  // Action Buttons (Left)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(
                                        AppColors.border_radius,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.05,
                                          ),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: const Text(
                                      'مغامرة',
                                      style: TextStyle(
                                        color: Color(0xFF2C3E50),
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  // Title & Scene Text
                                  Column(
                                    children: [
                                      Text(
                                        widget.mission.title,
                                        style: const TextStyle(
                                          color: Color(0xFF2C3E50),
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      Text(
                                        'مشهد ${_currentIndex + 1} من ${_stories.length}',
                                        style: const TextStyle(
                                          color: Colors.black54,
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  // Back Button (Right)
                                  GestureDetector(
                                    onTap: () {
                                      _stopPlayback();
                                      context.pop();
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(
                                          AppColors.border_radius,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.05,
                                            ),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: const Text(
                                        'رجوع',
                                        style: TextStyle(
                                          color: Color(0xFF2C3E50),
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 8),

                        // Subtitles (Outside, Top)
                        if (story.content.trim().isNotEmpty)
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(
                                color: AppColors.inputBorder,
                                width: 1.5,
                              ),
                              borderRadius: BorderRadius.circular(
                                AppColors.border_radius,
                              ),
                            ),
                            width: double.infinity,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 80),
                              child: SingleChildScrollView(
                                child: Text(
                                  story.content,
                                  style: const TextStyle(
                                    color: AppColors.secondary,
                                    fontSize: 16,
                                    height: 1.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                  textDirection: TextDirection.rtl,
                                ),
                              ),
                            ),
                          ),

                        if (story.content.trim().isNotEmpty)
                          const SizedBox(height: 8),

                        // Interactive Tap Areas & 3D Character
                        Expanded(
                          child: ValueListenableBuilder<Duration>(
                            valueListenable: _positionNotifier,
                            builder: (context, position, child) {
                              String activeChar = story.characterName;
                              CharacterMotion? activeMotion;
                              var showHat = false;
                              var hatColor = const Color(0xFF2C2C2E);
                              if (_currentTimeline != null) {
                                final t = position.inMilliseconds / 1000.0;
                                activeChar =
                                    _currentTimeline!.getActiveCharacterAt(t) ??
                                    (_currentTimeline!.blocks.isNotEmpty
                                        ? _currentTimeline!
                                              .blocks
                                              .first
                                              .characterId
                                        : story.characterName);
                                final motionId = _currentTimeline!
                                    .getActiveMotionAt(t);
                                if (motionId != null) {
                                  activeMotion = CharacterMotion.values
                                      .firstWhere(
                                        (m) => m.name == motionId,
                                        orElse: () => CharacterMotion.idle,
                                      );
                                }
                                final hat = _currentTimeline!.getActiveHatAt(t);
                                if (hat != null) {
                                  showHat = true;
                                  hatColor = hat.color;
                                }
                              }

                              return Column(
                                children: [
                                  Expanded(
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(
                                          AppColors.border_radius,
                                        ),
                                        border: Border.all(
                                          color: AppColors.inputBorder,
                                          width: 1.5,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: CharacterHelper.getColor(
                                              activeChar,
                                            ).withValues(alpha: 0.2),
                                            blurRadius: 10,
                                            offset: const Offset(0, 5),
                                          ),
                                        ],
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(
                                          AppColors.border_radius,
                                        ),
                                        child: Stack(
                                          children: [
                                            // 3D Character Viewer (Full area)
                                            Positioned.fill(
                                              child: RepaintBoundary(
                                                child: SmartCharacterViewer(
                                                  characterName: activeChar,
                                                  storyText:
                                                      '${story.title}\n${story.content}',
                                                  isPlaying: _isPlaying,
                                                  isSpeaking:
                                                      _hasAudio && _isPlaying,
                                                  playbackPosition:
                                                      _positionNotifier,
                                                  motion: activeMotion,
                                                  showHat: showHat,
                                                  hatColor: hatColor,
                                                  onReady: () => _onCharacterReady(_sceneGeneration),
                                                ),
                                              ),
                                            ),

                                            // Character Name (Top Center)
                                            Positioned(
                                              top: 16,
                                              left: 0,
                                              right: 0,
                                              child: Center(
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 8,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.transparent,
                                                    border: Border.all(
                                                      color: AppColors.inputBorder,
                                                      width: 1.5,
                                                    ),
                                                    borderRadius: BorderRadius.circular(
                                                      AppColors.border_radius,
                                                    ),
                                                  ),
                                                  child: Text(
                                                    CharacterHelper.getCleanName(activeChar),
                                                    style: const TextStyle(
                                                      color: AppColors.secondary,
                                                      fontSize: 16,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),

                                            // Previous Button (Right Side)
                                            Positioned(
                                              right: 0,
                                              top: 0,
                                              bottom: 0,
                                              width: 50,
                                              child: GestureDetector(
                                                onTap: _currentIndex > 0 ? _previousStory : null,
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    gradient: LinearGradient(
                                                      begin: Alignment.centerRight,
                                                      end: Alignment.centerLeft,
                                                      colors: [
                                                        CharacterHelper.getColor(activeChar).withValues(alpha: 0.5),
                                                        CharacterHelper.getColor(activeChar).withValues(alpha: 0.0),
                                                      ],
                                                    ),
                                                  ),
                                                  child: Center(
                                                    child: _currentIndex > 0 
                                                        ? const Icon(
                                                            Icons.chevron_left,
                                                            color: Colors.black,
                                                            size: 40,
                                                          )
                                                        : const SizedBox(),
                                                  ),
                                                ),
                                              ),
                                            ),

                                            // Next Button (Left Side)
                                            Positioned(
                                              left: 0,
                                              top: 0,
                                              bottom: 0,
                                              width: 50,
                                              child: GestureDetector(
                                                onTap: _nextStory,
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    gradient: LinearGradient(
                                                      begin: Alignment.centerLeft,
                                                      end: Alignment.centerRight,
                                                      colors: [
                                                        CharacterHelper.getColor(activeChar).withValues(alpha: 0.5),
                                                        CharacterHelper.getColor(activeChar).withValues(alpha: 0.0),
                                                      ],
                                                    ),
                                                  ),
                                                  child: const Center(
                                                    child: Icon(
                                                      Icons.chevron_right,
                                                      color: Colors.black,
                                                      size: 40,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),



                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  // Video Player Controls (Bottom)
                                  Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 16),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(AppColors.border_radius),
                                      border: Border.all(
                                        color: AppColors.inputBorder,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        // Replay Button
                                        IconButton(
                                          style: IconButton.styleFrom(
                                            backgroundColor: Colors.grey.shade200,
                                          ),
                                          icon: const Icon(
                                            Icons.replay,
                                            color: AppColors.secondary,
                                            size: 28,
                                          ),
                                          onPressed: _restartMission,
                                        ),
                                        const SizedBox(width: 24),
                                        // Play/Pause Button
                                        IconButton(
                                          style: IconButton.styleFrom(
                                            backgroundColor: Colors.grey.shade200,
                                            padding: const EdgeInsets.all(12),
                                          ),
                                          icon: Icon(
                                            (_audioPlayer != null && !_hasAudio ? _playRequested : _isPlaying)
                                                ? Icons.pause
                                                : Icons.play_arrow,
                                            color: AppColors.secondary,
                                            size: 32,
                                          ),
                                          onPressed: _togglePlayPause,
                                        ),
                                        const SizedBox(width: 24),
                                        // Mute Button
                                        if (_hasAudio)
                                          IconButton(
                                            style: IconButton.styleFrom(
                                              backgroundColor: Colors.grey.shade200,
                                            ),
                                            icon: Icon(
                                              _isMuted ? Icons.volume_off : Icons.volume_up,
                                              color: AppColors.secondary,
                                              size: 28,
                                            ),
                                            onPressed: _toggleMute,
                                          )
                                        else
                                          const SizedBox(width: 44),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  // Bottom Action Button
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16.0,
                                      vertical: 8.0,
                                    ),
                                    child: SizedBox(
                                      width: double.infinity,
                                      height: 56,
                                      child: FilledButton(
                                        onPressed: _nextStory,
                                        style: FilledButton.styleFrom(
                                          backgroundColor:
                                              CharacterHelper.getColor(
                                                activeChar,
                                              ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              AppColors.border_radius,
                                            ),
                                          ),
                                        ),
                                        child: Text(
                                          _currentIndex < _stories.length - 1
                                              ? 'متابعة المشهد'
                                              : 'إنهاء القصة والتحدي',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: CharacterHelper.getColor(activeChar).computeLuminance() > 0.5 ? Colors.black : Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                  orElse: () => const SizedBox(),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBar(int index, Color charColor) {
    if (index < _currentIndex) {
      return Container(
        height: 6,
        decoration: BoxDecoration(
          color: charColor,
          borderRadius: BorderRadius.circular(AppColors.border_radius),
        ),
      );
    } else if (index > _currentIndex) {
      return Container(
        height: 6,
        decoration: BoxDecoration(
          color: const Color(0x1A000000),
          borderRadius: BorderRadius.circular(AppColors.border_radius),
        ),
      );
    }

    return ValueListenableBuilder<Duration>(
      valueListenable: _positionNotifier,
      builder: (context, pos, _) {
        double percent = 0.0;
        if (_totalDuration.inMilliseconds > 0) {
          percent = (pos.inMilliseconds / _totalDuration.inMilliseconds).clamp(
            0.0,
            1.0,
          );
        }

        return Container(
          height: 6,
          decoration: BoxDecoration(
            color: const Color(0x1A000000),
            borderRadius: BorderRadius.circular(AppColors.border_radius),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppColors.border_radius),
            child: LinearProgressIndicator(
              value: percent,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(charColor),
            ),
          ),
        );
      },
    );
  }
}
