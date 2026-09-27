import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/widgets/smart_character_viewer.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/theme/app_colors.dart';
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

  File? _characterFile;
  File? _audioFile;
  StoryTimeline? _timeline;
  late ContentBloc _contentBloc;
  
  AudioPlayer? _audioPlayer;
  AudioPlayer? _linePlayer;
  bool _isPlaying = false;
  int _step = 0;
  bool _joining = false;
  String? _sceneSignature;
  final List<_SentenceLine> _lines = [];
  final ValueNotifier<Duration> _positionNotifier = ValueNotifier(Duration.zero);
  Duration _totalDuration = Duration.zero;
  StreamSubscription? _playerStateSubscription;
  StreamSubscription? _durationSubscription;
  StreamSubscription? _positionSubscription;

  @override
  void initState() {
    super.initState();
    _contentBloc = sl<ContentBloc>();
    if (widget.storyToEdit != null) {
      _titleController.text = widget.storyToEdit!.title;
      _contentController.text = widget.storyToEdit!.content;
      
      if (widget.storyToEdit!.audioUrl != null && widget.storyToEdit!.audioUrl!.isNotEmpty) {
        _initAudio(UrlSource(widget.storyToEdit!.audioUrl!));
      }
      if (widget.storyToEdit!.timelineData != null) {
        try {
          _timeline = StoryTimeline.fromJson(jsonDecode(widget.storyToEdit!.timelineData!));
        } catch (_) {}
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    _contentBloc.close();
    _playerStateSubscription?.cancel();
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();
    _audioPlayer?.dispose();
    _linePlayer?.dispose();
    _positionNotifier.dispose();
    super.dispose();
  }

  Future<void> _initAudio(Source source) async {
    _audioPlayer?.dispose();
    _playerStateSubscription?.cancel();
    _durationSubscription?.cancel();
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

    _durationSubscription = _audioPlayer!.onDurationChanged.listen((duration) {
      if (mounted) {
        setState(() {
          _totalDuration = duration;
        });
      }
    });

    _positionSubscription = _audioPlayer!.onPositionChanged.listen((position) {
      if (mounted) {
        _positionNotifier.value = position;
      }
    });

    await _audioPlayer!.setReleaseMode(ReleaseMode.stop);
    await _audioPlayer!.setSource(source);
    // When changing audio, pause playback
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

  Future<void> _pickAudio() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppColors.border_radius),
        ),
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 50),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(AppColors.border_radius),
              ),
            ),
            Text(
              'اختر ملف صوتي',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'اختر ملفاً صوتياً من هاتفك لإرفاقه بالقصة',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            // Pick file option
            InkWell(
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  final result = await FilePicker.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['mp3', 'wav', 'm4a', 'aac'],
                  );
                  if (result != null && result.isNotEmpty) {
                    final pickedPath = result.first.path;
                    if (pickedPath != null) {
                      setState(() {
                        _audioFile = File(pickedPath);
                      });
                      _initAudio(DeviceFileSource(pickedPath));
                    }
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('حدث خطأ: $e')));
                  }
                }
              },
              borderRadius: BorderRadius.circular(AppColors.border_radius),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primaryContainer.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(AppColors.border_radius),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(
                          AppColors.border_radius,
                        ),
                      ),
                      child: const Icon(Icons.folder_open, color: Colors.white),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'اختر من الملفات',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'MP3, WAV, M4A, AAC',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
            if (_audioFile != null) ...[
              const SizedBox(height: 12),
              // Remove file option
              InkWell(
                onTap: () {
                  setState(() => _audioFile = null);
                  Navigator.pop(ctx);
                },
                borderRadius: BorderRadius.circular(AppColors.border_radius),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.errorContainer.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(
                      AppColors.border_radius,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.error,
                          borderRadius: BorderRadius.circular(
                            AppColors.border_radius,
                          ),
                        ),
                        child: const Icon(
                          Icons.delete_outline,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        'إزالة الملف الصوتي',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              child: OutlinedButton(
                style: const ButtonStyle(
                  side: WidgetStatePropertyAll(
                    BorderSide(color: AppColors.inputBorder),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  'إلغاء',
                  style: TextStyle(color: Colors.black),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCharacter() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['glb', 'gltf'],
      );
      if (result != null && result.isNotEmpty) {
        final pickedPath = result.first.path;
        if (pickedPath != null) {
          setState(() {
            _characterFile = File(pickedPath);
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء رفع الشخصية: $e')),
        );
      }
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
    if (ready.isEmpty || ready.any((line) => line.audio == null || line.seconds <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ولّد صوت كل جملة قبل التالي')),
      );
      return;
    }

    final signature = ready
        .map((line) => '${line.characterId}|${line.spokenText}|${line.seconds}')
        .join('\n');
    if (signature == _sceneSignature && _audioFile != null && _timeline != null) {
      setState(() => _step = 1);
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
      _timeline = StoryTimeline(blocks: blocks, totalDuration: merged.seconds);
      _audioFile = merged.file;
      _sceneSignature = signature;
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
                  value: line.characterId,
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
      String charName = 'qort'; // Default character
      
      if (_timeline != null && _timeline!.blocks.isNotEmpty) {
        charName = _timeline!.blocks.first.characterId;
      } else if (widget.storyToEdit != null && widget.storyToEdit!.characterName.isNotEmpty) {
        charName = widget.storyToEdit!.characterName;
      }
      
      if (_characterFile != null) {
        // We will default the custom model to use 'fort' color scheme if no timeline is provided.
        // Or if timeline is provided, we use the color scheme of the first character.
        charName = 'custom|${CharacterHelper.getColorKey(charName)}|مخصصة';
      }

      final story = StoryEntity(
        id: widget.storyToEdit?.id ?? '',
        // Supabase gen_random_uuid will handle this if empty
        missionId: widget.mission.id,
        title: _titleController.text.trim(),
        characterName: charName,
        content: _contentController.text.trim(),
        imageUrl: widget.storyToEdit?.imageUrl ?? '',
        audioUrl: widget.storyToEdit?.audioUrl,
        orderIndex: widget.storyToEdit?.orderIndex ?? 0,
        timelineData: _timeline != null ? jsonEncode(_timeline!.toJson()) : null,
      );
      if (widget.storyToEdit != null) {
        _contentBloc.add(
          ContentEvent.updateStory(
            story,
            audioFile: _audioFile,
            characterFile: _characterFile,
          ),
        );
      } else {
        _contentBloc.add(
          ContentEvent.addStory(
            story,
            audioFile: _audioFile,
            characterFile: _characterFile,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _contentBloc,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(
          leading: widget.storyToEdit == null && _step == 1
              ? BackButton(onPressed: () => setState(() => _step = 0))
              : null,
          title: Text(
            widget.storyToEdit != null
                ? 'تعديل القصة'
                : _step == 0
                    ? 'كتابة المشهد'
                    : 'المونتاج',
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
                if (widget.storyToEdit != null) {
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
                        child: ListView(
                          children: [
                            if (widget.storyToEdit != null) ...[
                              if (_audioFile == null)
                                TextFormField(
                                  readOnly: true,
                                  onTap: _pickAudio,
                                  decoration: const InputDecoration(
                                    hintText: 'إرفاق ملف صوتي',
                                  ),
                                ),
                              if (_audioFile != null) ...[
                                const SizedBox(height: 16),
                                StoryTimelineEditor(
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
                              const SizedBox(height: 24),
                              TextFormField(
                                controller: _titleController,
                                decoration: const InputDecoration(
                                  hintText: 'عنوان القصة',
                                ),
                                validator: (val) =>
                                    val == null || val.isEmpty ? 'مطلوب' : null,
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _contentController,
                                decoration: const InputDecoration(
                                  hintText: 'محتوى القصة',
                                ),
                                maxLines: 4,
                                validator: (val) =>
                                    val == null || val.isEmpty ? 'مطلوب' : null,
                              ),
                            ] else if (_step == 0) ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _titleController,
                                      decoration: const InputDecoration(
                                        hintText: 'عنوان القصة',
                                      ),
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
                              : widget.storyToEdit == null && _step == 0
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
                                  widget.storyToEdit != null
                                      ? 'تحديث القصة'
                                      : _step == 0
                                          ? 'التالي'
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
