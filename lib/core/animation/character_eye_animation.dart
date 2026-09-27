import 'dart:math' as math;
import 'package:three_js/three_js.dart' as three;
import 'story_motion.dart';

/// Small conjugate eye movements and asymmetric, two-stage lid closures.
/// Operates on the supplied rig; no mesh/texture allocations during playback.
class CharacterEyeAnimation {
  final _random = math.Random();
  final _rotation = three.Euler();
  final _eyes = <three.Object3D>[];
  three.Mesh? _lids;
  CharacterMotion? _motion;
  double _time = 0, _motionTime = 0;
  double _nextBlink = 0.7, _blinkStart = -10, _blinkDuration = .26;
  double _nextLook = 1.2, _lookX = 0, _lookY = 0;
  double _gazeX = 0, _gazeY = 0, _squint = 0;

  void attach(three.Object3D model) {
    dispose();
    for (final name in ['EyeLeft', 'EyeRight']) {
      final eye = model.getObjectByName(name);
      if (eye != null) _eyes.add(eye);
    }
    model.traverse((object) {
      if (object is three.Mesh &&
          (object.name == 'EyeLids' ||
              object.morphTargetDictionary?.containsKey('BlinkLeftClosed') ==
                  true)) {
        _lids = object;
        object.visible = false;
      }
    });
  }

  static double _smooth(double t) {
    t = t.clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  double _blink(double delay) {
    final phase = (_time - _blinkStart - delay) / _blinkDuration;
    if (phase < 0 || phase > 1) return 0;
    if (phase < .30) return _smooth(phase / .30);
    if (phase < .40) return 1;
    return 1 - _smooth((phase - .40) / .60);
  }

  void update(double dt, CharacterMotion motion) {
    if (_eyes.length != 2 || _lids == null) return;
    _time += dt;
    _motionTime += dt;
    if (_motion != motion) {
      _motion = motion;
      _motionTime = 0;
      _nextLook = _time + .20;
      // A brief settling blink accompanies an expression change.
      _nextBlink = math.min(_nextBlink, _time + .35);
    }
    if (_time >= _nextBlink) {
      _blinkStart = _time;
      _blinkDuration = motion == CharacterMotion.sad
          ? .34
          : .24 + _random.nextDouble() * .06;
      final doubleBlink = _random.nextDouble() < .10;
      _nextBlink =
          _time + (doubleBlink ? .42 : 2.6 + _random.nextDouble() * 3.0);
    }
    if (_time >= _nextLook) {
      _lookX = (_random.nextDouble() - .5) * .055;
      _lookY = (_random.nextDouble() - .5) * .025;
      _nextLook = _time + 1.6 + _random.nextDouble() * 2.2;
    }
    var x = _lookX, y = _lookY, squint = 0.0;
    switch (motion) {
      case CharacterMotion.thinking:
        x += .065;
        y -= .050;
        squint = .08;
      case CharacterMotion.sad:
        x *= .3;
        y += .060;
        squint = .24;
      case CharacterMotion.laugh:
        squint = .48 + .10 * math.sin(_motionTime * 5.2);
        y -= .015;
      case CharacterMotion.happy:
        squint = .16;
      case CharacterMotion.smile:
        squint = .07;
      case CharacterMotion.victory:
        y -= .04;
        squint = .08;
      case CharacterMotion.wave:
        x += .025 * math.sin(_motionTime * 1.4);
      case CharacterMotion.idle:
      case CharacterMotion.talk:
      case CharacterMotion.walk:
        break;
    }
    final gazeEase = 1 - math.exp(-dt * 16);
    _gazeX += (x.clamp(-.10, .10) - _gazeX) * gazeEase;
    _gazeY += (y.clamp(-.08, .08) - _gazeY) * gazeEase;
    _squint += (squint - _squint) * (1 - math.exp(-dt * 9));
    final left = math.max(_squint, _blink(0));
    final right = math.max(_squint, _blink(.012));
    _lids!.visible = math.max(left, right) > .002;
    for (var i = 0; i < 2; i++) {
      final close = i == 0 ? left : right;
      // Settle gaze behind the lids to prevent an iris grazing a closing lid.
      final gazeAmount = 1 - close;
      _rotation.set(_gazeY * gazeAmount, _gazeX * gazeAmount, 0);
      _eyes[i].quaternion.setFromEuler(_rotation);
      _lids!.morphTargetInfluences[i * 2] = math.min(close * 2, 2 - close * 2);
      _lids!.morphTargetInfluences[i * 2 + 1] = math.max(0.0, close * 2 - 1);
    }
  }

  void dispose() {
    _eyes.clear();
    _lids = null;
    _motion = null;
    _time = _motionTime = 0;
    _gazeX = _gazeY = _squint = _lookX = _lookY = 0;
    _nextBlink = 0.7;
    _blinkStart = -10;
    _nextLook = 1.2;
  }
}
