import 'package:flutter/material.dart';
import 'package:three_js/three_js.dart' as three;

/// Recolors only green skin in the supplied atlas. Geometry, source textures,
/// normal/roughness maps and the animation mixer stay shared across identities.
class CharacterSkinPalette {
  final _target = three.Color(0xffffff);
  late final Map<String, dynamic> _colorUniform = {'value': _target};
  final Map<String, dynamic> _strengthUniform = {'value': 0.0};
  final _materials = <three.Material>[];

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
      material.customProgramCacheKey = () => 'glow-skin-palette-v1';
      material.onBeforeCompile = (dynamic shader, dynamic renderer) {
        shader.uniforms ??= <String, dynamic>{};
        shader.uniforms['glowSkinTarget'] = _colorUniform;
        shader.uniforms['glowSkinStrength'] = _strengthUniform;
        shader.vertexShader =
            '''
attribute float _glow_skin_region;
varying float vGlowSkinRegion;
${shader.vertexShader}
'''
                .replaceFirst(
                  '#include <begin_vertex>',
                  '#include <begin_vertex>\nvGlowSkinRegion = _glow_skin_region;',
                );
        shader.fragmentShader =
            '''
uniform vec3 glowSkinTarget;
uniform float glowSkinStrength;
varying float vGlowSkinRegion;
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
#endif
''');
      };
      material.needsUpdate = true;
    });
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
