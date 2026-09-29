import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/di/injection_container.dart';
import '../../../content/domain/entities/mission_entity.dart';
import '../../../content/domain/entities/story_entity.dart';
import '../../../content/presentation/bloc/content_bloc.dart';
import '../../../content/presentation/bloc/content_event.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:async';
import 'dart:convert';
import '../../../content/presentation/bloc/content_state.dart';
import '../../../../core/utils/character_helper.dart';
import '../../../../core/models/story_timeline.dart';
import '../../../../core/widgets/story_timeline_editor.dart';
import '../../../../core/audio/story_sentence_voice.dart';
import '../../../../core/services/resource_manager.dart';
import '../../../../core/widgets/admin_voice_field.dart';

class _SentenceLine {
  _SentenceLine() {
    controller.addListener(_onText);
  }

  final controller = TextEditingController();
  String characterId = 'fort';
  String spokenText = '';
  File? audio;
  double seconds = 0;
  bool busy = false;

  void _onText() {
    if (audio != null && controller.text.trim() != spokenText) {
      audio = null;
      seconds = 0;
      spokenText = '';
    }
  }

  void dispose() => controller.dispose();
}

const _sceneCharacters = <(String, String)>[
  ('fort', 'فورت'),
  ('lort', 'لورت'),
  ('mort', 'مورت'),
  ('port', 'بورت'),
  ('qort', 'كورت'),
];

class AddStoryScreen extends StatefulWidget {
  final MissionEntity mission;
  final StoryEntity? storyToEdit;

  const AddStoryScreen({super.key, required this.mission, this.storyToEdit});

  @override
  State<AddStoryScreen> createState() => _AddStoryScreenState();
}

