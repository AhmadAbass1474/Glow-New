import 'package:flutter/material.dart';
import 'package:three_js/three_js.dart' as three;

/// Recolors only green skin in the supplied atlas. Geometry, source textures,
/// normal/roughness maps and the animation mixer stay shared across identities.
class CharacterSkinPalette {
  final _target = three.Color(0xffffff);
  late final Map<String, dynamic> _colorUniform = {'value': _target};
  final Map<String, dynamic> _strengthUniform = {'value': 0.0};
  final Map<String, dynamic> _muscleUniform = {'value': 0.0};
  final _materials = <three.Material>[];

  static const _muscleGlsl = '''
vec2 glowPad(vec2 q, vec2 c, vec2 r) {
  vec2 d = (q - c) / r;
  float dist = length(d);
  float body = clamp((1.0 - dist) / 0.28, 0.0, 1.0);
  body = body * body * (3.0 - 2.0 * body);
  float light = body * clamp(d.y, 0.0, 1.0) * 0.85;
  float shadow = body * clamp(-d.y, 0.0, 1.0) * 0.55;
  float band = exp(-(d.y + 0.82) * (d.y + 0.82) / 0.05) * exp(-d.x * d.x / 0.7);
  return vec2(shadow + band * 0.55, light);
}
float glowSeg(vec2 p, vec2 a, vec2 b) {
  vec2 pa = p - a;
  vec2 ba = b - a;
  float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-5), 0.0, 1.0);
  return length(pa - ba * h);
}
vec3 glowMuscleDraw(vec3 p, vec3 n) {
  float cx = p.x + 0.062;
  float front = smoothstep(0.18, 0.55, n.z) * smoothstep(0.07, 0.13, p.z);
  float yIn = smoothstep(0.17, 0.20, p.y) * (1.0 - smoothstep(0.43, 0.47, p.y));
  float side = 1.0 - smoothstep(0.10, 0.155, abs(cx));
  float gate = front * yIn * side;
  vec2 q = vec2(cx, p.y);
  float shadow = clamp((0.007 - abs(cx)) / 0.005, 0.0, 1.0)
    * smoothstep(0.20, 0.225, p.y) * (1.0 - smoothstep(0.41, 0.43, p.y)) * 0.75;
  shadow += clamp((0.012 - abs(p.y - 0.350)) / 0.010, 0.0, 1.0)
    * clamp((0.105 - abs(cx)) / 0.08, 0.0, 1.0) * 0.65;
  shadow += clamp((0.0055 - abs(p.y - 0.308)) / 0.0045, 0.0, 1.0) * clamp((0.090 - abs(cx)) / 0.090, 0.0, 1.0) * 0.55;
  shadow += clamp((0.0055 - abs(p.y - 0.264)) / 0.0045, 0.0, 1.0) * clamp((0.096 - abs(cx)) / 0.096, 0.0, 1.0) * 0.55;
  shadow += clamp((0.0055 - abs(p.y - 0.222)) / 0.0045, 0.0, 1.0) * clamp((0.086 - abs(cx)) / 0.086, 0.0, 1.0) * 0.55;
  vec2 pad = glowPad(q, vec2(-0.056, 0.400), vec2(0.050, 0.034));
  shadow += pad.x; float light = pad.y;
  pad = glowPad(q, vec2(0.056, 0.400), vec2(0.050, 0.034));
  shadow += pad.x; light += pad.y;
  pad = glowPad(q, vec2(-0.046, 0.328), vec2(0.042, 0.022));
  shadow += pad.x; light += pad.y;
  pad = glowPad(q, vec2(0.046, 0.328), vec2(0.042, 0.022));
  shadow += pad.x; light += pad.y;
  pad = glowPad(q, vec2(-0.048, 0.284), vec2(0.046, 0.022));
  shadow += pad.x; light += pad.y;
  pad = glowPad(q, vec2(0.048, 0.284), vec2(0.046, 0.022));
  shadow += pad.x; light += pad.y;
  pad = glowPad(q, vec2(-0.044, 0.242), vec2(0.042, 0.020));
  shadow += pad.x; light += pad.y;
  pad = glowPad(q, vec2(0.044, 0.242), vec2(0.042, 0.020));
  shadow += pad.x; light += pad.y;
  float boltD = glowSeg(q, vec2(-0.030, 0.426), vec2(-0.074, 0.402));
  boltD = min(boltD, glowSeg(q, vec2(-0.074, 0.402), vec2(-0.036, 0.386)));
  boltD = min(boltD, glowSeg(q, vec2(-0.036, 0.386), vec2(-0.080, 0.358)));
  float bolt = clamp((0.0065 - boltD) / 0.0045, 0.0, 1.0);
  return vec3(shadow, light, bolt) * gate;
}
''';

