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
  float light = body * clamp(d.y, 0.0, 1.0) * 0.42;
  float shadow = body * clamp(-d.y, 0.0, 1.0) * 0.28;
  float band = exp(-(d.y + 0.82) * (d.y + 0.82) / 0.05) * exp(-d.x * d.x / 0.7);
  return vec2(shadow + band * 0.22, light);
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
  float yIn = smoothstep(0.17, 0.20, p.y) * (1.0 - smoothstep(0.36, 0.39, p.y));
  float side = 1.0 - smoothstep(0.13, 0.20, abs(cx));
  float gate = front * yIn * side;
  vec2 q = vec2(cx, p.y);
  float shadow = clamp((0.007 - abs(cx)) / 0.005, 0.0, 1.0)
    * smoothstep(0.20, 0.225, p.y) * (1.0 - smoothstep(0.34, 0.36, p.y)) * 0.36;
  shadow += clamp((0.0055 - abs(p.y - 0.308)) / 0.0045, 0.0, 1.0) * clamp((0.135 - abs(cx)) / 0.135, 0.0, 1.0) * 0.30;
  shadow += clamp((0.0055 - abs(p.y - 0.264)) / 0.0045, 0.0, 1.0) * clamp((0.140 - abs(cx)) / 0.140, 0.0, 1.0) * 0.30;
  shadow += clamp((0.0055 - abs(p.y - 0.222)) / 0.0045, 0.0, 1.0) * clamp((0.125 - abs(cx)) / 0.125, 0.0, 1.0) * 0.28;
  float light = 0.0;
  vec2 pad = glowPad(q, vec2(-0.058, 0.328), vec2(0.068, 0.026));
  shadow += pad.x; light += pad.y;
  pad = glowPad(q, vec2(0.058, 0.328), vec2(0.068, 0.026));
  shadow += pad.x; light += pad.y;
  pad = glowPad(q, vec2(-0.060, 0.284), vec2(0.072, 0.026));
  shadow += pad.x; light += pad.y;
  pad = glowPad(q, vec2(0.060, 0.284), vec2(0.072, 0.026));
  shadow += pad.x; light += pad.y;
  pad = glowPad(q, vec2(-0.054, 0.242), vec2(0.064, 0.024));
  shadow += pad.x; light += pad.y;
  pad = glowPad(q, vec2(0.054, 0.242), vec2(0.064, 0.024));
  shadow += pad.x; light += pad.y;
  float boltD = glowSeg(q, vec2(-0.030, 0.426), vec2(-0.074, 0.402));
  boltD = min(boltD, glowSeg(q, vec2(-0.074, 0.402), vec2(-0.036, 0.386)));
  boltD = min(boltD, glowSeg(q, vec2(-0.036, 0.386), vec2(-0.080, 0.358)));
  float bolt = clamp((0.0065 - boltD) / 0.0045, 0.0, 1.0);
  return vec3(shadow, light, bolt) * gate;
}
float glowDome(vec2 q, vec2 c, vec2 r) {
  vec2 d = (q - c) / r;
  float body = clamp(1.0 - dot(d, d), 0.0, 1.0);
  return body * body;
}
float glowMuscleHeight(vec3 p, vec3 n) {
  float cx = p.x + 0.062;
  float front = smoothstep(0.18, 0.55, n.z) * smoothstep(0.07, 0.13, p.z);
  float yIn = smoothstep(0.17, 0.20, p.y) * (1.0 - smoothstep(0.36, 0.39, p.y));
  float side = 1.0 - smoothstep(0.13, 0.20, abs(cx));
  float gate = front * yIn * side;
  vec2 q = vec2(cx, p.y);
  float h = 0.0;
  h += glowDome(q, vec2(-0.058, 0.328), vec2(0.068, 0.026)) * 0.010;
  h += glowDome(q, vec2(0.058, 0.328), vec2(0.068, 0.026)) * 0.010;
  h += glowDome(q, vec2(-0.060, 0.284), vec2(0.072, 0.026)) * 0.011;
  h += glowDome(q, vec2(0.060, 0.284), vec2(0.072, 0.026)) * 0.011;
  h += glowDome(q, vec2(-0.054, 0.242), vec2(0.064, 0.024)) * 0.009;
  h += glowDome(q, vec2(0.054, 0.242), vec2(0.064, 0.024)) * 0.009;
  float reach = 1.0 - smoothstep(0.03, 0.16, abs(cx));
  h -= exp(-cx * cx / 0.000045) * 0.003 * smoothstep(0.20, 0.24, p.y) * (1.0 - smoothstep(0.34, 0.36, p.y));
  h -= exp(-(p.y - 0.306) * (p.y - 0.306) / 0.000030) * 0.003 * reach;
  h -= exp(-(p.y - 0.262) * (p.y - 0.262) / 0.000030) * 0.003 * reach;
  h -= exp(-(p.y - 0.222) * (p.y - 0.222) / 0.000030) * 0.002 * reach;
  return h * gate;
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
      material.customProgramCacheKey = () => 'glow-skin-palette-v8';
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
                  '#include <beginnormal_vertex>',
                  '''
#include <beginnormal_vertex>
float glowHdx = glowMuscleHeight(position + vec3(0.004, 0.0, 0.0), normal) - glowMuscleHeight(position - vec3(0.004, 0.0, 0.0), normal);
float glowHdy = glowMuscleHeight(position + vec3(0.0, 0.004, 0.0), normal) - glowMuscleHeight(position - vec3(0.0, 0.004, 0.0), normal);
objectNormal = normalize(objectNormal - vec3(glowHdx, glowHdy, 0.0) * (36.0 * glowMuscles));
''',
                )
                .replaceFirst(
                  '#include <begin_vertex>',
                  '''
#include <begin_vertex>
vGlowSkinRegion = _glow_skin_region;
vGlowMuscle = glowMuscleDraw(position, normal);
transformed += normal * glowMuscleHeight(position, normal) * glowMuscles;
''',
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
  float muscleOn = glowMuscles;
  diffuseColor.rgb *= mix(1.0, 0.62, clamp(vGlowMuscle.x, 0.0, 1.0) * muscleOn);
  diffuseColor.rgb *= mix(1.0, 1.28, clamp(vGlowMuscle.y, 0.0, 1.0) * muscleOn);
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