class _AddStoryScreenState extends State<AddStoryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _scriptController = TextEditingController();

  File? _audioFile;
  StoryTimeline? _timeline;
  late ContentBloc _contentBloc;

  AudioPlayer? _audioPlayer;
  AudioPlayer? _linePlayer;
  bool _isPlaying = false;
  int _step = 0;
  bool _joining = false;
  bool _scriptBusy = false;
  bool _preparingEdit = false;
  bool _audioRebuilt = false;
  String? _sceneSignature;
  String _savedSceneKey = '';
  final List<_SentenceLine> _lines = [];
  final ValueNotifier<Duration> _positionNotifier = ValueNotifier(Duration.zero);
  StreamSubscription? _playerStateSubscription;
  StreamSubscription? _positionSubscription;

  @override
  void initState() {
    super.initState();
    _contentBloc = sl<ContentBloc>();
    _scriptController.addListener(() {
      if (mounted) setState(() {});
    });
    final story = widget.storyToEdit;
    if (story == null) return;
    _titleController.text = story.title;
    _contentController.text = story.content;
    if (story.timelineData != null) {
      try {
        _timeline = StoryTimeline.fromJson(jsonDecode(story.timelineData!));
      } catch (_) {}
    }
    _hydrateLines(story);
    _scriptController.text = _scriptFromLines(_lines);
    final url = story.audioUrl?.trim() ?? '';
    if (url.isNotEmpty) {
      _preparingEdit = true;
      unawaited(_loadExistingAudio(url));
    }
  }

  void _hydrateLines(StoryEntity story) {
    final texts = story.content
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final blocks = _timeline?.blocks ?? const <StoryBlock>[];
    for (var i = 0; i < texts.length; i++) {
      final line = _SentenceLine();
      line.controller.text = texts[i];
      final fromBlock = i < blocks.length ? blocks[i].characterId : '';
      if (_sceneCharacters.any((character) => character.$1 == fromBlock)) {
        line.characterId = fromBlock;
      } else if (_sceneCharacters.any(
        (character) => character.$1 == story.characterName,
      )) {
        line.characterId = story.characterName;
      }
      line.controller.addListener(() {
        if (mounted) setState(() {});
      });
      _lines.add(line);
    }
    _savedSceneKey = _sceneKey(_lines);
  }

  String _sceneKey(List<_SentenceLine> lines) {
    return lines
        .map((line) => '${line.characterId}|${line.controller.text.trim()}')
        .join('\n');
  }

  Future<void> _loadExistingAudio(String url) async {
    try {
      final resources = sl<ResourceManager>();
      final path = resources.getLocalFilePath(url) ??
          await resources.downloadAndCacheFile(url, folder: 'audio');
      if (!mounted) return;
      if (path != null && File(path).existsSync()) {
        _audioFile = File(path);
        await _initAudio(DeviceFileSource(path));
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر تحميل صوت القصة. ولّد الجمل من جديد.'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر تحميل صوت القصة. ولّد الجمل من جديد.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _preparingEdit = false;
          if (_audioFile != null) _step = 1;
        });
      }
    }
  }

  StoryTimeline _keepLanes(List<StoryBlock> blocks, double seconds) {
    final previous = _timeline;
    double fit(double start, double end) {
      final capped = end > seconds ? seconds : end;
      return capped > start ? capped : start;
    }

    return StoryTimeline(
      blocks: blocks,
      totalDuration: seconds,
      motionBlocks: [
        for (final block in previous?.motionBlocks ?? const <StoryMotionBlock>[])
          if (block.startTime < seconds)
            StoryMotionBlock(
              motionId: block.motionId,
              startTime: block.startTime,
              endTime: fit(block.startTime, block.endTime),
            ),
      ].where((block) => block.endTime > block.startTime).toList(),
      hatBlocks: [
        for (final block in previous?.hatBlocks ?? const <StoryHatBlock>[])
          if (block.startTime < seconds)
            StoryHatBlock(
              colorHex: block.colorHex,
              startTime: block.startTime,
              endTime: fit(block.startTime, block.endTime),
            ),
      ].where((block) => block.endTime > block.startTime).toList(),
      glassesBlocks: [
        for (final block in previous?.glassesBlocks ?? const <StoryGlassesBlock>[])
          if (block.startTime < seconds)
            StoryGlassesBlock(
              startTime: block.startTime,
              endTime: fit(block.startTime, block.endTime),
            ),
      ].where((block) => block.endTime > block.startTime).toList(),
      musclesBlocks: [
        for (final block in previous?.musclesBlocks ?? const <StoryMusclesBlock>[])
          if (block.startTime < seconds)
            StoryMusclesBlock(
              startTime: block.startTime,
              endTime: fit(block.startTime, block.endTime),
            ),
      ].where((block) => block.endTime > block.startTime).toList(),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _scriptController.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    _contentBloc.close();
    _playerStateSubscription?.cancel();
    _positionSubscription?.cancel();
    _audioPlayer?.dispose();
    _linePlayer?.dispose();
    _positionNotifier.dispose();
    super.dispose();
  }

  Future<void> _initAudio(Source source) async {
    _audioPlayer?.dispose();
    _playerStateSubscription?.cancel();
    _positionSubscription?.cancel();

    _audioPlayer = AudioPlayer();

    _playerStateSubscription = _audioPlayer!.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
        if (!_isPlaying && state == PlayerState.completed) {
          _positionNotifier.value = Duration.zero;
        }
      }
    });

    _positionSubscription = _audioPlayer!.onPositionChanged.listen((position) {
      if (mounted) {
        _positionNotifier.value = position;
      }
    });

    await _audioPlayer!.setReleaseMode(ReleaseMode.stop);
    await _audioPlayer!.setSource(source);
    setState(() {
      _isPlaying = false;
      _positionNotifier.value = Duration.zero;
    });
  }

  void _togglePlayPause() async {
    if (_audioPlayer == null) return;
    if (_isPlaying) {
      await _audioPlayer!.pause();
    } else {
      await _audioPlayer!.resume();
    }
  }

  String _scriptFromLines(List<_SentenceLine> lines) {
    return lines
        .where((line) => line.controller.text.trim().isNotEmpty)
        .map((line) => '${line.controller.text.trim()} /${_characterName(line.characterId)}')
        .join('\n');
  }

  String _characterName(String characterId) {
    for (final character in _sceneCharacters) {
      if (character.$1 == characterId) return character.$2;
    }
    return 'كورت';
  }

  String? _characterId(String name) {
    final cleaned = name.trim();
    for (final character in _sceneCharacters) {
      if (character.$2 == cleaned || character.$1 == cleaned) return character.$1;
    }
    return null;
  }

  List<({String text, String characterId})>? _parseScript(String raw) {
    final pieces = <({String text, String characterId})>[];
    final pattern = RegExp(r'([^/\n]+?)\s*/\s*(\S+)');
    final lines = raw.split('\n');
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index].trim();
      if (line.isEmpty) continue;
      final matches = pattern.allMatches(line).toList();
      if (matches.isEmpty) {
        _scriptError('السطر ${index + 1} يحتاج / واسم الشخصية في آخره');
        return null;
      }
      var consumed = 0;
      for (final match in matches) {
        final spoken = match.group(1)!.trim();
        final name = match.group(2)!.replaceAll(RegExp(r'[.،,!！?؟:]+$'), '');
        final characterId = _characterId(name);
        if (spoken.isEmpty || characterId == null) {
          _scriptError('السطر ${index + 1}: الشخصية «$name» غير معروفة');
          return null;
        }
        pieces.add((text: spoken, characterId: characterId));
        consumed = match.end;
      }
      if (line.substring(consumed).trim().isNotEmpty) {
        _scriptError('السطر ${index + 1} فيه كلام بعد اسم الشخصية');
        return null;
      }
    }
    if (pieces.isEmpty) {
      _scriptError('اكتب جملة واحدة على الأقل في الوصف');
      return null;
    }
    return pieces;
  }

  void _scriptError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  _SentenceLine _makeLine(String text, String characterId) {
    final line = _SentenceLine();
    line.controller.text = text;
    line.characterId = characterId;
    line.controller.addListener(() {
      if (mounted) setState(() {});
    });
    return line;
  }

  bool get _scriptReady {
    final pieces = _parseScriptQuiet(_scriptController.text);
    if (pieces == null) return false;
    final ready = _lines.where((line) => line.controller.text.trim().isNotEmpty).toList();
    if (ready.length != pieces.length) return false;
    for (var index = 0; index < pieces.length; index++) {
      final line = ready[index];
      final piece = pieces[index];
      if (line.audio == null || line.spokenText != piece.text || line.characterId != piece.characterId) {
        return false;
      }
    }
    return true;
  }

  List<({String text, String characterId})>? _parseScriptQuiet(String raw) {
    final pieces = <({String text, String characterId})>[];
    final pattern = RegExp(r'([^/\n]+?)\s*/\s*(\S+)');
    for (final rawLine in raw.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final matches = pattern.allMatches(line).toList();
      if (matches.isEmpty) return null;
      var consumed = 0;
      for (final match in matches) {
        final spoken = match.group(1)!.trim();
        final name = match.group(2)!.replaceAll(RegExp(r'[.،,!！?؟:]+$'), '');
        final characterId = _characterId(name);
        if (spoken.isEmpty || characterId == null) return null;
        pieces.add((text: spoken, characterId: characterId));
        consumed = match.end;
      }
      if (line.substring(consumed).trim().isNotEmpty) return null;
    }
    if (pieces.isEmpty) return null;
    return pieces;
  }

  Future<void> _speakScript() async {
    if (_scriptBusy) return;
    final pieces = _parseScript(_scriptController.text);
    if (pieces == null) return;
    final ready = _lines.where((line) => line.controller.text.trim().isNotEmpty).toList();
    final same = ready.length == pieces.length &&
        List.generate(pieces.length, (index) {
          final line = ready[index];
          return line.audio != null &&
              line.spokenText == pieces[index].text &&
              line.characterId == pieces[index].characterId;
        }).every((matches) => matches);
    if (same) {
      await _playLines(ready);
      return;
    }

    setState(() => _scriptBusy = true);
    final next = <_SentenceLine>[];
    try {
      for (final piece in pieces) {
        final clip = await StorySentenceVoice.speak(
          characterId: piece.characterId,
          text: piece.text,
        );
        final line = _makeLine(piece.text, piece.characterId);
        line.audio = clip.file;
        line.seconds = clip.seconds;
        line.spokenText = piece.text;
        next.add(line);
      }
      if (!mounted) {
        for (final line in next) {
          line.dispose();
        }
        return;
      }
      final previous = List<_SentenceLine>.of(_lines);
      setState(() {
        _lines
          ..clear()
          ..addAll(next);
        _scriptBusy = false;
      });
      for (final line in previous) {
        line.dispose();
      }
      next.clear();
      await _playLines(_lines);
    } catch (_) {
      for (final line in next) {
        line.dispose();
      }
      if (!mounted) return;
      setState(() => _scriptBusy = false);
      _scriptError('تعذر توليد صوت الوصف. حاول مرة أخرى.');
    }
  }

  Future<void> _playLines(List<_SentenceLine> lines) async {
    _linePlayer ??= AudioPlayer();
    for (final line in lines) {
      final file = line.audio;
      if (file == null || !mounted) return;
      await _linePlayer!.stop();
      await _linePlayer!.play(DeviceFileSource(file.path));
      await _linePlayer!.onPlayerComplete.first;
    }
  }

  void _addLine() {
    final line = _SentenceLine();
    line.controller.addListener(() {
      if (mounted) setState(() {});
    });
    setState(() => _lines.add(line));
  }

  Future<void> _playLine(File file) async {
    _linePlayer ??= AudioPlayer();
    await _linePlayer!.stop();
    await _linePlayer!.setVolume(1);
    await _linePlayer!.play(DeviceFileSource(file.path));
  }

  Future<void> _speakLine(_SentenceLine line) async {
    final text = line.controller.text.trim();
    if (text.isEmpty || line.busy) return;
    if (line.audio != null && line.spokenText == text) {
      await _playLine(line.audio!);
      return;
    }
    setState(() => line.busy = true);
    try {
      final clip = await StorySentenceVoice.speak(
        characterId: line.characterId,
        text: text,
      );
      if (!mounted) return;
      setState(() {
        line.audio = clip.file;
        line.seconds = clip.seconds;
        line.spokenText = text;
        line.busy = false;
      });
      await _playLine(clip.file);
    } catch (_) {
      if (!mounted) return;
      setState(() => line.busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر توليد صوت هذه الجملة. حاول مرة أخرى.')),
      );
    }
  }

  Future<void> _openTimeline() async {
    if (_joining) return;
    final ready = _lines.where((line) => line.controller.text.trim().isNotEmpty).toList();
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اكتب عنوان القصة أولاً')),
      );
      return;
    }
    if (ready.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أضف جملة واحدة على الأقل')),
      );
      return;
    }

    final sceneKey = _sceneKey(ready);
    final sameScene = _audioFile != null &&
        _timeline != null &&
        (sceneKey == _sceneSignature ||
            (!_audioRebuilt && sceneKey == _savedSceneKey && _savedSceneKey.isNotEmpty));
    if (sameScene) {
      _contentController.text = ready.map((line) => line.controller.text.trim()).join('\n');
      setState(() => _step = 1);
      return;
    }

    if (ready.any((line) => line.audio == null || line.seconds <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ولّد صوت كل جملة قبل التالي')),
      );
      return;
    }

    setState(() => _joining = true);
    try {
      final merged = await StorySentenceVoice.join(ready.map((line) => line.audio!).toList());
      final spoken = ready.fold<double>(0, (sum, line) => sum + line.seconds);
      final scale = spoken > 0 ? merged.seconds / spoken : 1.0;
      var cursor = 0.0;
      final blocks = <StoryBlock>[];
      for (final line in ready) {
        final end = cursor + (line.seconds * scale);
        blocks.add(
          StoryBlock(
            characterId: line.characterId,
            startTime: cursor,
            endTime: end,
          ),
        );
        cursor = end;
      }
      if (blocks.isNotEmpty) {
        final last = blocks.last;
        blocks[blocks.length - 1] = StoryBlock(
          characterId: last.characterId,
          startTime: last.startTime,
          endTime: merged.seconds,
        );
      }
      _contentController.text = ready.map((line) => line.controller.text.trim()).join('\n');
      _timeline = _keepLanes(blocks, merged.seconds);
      _audioFile = merged.file;
      _audioRebuilt = true;
      _sceneSignature = sceneKey;
      await _initAudio(DeviceFileSource(merged.file.path));
      if (!mounted) return;
      setState(() => _step = 1);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تجهيز المشهد. حاول مرة أخرى.')),
      );
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Widget _sentenceRow(_SentenceLine line, int index) {
    final ready = line.audio != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: line.controller,
            maxLines: 2,
            decoration: InputDecoration(hintText: 'الجملة ${index + 1}'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: line.characterId,
                  decoration: const InputDecoration(isDense: true),
                  items: [
                    for (final character in _sceneCharacters)
                      DropdownMenuItem(
                        value: character.$1,
                        child: Text(
                          character.$2,
                          style: TextStyle(
                            color: CharacterHelper.getColor(character.$1),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                  onChanged: line.busy
                      ? null
                      : (value) {
                          if (value == null || value == line.characterId) return;
                          setState(() {
                            line.characterId = value;
                            line.audio = null;
                            line.seconds = 0;
                            line.spokenText = '';
                          });
                        },
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: line.busy ? null : () => _speakLine(line),
                child: line.busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(ready ? 'اسمع' : 'اعمل الصوت'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      String charName = 'qort';

      if (_timeline != null && _timeline!.blocks.isNotEmpty) {
        charName = _timeline!.blocks.first.characterId;
      } else if (widget.storyToEdit != null && widget.storyToEdit!.characterName.isNotEmpty) {
        charName = widget.storyToEdit!.characterName;
      }

      final story = StoryEntity(
        id: widget.storyToEdit?.id ?? '',
        missionId: widget.mission.id,
        title: _titleController.text.trim(),
        characterName: charName,
        content: _contentController.text.trim(),
        imageUrl: widget.storyToEdit?.imageUrl ?? '',
        audioUrl: widget.storyToEdit?.audioUrl,
        orderIndex: widget.storyToEdit?.orderIndex ?? 0,
        timelineData: _timeline != null ? jsonEncode(_timeline!.toJson()) : null,
      );
      final audioFile = widget.storyToEdit == null || _audioRebuilt ? _audioFile : null;
      if (widget.storyToEdit != null) {
        _contentBloc.add(
          ContentEvent.updateStory(
            story,
            audioFile: audioFile,
          ),
        );
      } else {
        _contentBloc.add(
          ContentEvent.addStory(
            story,
            audioFile: audioFile,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.storyToEdit != null;
    return BlocProvider.value(
      value: _contentBloc,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(
          leading: _step == 1
              ? BackButton(onPressed: () => setState(() => _step = 0))
              : null,
          title: Text(
            _step == 1
                ? 'المونتاج'
                : editing
                    ? 'تعديل القصة'
                    : 'كتابة المشهد',
          ),
          elevation: 0,
          surfaceTintColor: Colors.white,
        ),
        body: BlocConsumer<ContentBloc, ContentState>(
          listener: (context, state) {
            state.maybeWhen(
              storyAdded: (_) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تمت إضافة القصة بنجاح!')),
                );
                context.pop(true);
              },
              storiesLoaded: (_) {
                if (editing) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم تحديث القصة بنجاح!')),
                  );
                  context.pop(true);
                }
              },
              error: (msg) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('خطأ: $msg')));
              },
              orElse: () {},
            );
          },
          builder: (context, state) {
            final isLoading = _joining ||
                _scriptBusy ||
                _preparingEdit ||
                state.maybeWhen(
                  loading: () => true,
                  orElse: () => false,
                );

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      Expanded(
                        child: _preparingEdit
                            ? const Center(child: CircularProgressIndicator())
                            : ListView(
                                children: [
                                  if (_step == 0) ...[
                                    Row(
                                      children: [
                                        Expanded(
                                          child: AdminVoiceField(
                                            controller: _titleController,
                                            hint: 'عنوان القصة',
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton.filledTonal(
                                          onPressed: _addLine,
                                          icon: const Icon(Icons.add),
                                          tooltip: 'إضافة جملة',
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: TextFormField(
                                            controller: _scriptController,
                                            minLines: 4,
                                            maxLines: 8,
                                            decoration: const InputDecoration(
                                              hintText: 'الوصف. كل جملة تنتهي بـ /لورت أو /بورت',
                                              alignLabelWithHint: true,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        FilledButton.tonal(
                                          onPressed: _scriptBusy ? null : _speakScript,
                                          style: FilledButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                          ),
                                          child: _scriptBusy
                                              ? const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child: CircularProgressIndicator(strokeWidth: 2),
                                                )
                                              : Text(_scriptReady ? 'اسمع' : 'اعمل الصوت'),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    for (var i = 0; i < _lines.length; i++)
                                      _sentenceRow(_lines[i], i),
                                  ] else if (_audioFile != null) ...[
                                    StoryTimelineEditor(
                                      key: ValueKey(_audioFile!.path),
                                      audioFile: _audioFile!,
                                      initialTimeline: _timeline,
                                      positionNotifier: _positionNotifier,
                                      audioPlayer: _audioPlayer,
                                      isPlaying: _isPlaying,
                                      onTogglePlay: _togglePlayPause,
                                      onTimelineChanged: (val) {
                                        setState(() => _timeline = val);
                                      },
                                    ),
                                  ],
                                ],
                              ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: isLoading
                              ? null
                              : _step == 0
                                  ? _openTimeline
                                  : _submit,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: isLoading
                              ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  _step == 0
                                      ? 'التالي'
                                      : editing
                                          ? 'تحديث القصة'
                                          : 'نشر القصة الآن',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
