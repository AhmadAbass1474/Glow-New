import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:three_js/three_js.dart' as three;
import '../animation/story_motion.dart';
import '../animation/character_skin_palette.dart';
import '../animation/character_eye_animation.dart';
import '../animation/character_sleeve_morph.dart';
import '../services/character_asset_cache.dart';
import '../utils/character_helper.dart';
import 'mobile_character_viewer.dart';

/// One skinned GLB with reusable animations and five material colors.
/// Speaking uses a stylized cadence, not phoneme-based lip synchronization.
class SmartCharacterViewer extends StatelessWidget {
  const SmartCharacterViewer({
    super.key,
    required this.characterName,
    this.storyText = '',
    this.isPlaying = true,
    this.isSpeaking = false,
    this.playbackPosition,
    this.motion,
    this.interactive = true,
    this.showSkeleton = false,
    this.showHat = false,
    this.hatColor = const Color(0xFF2C2C2E),
    this.showMuscles = false,
    this.showGlasses = false,
    this.cameraFit = 1.10,
    this.onReady,
  });
  final String characterName;
  final String storyText;
  final bool isPlaying;
  final bool isSpeaking;
  final ValueListenable<Duration>? playbackPosition;
  final CharacterMotion? motion;
  final bool interactive;
  final bool showSkeleton;
  final bool showHat;
  final Color hatColor;
  final bool showMuscles;
  final bool showGlasses;
  final double cameraFit;
  final VoidCallback? onReady;

  @override
  Widget build(BuildContext context) {
    final source = CharacterHelper.getModelPath(characterName);
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android)) {
      return MobileCharacterViewer(
        key: ValueKey(source),
        characterName: characterName,
        storyText: storyText,
        isPlaying: isPlaying,
        isSpeaking: isSpeaking,
        interactive: interactive,
        showSkeleton: showSkeleton,
        showHat: showHat,
        hatColor: hatColor,
        showMuscles: showMuscles,
        showGlasses: showGlasses,
        cameraFit: cameraFit,
        motion: motion,
        playbackPosition: playbackPosition,
        onReady: onReady,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(
          constraints.hasBoundedWidth ? constraints.maxWidth : 320,
          constraints.hasBoundedHeight ? constraints.maxHeight : 360,
        );
        if (size.isEmpty) return const SizedBox.shrink();
        return _CharacterSurface(
          // Layout, keyboard and palette changes retain the model and texture.
          key: ValueKey(source),
          source: source,
          size: size,
          configuration: this,
        );
      },
    );
  }
}

class _CharacterSurface extends StatefulWidget {
  const _CharacterSurface({
    super.key,
    required this.source,
    required this.size,
    required this.configuration,
  });
  final String source;
  final Size size;
  final SmartCharacterViewer configuration;
  @override
  State<_CharacterSurface> createState() => _CharacterSurfaceState();
}

