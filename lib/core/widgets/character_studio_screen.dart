import 'dart:async';

import 'package:Glow/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

import '../animation/story_motion.dart';
import '../utils/character_helper.dart';
import 'smart_character_viewer.dart';

/// A backend-independent workbench for the same character used by stories.
class CharacterStudioScreen extends StatefulWidget {
  const CharacterStudioScreen({super.key});

  @override
  State<CharacterStudioScreen> createState() => _CharacterStudioScreenState();
}

class _CharacterStudioScreenState extends State<CharacterStudioScreen> {
  static const _ink = Color(0xFF18372F);
  static const _muted = Color(0xFF688077);
  static const _accent = Color(0xFF277A59);
  static const _sample =
      'مرحبا يا أصدقائي! مشى صديقنا إلى الحديقة. '
      'فكر كيف يساعد أصدقاءه؟ كان حزينا عندما خسر. '
      'ثم حاول من جديد وفاز! ضحك الجميع بسعادة.';

  final _storyController = TextEditingController(text: _sample);
  final _position = ValueNotifier(Duration.zero);
  final _clock = Stopwatch();
  late final Timer _timer;
  var _plan = StoryMotionPlan.fromText(_sample);
  var _storyText = _sample;
  var _basePosition = Duration.zero;
  var _character = 'port';
  CharacterMotion? _selectedMotion;
  var _playing = true;
  var _skeleton = false;
  var _showHat = true;
  var _showGlasses = true;
  var _showMuscles = true;
  var _hatColor = const Color(0xFF2C2C2E);

  static const _hatColors = <Color>[
    Color(0xFF2C2C2E),
    Color(0xFF1A1A1A),
    Color(0xFF4A3728),
    Color(0xFF8B4513),
    Color(0xFFC0392B),
    Color(0xFF277A59),
    Color(0xFF2E86C1),
    Color(0xFFF5F5F5),
  ];