  void attach(three.Object3D model) {
    model.traverse((object) {
      if (object is! three.Mesh ||
          object.geometry?.attributes['_glow_skin_region'] == null) {
        return;
      }
      final material = object.material;
      if (material == null || _materials.contains(material)) return;
      final name = material.name;
      if (name == 'Hat' ||
          name == 'HatBand' ||
          name == 'HatTrim' ||
          name == 'HatSkin') {
        return;
      }
      _materials.add(material);
      material.customProgramCacheKey = () => 'glow-skin-palette-v3';
      material.onBeforeCompile = (dynamic shader, dynamic renderer) {
        shader.uniforms ??= <String, dynamic>{};
        shader.uniforms['glowSkinTarget'] = _colorUniform;
        shader.uniforms['glowSkinStrength'] = _strengthUniform;
        shader.uniforms['glowMuscles'] = _muscleUniform;
        shader.vertexShader =
            '''
attribute float _glow_skin_region;
varying float vGlowSkinRegion;
varying vec3 vGlowMuscle;
uniform float glowMuscles;
$_muscleGlsl
${shader.vertexShader}
'''
                .replaceFirst(
                  '#include <begin_vertex>',
                  '#include <begin_vertex>\nvGlowSkinRegion = _glow_skin_region;\nvGlowMuscle = glowMuscleDraw(position, normal);',
                );
        shader.fragmentShader =
            '''
uniform vec3 glowSkinTarget;
uniform float glowSkinStrength;
uniform float glowMuscles;
varying float vGlowSkinRegion;
varying vec3 vGlowMuscle;
${shader.fragmentShader}
'''
                .replaceFirst('#include <map_fragment>', '''
#include <map_fragment>
#ifdef USE_MAP
  float greenDominance = (diffuseColor.g - max(diffuseColor.r, diffuseColor.b))
    / max(diffuseColor.g, 0.0001);
  float skinMask = smoothstep(0.20, 0.45, greenDominance)
    * clamp(vGlowSkinRegion, 0.0, 1.0) * glowSkinStrength;
  // Preserve texture luminance and all subsequent PBR lighting. The reference
  // is the linear luminance of the saved green identity (#22592A).
  float textureShade = dot(diffuseColor.rgb, vec3(0.2126, 0.7152, 0.0722)) / 0.07652005545;
  diffuseColor.rgb = mix(diffuseColor.rgb, glowSkinTarget * textureShade, skinMask);
  float muscleCream = (1.0 - smoothstep(0.08, 0.30, greenDominance))
    * smoothstep(0.55, 0.80, max(diffuseColor.r, diffuseColor.g));
  float muscleOn = muscleCream * glowMuscles;
  diffuseColor.rgb *= mix(1.0, 0.60, clamp(vGlowMuscle.x, 0.0, 1.0) * muscleOn);
  diffuseColor.rgb *= mix(1.0, 1.12, clamp(vGlowMuscle.y, 0.0, 1.0) * muscleOn);
  diffuseColor.rgb = mix(diffuseColor.rgb, vec3(1.0, 0.75, 0.08), clamp(vGlowMuscle.z, 0.0, 1.0) * muscleOn);
#endif
''');
      };
      material.needsUpdate = true;
    });
  }

  void setMuscles(bool enabled) {
    _muscleUniform['value'] = enabled ? 1.0 : 0.0;
    for (final material in _materials) {
      material.uniformsNeedUpdate = true;
    }
  }

  void setColor(Color color, {required bool originalGreen}) {
    _target.setRGB(color.r, color.g, color.b).convertSRGBToLinear();
    _strengthUniform['value'] = originalGreen ? 0.0 : 1.0;
    for (final material in _materials) {
      material.uniformsNeedUpdate = true;
    }
  }

  void dispose() {
    // Material/GPU ownership remains with the existing renderer lifecycle.
    for (final material in _materials) {
      material.onBeforeCompile = null;
    }
    _materials.clear();
  }
}