class _CharacterSurfaceState extends State<_CharacterSurface>
    with WidgetsBindingObserver {
  _GuardedThreeJS? _view;
  late StoryMotionPlan _plan;
  final _actions = <String, three.AnimationAction>{};
  final _bones = <three.Object3D>[];
  final _skinPalette = CharacterSkinPalette();
  final _eyeAnimation = CharacterEyeAnimation();
  final _sleeveMorph = CharacterSleeveMorph();
  three.Object3D? _model;
  three.AnimationMixer? _mixer;
  three.AnimationAction? _activeAction;
  three.OrbitControls? _orbit;
  three.Object3D? _jaw;
  three.Object3D? _mouth;
  three.Quaternion? _jawRest;
  three.Vector3? _jawRestPosition;
  three.LineSegments? _skeleton;
  three.Float32BufferAttribute? _skeletonPositions;
  final _point = three.Vector3();
  final _jawRotation = three.Quaternion();
  final _jawAxis = three.Vector3(1, 0, 0);
  bool _ready = false;
  bool _foreground = true;
  bool _tickerEnabled = true;
  Object? _error;
  double _elapsed = 0;
  Duration _lastPosition = Duration.zero;
  Timer? _loadTimeout;
  int _loadGeneration = 0;
  bool _compatibilityMode = false;
  double _modelWidth = 3.5;
  final _startup = Stopwatch();
  static const _canvasSize = Size.square(512);
  SmartCharacterViewer get config => widget.configuration;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _plan = StoryMotionPlan.fromText(config.storyText);
    config.playbackPosition?.addListener(_onPosition);
  }

  void _createView() {
    final generation = ++_loadGeneration;
    _startup.reset();
    _startup.start();
    // Android's flutter_angle resize is a no-op. Keep one bounded square
    // texture and project for the current display aspect instead of decoding
    // the GLB and recreating the EGL context whenever the layout changes.
    final pixels =
        (widget.size.longestSide * MediaQuery.devicePixelRatioOf(context))
            .clamp(512.0, _compatibilityMode ? 640.0 : 2048.0);
    final view = _GuardedThreeJS(
      size: _canvasSize,
      canRender: _canRender,
      onFirstFrame: () {
        if (!mounted || generation != _loadGeneration || _error != null) return;
        _loadTimeout?.cancel();
        _startup.stop();
        if (kDebugMode)
          debugPrint(
            'Character first frame: ${_startup.elapsedMilliseconds} ms (compatibility=$_compatibilityMode)',
          );
        setState(() => _ready = true);
        widget.configuration.onReady?.call();
      },
      settings: three.Settings(
        clearColor: 0xF4F7F5,
        antialias: kIsWeb, // MSAA often crashes mobile FBOs
        enableShadowMap: false,
        toneMapping: three.NoToneMapping,
        // Keep the known native texture path; fallback also disables MSAA.
        useSurfaceProducer: kIsWeb,
        stencil: false,
        precision: kIsWeb ? three.Precision.highp : three.Precision.mediump,
        screenResolution: pixels / _canvasSize.width,
      ),
      setup: () => _setup(generation),
      onError: (error, stack) {
        if (generation == _loadGeneration) _onError(error, stack);
      },
      onSetupComplete: () {
        if (generation != _loadGeneration) return;
        _loadTimeout?.cancel();
        if (mounted && _error == null) setState(() {});
      },
    );
    _view = view;
    // Early disposal must be safe even before the native texture exists.
    view.scene = three.Scene();
    view.camera = three.PerspectiveCamera(
      38,
      widget.size.width / widget.size.height,
      0.05,
      100,
    );
    _loadTimeout = Timer(const Duration(seconds: 30), () {
      if (generation == _loadGeneration) {
        _onError(
          TimeoutException('Character initialization timed out.'),
          StackTrace.current,
        );
      }
    });
  }

  void _onError(Object error, [StackTrace? stack]) {
    if (!mounted || _error != null) return;
    _loadTimeout?.cancel();
    debugPrint('Character viewer error: $error\n$stack');
    if (!_compatibilityMode) {
      _compatibilityMode = true;
      _restartRenderer();
      return;
    }
    _view?.visible = false;
    setState(() => _error = error);
  }

  Future<void> _setup(int generation) async {
    final loader = three.GLTFLoader();
    three.GLTFData? data;
    try {
      data = await _loadModel(loader);
    } finally {
      loader.dispose();
    }
    if (data == null) throw StateError('The GLB could not be loaded.');
    if (!mounted || _error != null || generation != _loadGeneration) {
      data.scene.dispose();
      return;
    }
    final view = _view;
    if (view == null) {
      data.scene.dispose();
      return;
    }
    _model = data.scene;
    view.scene.add(_model!);
    _model!.traverse((object) {
      if (object is three.Bone) _bones.add(object);
      if (object is three.SkinnedMesh) object.frustumCulled = false;
    });
    if (widget.source == CharacterHelper.sharedModelPath) {
      _skinPalette.attach(_model!);
      _eyeAnimation.attach(_model!);
      _sleeveMorph.attach(_model!);
    }
    _recolor();
    _jaw = _model!.getObjectByName('Jaw');
    _mouth = _model!.getObjectByName('Mouth');
    _jawRest = _jaw?.quaternion.clone();
    _jawRestPosition = _jaw?.position.clone();
    _mixer = three.AnimationMixer(_model!);
    for (final clip
        in (data.animations ?? const []).whereType<three.AnimationClip>()) {
      final action = _mixer!.clipAction(clip);
      if (action != null) _actions[clip.name] = action;
    }
    _frameModel();
    _buildLighting();
    if (config.showSkeleton) _buildSkeleton();
    _orbit = three.OrbitControls(view.camera, view.globalKey)
      ..enabled = config.interactive
      ..enablePan = false
      ..enableZoom = false
      ..enableDamping = true
      ..minDistance = 3
      ..maxDistance = 16;
    _orbit!.target.setValues(0, 1.78, 0);
    view.addAnimationEvent(_animate);
    _selectMotion();
    _mixer!.update(0);
    _sleeveMorph.update();
  }

  Future<three.GLTFData?> _loadModel(three.GLTFLoader loader) async {
    final source = widget.source;
    final uri = Uri.tryParse(source);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      if (uri?.scheme == 'file') return loader.fromPath(uri!.toFilePath());
      return loader.fromBytes(await CharacterAssetCache.instance.load(source));
    }

    // Keep the viewer free of app DI so the studio entrypoint stays light on
    // web. Remote story models go through CharacterAssetCache when bundled, or
    // the network loader when the URI is already absolute.
    return loader.fromNetwork(uri).timeout(const Duration(seconds: 6));
  }

  void _frameModel() {
    final bounds = three.BoundingBox().setFromObject(_model!);
    final extent = bounds.getSize(three.Vector3());
    final center = bounds.getCenter(three.Vector3());
    if (!extent.y.isFinite || extent.y <= 0) {
      throw StateError('The model has no renderable geometry.');
    }
    final scale = 3.5 / extent.y;
    _model!.scale.setValues(scale, scale, scale);
    _model!.position.setValues(
      -center.x * scale,
      -bounds.min.y * scale,
      -center.z * scale,
    );
    _modelWidth = extent.x * scale;
    _fitCamera();
  }

  void _fitCamera() {
    final aspect = widget.size.width / widget.size.height;
    final camera = _view?.camera;
    if (camera == null) return;
    camera.aspect = aspect;
    camera.updateProjectionMatrix();
    final distance =
        math.max(3.5, _modelWidth / aspect) /
        (2 * math.tan(38 * math.pi / 360)) *
        config.cameraFit;
    camera.position.setValues(0.32, 2.06, distance);
    camera.lookAt(three.Vector3(0, 1.78, 0));
  }

  void _buildLighting() {
    final view = _view;
    if (view == null) return;
    view.scene.add(three.HemisphereLight(0xEAF6FF, 0x8D8270, 0.75));
    view.scene.add(
      three.DirectionalLight(0xFFF2DC, 1.7)..position.setValues(-3, 6, 6),
    );
    view.scene.add(
      three.DirectionalLight(0xD7EFFF, 0.65)..position.setValues(4, 3, -3),
    );
    // Layered ellipses make a soft contact shadow without a shadow-map pass.
    for (var i = 0; i < 5; i++) {
      view.scene.add(
        three.Mesh(
            three.SphereGeometry(1, 32, 8),
            three.MeshBasicMaterial({
              three.MaterialProperty.color: 0x31483B,
              three.MaterialProperty.transparent: true,
              three.MaterialProperty.opacity: 0.025,
              three.MaterialProperty.depthWrite: false,
            }),
          )
          ..position.setValues(0, -0.04 - i * 0.001, 0)
          ..scale.setValues(0.60 + i * 0.10, 0.018, 0.38 + i * 0.07),
      );
    }
  }

  void _recolor() {
    if (widget.source == CharacterHelper.sharedModelPath) {
      final color = CharacterHelper.getColor(config.characterName);
      _skinPalette.setColor(
        color,
        originalGreen:
            CharacterHelper.getColorKey(config.characterName) == 'port',
      );
      _model?.traverse((object) {
        final material = object.material;
        if (material?.name == 'BodyColor' || material?.name == 'BodyDetail') {
          final shade = material!.name == 'BodyDetail' ? 0.55 : 1.0;
          material.color
              .setRGB(color.r * shade, color.g * shade, color.b * shade)
              .convertSRGBToLinear();
          material.needsUpdate = true;
        }
      });
    }
    _applyHat();
    _applyMuscles();
    _applyGlasses();
  }

  void _applyGlasses() {
    _model?.traverse((object) {
      if (object.material?.name != 'Glasses') return;
      object.visible = config.showGlasses;
    });
  }

  void _applyMuscles() {
    _skinPalette.setMuscles(config.showMuscles);
    _model?.traverse((object) {
      if (object.material?.name != 'Muscles') return;
      object.visible = false;
    });
  }

  void _applyHat() {
    final hatColor = config.hatColor;
    final skinColor = CharacterHelper.getColor(config.characterName);
    _model?.traverse((object) {
      final material = object.material;
      final name = material?.name;
      if (name != 'Hat' &&
          name != 'HatBand' &&
          name != 'HatTrim' &&
          name != 'HatSkin') {
        return;
      }
      object.visible = config.showHat;
      if (!config.showHat || material == null) return;
      if (name == 'HatSkin') {
        material.color
            .setRGB(skinColor.r, skinColor.g, skinColor.b)
            .convertSRGBToLinear();
      } else {
        final shade = name == 'HatBand' ? 0.45 : 1.0;
        // Textured hat: tint the felt with the studio hat color.
        material.color
            .setRGB(hatColor.r * shade, hatColor.g * shade, hatColor.b * shade)
            .convertSRGBToLinear();
      }
      material.transparent = false;
      material.opacity = 1.0;
      material.depthWrite = true;
      material.needsUpdate = true;
    });
  }

  void _buildSkeleton() {
    final view = _view;
    if (view == null) return;
    _bones.removeWhere((bone) => bone.parent is! three.Bone);
    if (_bones.isEmpty) return;
    _skeletonPositions = three.Float32BufferAttribute.fromList(
      List<double>.filled(_bones.length * 6, 0),
      3,
    );
    final geometry = three.BufferGeometry()
      ..setAttributeFromString('position', _skeletonPositions!);
    _skeleton =
        three.LineSegments(
            geometry,
            three.LineBasicMaterial({
              three.MaterialProperty.color: 0xFFB547,
              three.MaterialProperty.depthTest: false,
              three.MaterialProperty.depthWrite: false,
            }),
          )
          ..frustumCulled = false
          ..renderOrder = 100
          ..visible = config.showSkeleton;
    view.scene.add(_skeleton!);
  }

  void _updateSkeleton() {
    if (_skeleton == null || !config.showSkeleton) return;
    for (var i = 0; i < _bones.length; i++) {
      _bones[i].getWorldPosition(_point);
      _skeletonPositions!.setXYZ(i * 2, _point.x, _point.y, _point.z);
      _bones[i].parent!.getWorldPosition(_point);
      _skeletonPositions!.setXYZ(i * 2 + 1, _point.x, _point.y, _point.z);
    }
    _skeletonPositions!.needsUpdate = true;
  }

  Duration get _position =>
      config.playbackPosition?.value ??
      Duration(microseconds: (_elapsed * 1000000).round());

  void _selectMotion() {
    final motion = config.motion ?? _plan.motionAt(_position);
    final next =
        _actions[motion.clipName] ??
        _actions['Idle'] ??
        (_actions.isEmpty ? null : _actions.values.first);
    if (next == null || identical(next, _activeAction)) return;
    final previous = _activeAction;
    next.reset().setEffectiveWeight(1).play();
    if (previous != null) next.crossFadeFrom(previous, 0.3);
    _activeAction = next;
  }

  void _onPosition() {
    final position = _position;
    if (position < _lastPosition ||
        (position - _lastPosition).inMilliseconds > 1200) {
      _mixer?.stopAllAction();
      _activeAction = null;
      _elapsed = position.inMicroseconds / 1000000;
      _selectMotion();
      final action = _activeAction;
      if (action != null && action.clip.duration > 0) {
        action.time = _elapsed % action.clip.duration;
      }
      _mixer?.update(0);
      _sleeveMorph.update();
    }
    _lastPosition = position;
  }

  void _animate(double delta) {
    if (!mounted || !_foreground || !_tickerEnabled || _error != null) return;
    _orbit?.update();
    if (config.isPlaying) {
      final dt = delta.clamp(0.0, 0.08);
      _elapsed += dt;
      _selectMotion();
      if (_jaw != null && _jawRest != null) {
        _jaw!.quaternion.setFrom(_jawRest!);
      }
      _mixer?.update(dt);
      _sleeveMorph.update();
      final motion = config.motion ?? _plan.motionAt(_position);
      _eyeAnimation.update(dt, motion);
      _applyTalkingMouth(motion);
    }
    _updateSkeleton();
  }

  /// Every motion uses the Talk clip's jaw curve. Sad stays shut and lifts
  /// the lower lip so the painted smile turns down.
  void _applyTalkingMouth(CharacterMotion motion) {
    final jaw = _jaw;
    final rest = _jawRestPosition;
    if (jaw == null || rest == null) return;
    final sad = motion == CharacterMotion.sad;
    jaw.position.setValues(rest.x, rest.y + (sad ? 0.024 : 0.0), rest.z);
    if (sad) {
      _jawRotation.setFromAxisAngle(_jawAxis, 0);
    } else {
      final u = (_elapsed % 2.0) / 2.0;
      final syllable = math.pow(math.sin(math.pi * 4 * u), 2.0);
      _jawRotation.setFromAxisAngle(_jawAxis, 0.08 + 0.30 * syllable);
    }
    jaw.quaternion.setFrom(_jawRotation);
    _mouth?.scale.setValues(1, 1, 1);
  }

  bool _canRender() {
    if (!mounted || !_foreground || !_tickerEnabled || _error != null)
      return false;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return false;
    final bounds = box.localToGlobal(Offset.zero) & box.size;
    return bounds.overlaps(Offset.zero & MediaQuery.sizeOf(context));
  }

  @override
  void didUpdateWidget(covariant _CharacterSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.configuration;
    if (oldWidget.size != widget.size ||
        old.cameraFit != config.cameraFit) {
      _fitCamera();
    }
    if (old.characterName != config.characterName) {
      _recolor();
      if (_ready) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) config.onReady?.call();
        });
      }
    }
    if (old.showHat != config.showHat || old.hatColor != config.hatColor) {
      _applyHat();
    }
    if (old.showMuscles != config.showMuscles) {
      _applyMuscles();
    }
    if (old.showGlasses != config.showGlasses) {
      _applyGlasses();
    }
    if (old.storyText != config.storyText) {
      _plan = StoryMotionPlan.fromText(config.storyText);
      _elapsed = 0;
      _lastPosition = Duration.zero;
      _mixer?.stopAllAction();
      _activeAction = null;
    }
    if (old.playbackPosition != config.playbackPosition) {
      old.playbackPosition?.removeListener(_onPosition);
      config.playbackPosition?.addListener(_onPosition);
      _onPosition();
    }
    if (old.isSpeaking && !config.isSpeaking && _jawRest != null) {
      _jaw?.quaternion.setFrom(_jawRest!);
      _mouth?.scale.setValues(1, 1, 1);
    }
    _orbit?.enabled = config.interactive;
    if (config.showSkeleton && _skeleton == null && _ready) _buildSkeleton();
    _skeleton?.visible = config.showSkeleton;
    _selectMotion();
    if (old.motion != config.motion || old.storyText != config.storyText) {
      _mixer?.update(0);
      _sleeveMorph.update();
    }
    _updateSkeleton();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    if (_view == null && _error == null) _createView();
    _view?.visible = _foreground && _tickerEnabled && _error == null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _view?.visible = _foreground && _tickerEnabled && _error == null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    config.playbackPosition?.removeListener(_onPosition);
    _loadTimeout?.cancel();
    _disposeRenderer();
    super.dispose();
  }

  void _disposeRenderer() {
    ++_loadGeneration;
    _loadTimeout?.cancel();
    _skinPalette.dispose();
    _eyeAnimation.dispose();
    _sleeveMorph.dispose();
    _orbit?.dispose();
    _orbit = null;
    _mixer?.stopAllAction();
    for (final action in _actions.values.toList()) {
      _mixer?.uncacheAction(action.clip, _model);
    }
    _view?.dispose();
    _view = null;
    _actions.clear();
    _bones.clear();
    _activeAction = null;
    _mixer = null;
    _model = null;
    _jaw = null;
    _mouth = null;
    _jawRest = null;
    _jawRestPosition = null;
    _skeleton = null;
    _skeletonPositions = null;
  }

  void _restartRenderer() {
    _disposeRenderer();
    if (!mounted) return;
    setState(() {
      _error = null;
      _ready = false;
      _createView();
    });
  }

  void _retry() {
    _compatibilityMode = false;
    _restartRenderer();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'شخصية ${CharacterHelper.getCleanName(config.characterName)} متحركة',
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The platform texture must stay in the tree while it initializes;
          // the fallback is painted above it until the first rendered frame.
          if (_view != null)
            RepaintBoundary(
              child: FittedBox(
                fit: BoxFit.fill,
                child: SizedBox.fromSize(
                  size: _canvasSize,
                  child: _view!.build(),
                ),
              ),
            ),
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'تعذّر عرض الشخصية الآن. أعد المحاولة.',
                  style: const TextStyle(fontSize: 14),
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.rtl,
                ),
              ),
            ),
          if (!_ready && _error == null)
            ColoredBox(
              color: const Color(0xFFF4F7F5),
              child: _GlowingLoader(
                color: CharacterHelper.getColor(config.characterName),
              ),
            ),
          if (_error != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: FilledButton.tonalIcon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('تشغيل العرض ثلاثي الأبعاد'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Contains native initialization/render errors and safely disposes textures
/// created after a route has already been closed.
class _GuardedThreeJS extends three.ThreeJS {
  _GuardedThreeJS({
    required super.size,
    required super.settings,
    required super.setup,
    required super.onSetupComplete,
    required this.onError,
    required this.canRender,
    required this.onFirstFrame,
  });
  final void Function(Object, StackTrace) onError;
  final bool Function() canRender;
  final VoidCallback onFirstFrame;
  bool _initializing = false;
  bool _closing = false;
  bool _failed = false;
  bool _rendering = false;
  bool _firstFrame = false;
  bool _inViewport = true;
  Duration _lastVisibilityCheck = const Duration(seconds: -1);

  @override
  Future<void> initPlatformState() async {
    if (_closing) return;
    _initializing = true;
    try {
      await super.initPlatformState();
    } catch (error, stack) {
      _failed = true;
      if (!_closing) onError(error, stack);
    } finally {
      _initializing = false;
      if (_closing && !_rendering) _finishDispose();
    }
  }

  @override
  Future<void> animate(Duration duration) async {
    if (_closing || _failed || _rendering || !mounted) return;
    if (duration - _lastVisibilityCheck >= const Duration(milliseconds: 200)) {
      _lastVisibilityCheck = duration;
      _inViewport = canRender();
    }
    if (!visible || !_inViewport) {
      clock.getDelta(); // Do not jump forward after a hidden route resumes.
      return;
    }
    _rendering = true;
    try {
      await super.animate(duration);
      if (!_closing && !_firstFrame) {
        _firstFrame = true;
        onFirstFrame();
      }
    } catch (error, stack) {
      _failed = true;
      if (!_closing) onError(error, stack);
    } finally {
      _rendering = false;
      if (_closing && !_initializing) _finishDispose();
    }
  }

  @override
  void dispose() {
    if (_closing) return;
    _closing = true;
    visible = false;
    if (!_initializing && !_rendering) _finishDispose();
  }

  void _finishDispose() {
    final nativeAngle = angle;
    angle = null;
    super.dispose();
    // flutter_angle 0.4.2 assumes EGL initialized even when loading its native
    // library failed. A cleanup exception must not abort the route's disposal.
    try {
      nativeAngle?.dispose([texture]);
    } catch (error) {
      debugPrint(
        'Character native cleanup after initialization failure: $error',
      );
    }
  }
}

class _GlowingLoader extends StatefulWidget {
  final Color color;
  const _GlowingLoader({required this.color});

  @override
  State<_GlowingLoader> createState() => _GlowingLoaderState();
}

class _GlowingLoaderState extends State<_GlowingLoader> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final value = Curves.easeInOutSine.transform(_controller.value);
          return Container(
            height: 100 + (50 * value),
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  widget.color.withValues(alpha: 0.4 + (0.2 * value)),
                  widget.color.withValues(alpha: 0.0),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