  @override
  void initState() {
    super.initState();
    _clock.start();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!_playing) return;
      final duration = _plan.duration.inMilliseconds;
      final elapsed = (_basePosition + _clock.elapsed).inMilliseconds;
      _position.value = Duration(
        milliseconds: duration > 0 ? elapsed % duration : elapsed,
      );
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _clock.stop();
    _position.dispose();
    _storyController.dispose();
    super.dispose();
  }

  void _togglePlayback() {
    setState(() {
      _playing = !_playing;
      if (_playing) {
        _clock
          ..reset()
          ..start();
      } else {
        _basePosition = _position.value;
        _clock.stop();
      }
    });
  }

  void _seek(Duration position) {
    _basePosition = position;
    _position.value = position;
    _clock.reset();
  }

  void _applyStory() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _storyText = _storyController.text;
      _plan = StoryMotionPlan.fromText(_storyText);
      _selectedMotion = null;
      _seek(Duration.zero);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F7F3),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF3F7F3),
          foregroundColor: _ink,
          surfaceTintColor: Colors.transparent,
          title: const Text(
            'استوديو الشخصية',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 19),
          ),
          actions: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 20),
              child: Center(
                child: Text(
                  'GLOW / 3D',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    color: _ink.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) {
                return const SizedBox.shrink();
              }
              final wide = constraints.maxWidth >= 900;
              return SingleChildScrollView(
                padding: EdgeInsets.all(wide ? 28 : 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1260),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'شخصية واحدة، بحكايات كثيرة.',
                          style: TextStyle(
                            color: _ink,
                            fontSize: 27,
                            height: 1.4,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'جرّب الحركة والتعبير واللون، ثم دع قصتك تقود المشهد.',
                          style: TextStyle(color: _muted, height: 1.6),
                        ),
                        const SizedBox(height: 24),
                        if (wide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _stage(570)),
                              const SizedBox(width: 22),
                              SizedBox(width: 350, child: _controls()),
                            ],
                          )
                        else ...[
                          _stage(
                            (constraints.maxWidth * 1.04).clamp(330.0, 480.0),
                          ),
                          const SizedBox(height: 18),
                          _controls(),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _stage(double height) {
    return Column(
      children: [
        Container(
          height: height,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            color: const Color(0xFFE6EEE7),
            border: Border.all(color: const Color(0xFFDCE6DC)),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              SmartCharacterViewer(
                characterName: _character,
                storyText: _storyText,
                isPlaying: _playing,
                isSpeaking: false,
                playbackPosition: _position,
                motion: _selectedMotion,
                interactive: true,
                showSkeleton: _skeleton,
                showHat: _showHat,
                hatColor: _hatColor,
                showMuscles: _showMuscles,
                showGlasses: _showGlasses,
              ),
              PositionedDirectional(
                top: 18,
                start: 18,
                child: _badge(
                  icon: Icons.view_in_ar_outlined,
                  label:
                      'مجسم واحد · ${CharacterMotion.values.length} حركات وتعبيرات',
                ),
              ),
              PositionedDirectional(
                top: 18,
                end: 18,
                child: ValueListenableBuilder<Duration>(
                  valueListenable: _position,
                  builder: (context, position, child) => _badge(
                    icon: _playing ? Icons.play_arrow_rounded : Icons.pause,
                    label: _playing
                        ? (_selectedMotion ?? _plan.motionAt(position))
                              .arabicLabel
                        : 'متوقف',
                  ),
                ),
              ),
              const PositionedDirectional(
                bottom: 18,
                start: 0,
                end: 0,
                child: IgnorePointer(
                  child: Center(
                    child: Text(
                      'اسحب لتدوير الشخصية • قرّب لاستكشاف التفاصيل',
                      style: TextStyle(
                        color: Color(0xFF52665B),
                        fontSize: 11,
                        shadows: [Shadow(color: Colors.white, blurRadius: 8)],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _playbackPanel(),
      ],
    );
  }

  Widget _playbackPanel() {
    return _panel(
      child: ValueListenableBuilder<Duration>(
        valueListenable: _position,
        builder: (context, position, child) {
          final cue = _plan.cueAt(position);
          final duration = _plan.duration.inMilliseconds;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      minimumSize: const Size(54, 48),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _togglePlayback,
                    child: Tooltip(
                      message: _playing ? 'إيقاف مؤقت' : 'تشغيل',
                      child: Icon(
                        _playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'إعادة المشهد',
                    onPressed: () => _seek(Duration.zero),
                    icon: const Icon(Icons.replay_rounded, color: _ink),
                  ),
                  const Spacer(),
                  const Icon(Icons.repeat_rounded, size: 16, color: _muted),
                  const SizedBox(width: 8),
                  Text(
                    '${_time(position)} / ${_time(_plan.duration)}',
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      fontSize: 12,
                      color: _muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: _accent,
                  thumbColor: _accent,
                  inactiveTrackColor: const Color(0xFFE0E9E2),
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 14,
                  ),
                ),
                child: Slider(
                  value: duration > 0
                      ? (position.inMilliseconds / duration).clamp(0.0, 1.0)
                      : 0,
                  onChanged: duration > 0
                      ? (value) => _seek(
                          Duration(milliseconds: (value * duration).round()),
                        )
                      : null,
                  semanticFormatterCallback: (value) =>
                      '${(value * duration / 1000).round()} ثانية',
                ),
              ),
              Text(
                _selectedMotion == null
                    ? 'اللحظة الحالية'
                    : 'معاينة حركة يدوية',
                style: const TextStyle(
                  fontSize: 11,
                  color: _muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 44,
                child: Text(
                  _selectedMotion?.arabicLabel ??
                      cue?.text ??
                      'اكتب قصة قصيرة لبدء المشهد.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _ink, height: 1.5),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _controls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle('لون الشخصية', Icons.palette_outlined),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: CharacterHelper.characters.keys.map((key) {
                  final selected = _character == key;
                  return Semantics(
                    button: true,
                    selected: selected,
                    label: 'لون ${CharacterHelper.getCleanName(key)}',
                    child: Tooltip(
                      message: CharacterHelper.getCleanName(key),
                      child: InkWell(
                        borderRadius: BorderRadius.all(
                          Radius.circular(AppColors.border_radius),
                        ),
                        onTap: () => setState(() => _character = key),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          height: 46,
                          width: 46,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected ? _ink : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: CharacterHelper.getColor(key),
                            ),
                            child: selected
                                ? const Icon(
                                    Icons.check_rounded,
                                    size: 20,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 22),
              _sectionTitle('الحركة والتعبير', Icons.accessibility_new_rounded),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _selectedMotion = null),
                  icon: Icon(
                    _selectedMotion == null
                        ? Icons.check_circle_rounded
                        : Icons.auto_stories_outlined,
                    size: 18,
                  ),
                  label: const Text('تلقائي حسب القصة'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _accent,
                    backgroundColor: _selectedMotion == null
                        ? const Color(0xFFEAF3EC)
                        : Colors.white,
                    side: BorderSide(
                      color: _selectedMotion == null
                          ? _accent
                          : const Color(0xFFDBE5DD),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(13),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: CharacterMotion.values.map((motion) {
                    final selected = _selectedMotion == motion;
                    return SizedBox(
                      width: (constraints.maxWidth - 24) / 4,
                      child: Material(
                        color: selected ? _ink : const Color(0xFFF3F6F3),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => setState(() => _selectedMotion = motion),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Column(
                              children: [
                                Icon(
                                  _motionIcon(motion),
                                  size: 21,
                                  color: selected ? Colors.white : _muted,
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  motion.arabicLabel,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: selected ? Colors.white : _ink,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                value: _skeleton,
                onChanged: (value) => setState(() => _skeleton = value),
                contentPadding: EdgeInsets.zero,
                activeTrackColor: _accent,
                title: const Text(
                  'إظهار العظام',
                  style: TextStyle(color: _ink, fontSize: 13),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                value: _showMuscles,
                onChanged: (value) => setState(() => _showMuscles = value),
                contentPadding: EdgeInsets.zero,
                activeTrackColor: _accent,
                title: const Text(
                  'عضلات البطن',
                  style: TextStyle(color: _ink, fontSize: 13),
                ),
                subtitle: const Text(
                  'صدر وبطن على الجسم، وتقدر تشيلها',
                  style: TextStyle(color: _muted, fontSize: 11),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                value: _showGlasses,
                onChanged: (value) => setState(() => _showGlasses = value),
                contentPadding: EdgeInsets.zero,
                activeTrackColor: _accent,
                title: const Text(
                  'النظارة',
                  style: TextStyle(color: _ink, fontSize: 13),
                ),
                subtitle: const Text(
                  'فوق العينين، وتقدر تشيلها',
                  style: TextStyle(color: _muted, fontSize: 11),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                value: _showHat,
                onChanged: (value) => setState(() => _showHat = value),
                contentPadding: EdgeInsets.zero,
                activeTrackColor: _accent,
                title: const Text(
                  'إظهار الطاقية',
                  style: TextStyle(color: _ink, fontSize: 13),
                ),
                subtitle: const Text(
                  'قبعة فيدورا مع أذنين',
                  style: TextStyle(color: _muted, fontSize: 11),
                ),
              ),
              if (_showHat) ...[
                const SizedBox(height: 10),
                const Text(
                  'لون الطاقية',
                  style: TextStyle(color: _ink, fontSize: 13),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _hatColors.map((color) {
                    final selected = _hatColor.toARGB32() == color.toARGB32();
                    return Semantics(
                      button: true,
                      selected: selected,
                      label: 'لون الطاقية',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(22),
                        onTap: () => setState(() => _hatColor = color),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          height: 36,
                          width: 36,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected ? _ink : const Color(0xFFD0D8D0),
                              width: selected ? 2.2 : 1,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionTitle('جرّب حكايتك', Icons.edit_note_rounded),
              const SizedBox(height: 14),
              TextField(
                controller: _storyController,
                minLines: 4,
                maxLines: 7,
                maxLength: 2000,
                textDirection: TextDirection.rtl,
                style: const TextStyle(color: _ink, fontSize: 13, height: 1.8),
                decoration: InputDecoration(
                  hintText: 'مرحبا! مشى صديقنا إلى الحديقة…',
                  filled: true,
                  fillColor: const Color(0xFFF5F7F3),
                  contentPadding: const EdgeInsets.all(14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _accent),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              FilledButton.icon(
                onPressed: _applyStory,
                icon: const Icon(Icons.auto_stories_outlined, size: 18),
                label: const Text('تطبيق القصة'),
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'الحركات تتبع كلمات القصة بتوقيت تقريبي. '
                'يمكنك اختيار الحركة يدويًا. حركة الفم للمعاينة '
                'ولا تتزامن مع تسجيل صوتي.',
                style: TextStyle(color: _muted, fontSize: 11, height: 1.7),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _panel({required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.all(Radius.circular(AppColors.border_radius)),
      border: Border.all(color: const Color(0xFFE2E9E1)),
    ),
    child: child,
  );

  Widget _sectionTitle(String title, IconData icon) => Row(
    children: [
      Icon(icon, color: _accent, size: 20),
      const SizedBox(width: 9),
      Text(
        title,
        style: const TextStyle(
          color: _ink,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );

  Widget _badge({required IconData icon, required String label}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(24),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: _accent),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: _ink, fontSize: 11)),
      ],
    ),
  );

  String _time(Duration time) =>
      '${time.inMinutes.toString().padLeft(2, '0')}:'
      '${(time.inSeconds % 60).toString().padLeft(2, '0')}';

  IconData _motionIcon(CharacterMotion motion) => switch (motion) {
    CharacterMotion.idle => Icons.self_improvement_rounded,
    CharacterMotion.talk => Icons.chat_bubble_outline_rounded,
    CharacterMotion.wave => Icons.waving_hand_outlined,
    CharacterMotion.happy => Icons.sentiment_very_satisfied_rounded,
    CharacterMotion.sad => Icons.sentiment_dissatisfied_rounded,
    CharacterMotion.thinking => Icons.psychology_outlined,
    CharacterMotion.victory => Icons.emoji_events_outlined,
    CharacterMotion.walk => Icons.directions_walk_rounded,
    CharacterMotion.smile => Icons.sentiment_satisfied_alt_rounded,
    CharacterMotion.laugh => Icons.sentiment_very_satisfied_rounded,
  };
}
