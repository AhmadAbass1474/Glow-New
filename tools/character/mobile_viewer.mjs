import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';

// Bundled as one local classic script: no CDN, network import or model URL.
const send = (type, detail = {}) => window.GlowCharacter?.postMessage(JSON.stringify({ type, ...detail }));
let renderer, scene, camera, controls, model, mixer, skeleton, jaw, jawRest, lids;
let frame = 0, last = 0, time = 0, motionTime = 0, previousMotion;
let active, ready = false, disposed = false, firstFrame = false, failed = false;
let sampledFrames = 0, sampleStart = 0;
let state = {
  motion: 'Idle', playing: true, speaking: false, visible: true, interactive: true,
  skeleton: false, hat: true, hatColor: '#2c2c2e', muscles: false, glasses: false, cameraFit: 1.10, originalGreen: true, color: '#22592a', position: 0,
};
const actions = new Map(), eyes = [];
const HAT_MATERIALS = new Set(['Hat', 'HatBand', 'HatTrim', 'HatSkin']);
const target = { value: new THREE.Color() }, strength = { value: 0 }, muscles = { value: 0 };
const MUSCLE_GLSL = `
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
`;
let nextBlink = 0.7, blinkStart = -10, blinkDuration = .26, nextLook = 1.2;
let lookX = 0, lookY = 0, gazeX = 0, gazeY = 0, squint = 0, jawRestPos = null;
const eyeRotation = new THREE.Euler(), jawRotation = new THREE.Quaternion();
const jawAxis = new THREE.Vector3(1, 0, 0);
const smooth = t => { t = THREE.MathUtils.clamp(t, 0, 1); return t * t * (3 - 2 * t); };
function blink(delay) {
  const p = (time - blinkStart - delay) / blinkDuration;
  if (p < 0 || p > 1) return 0;
  if (p < .3) return smooth(p / .3);
  return p < .4 ? 1 : 1 - smooth((p - .4) / .6);
}
function animateEyes(dt) {
  if (eyes.length !== 2 || !lids) return;
  if (state.motion !== previousMotion) {
    previousMotion = state.motion; motionTime = 0;
    nextLook = time + .2; nextBlink = Math.min(nextBlink, time + .35);
  }
  motionTime += dt;
  if (time >= nextBlink) {
    blinkStart = time; blinkDuration = state.motion === 'Sad' ? .34 : .24 + Math.random() * .06;
    nextBlink = time + (Math.random() < .1 ? .42 : 2.6 + Math.random() * 3);
  }
  if (time >= nextLook) {
    lookX = (Math.random() - .5) * .055; lookY = (Math.random() - .5) * .025;
    nextLook = time + 1.6 + Math.random() * 2.2;
  }
  let x = lookX, y = lookY, close = 0;
  switch (state.motion) {
    case 'Thinking': x += .065; y -= .05; close = .08; break;
    case 'Sad': x *= .3; y += .06; close = .24; break;
    case 'Laugh': close = .48 + .1 * Math.sin(motionTime * 5.2); y -= .015; break;
    case 'Happy': close = .16; break;
    case 'Smile': close = .07; break;
    case 'Victory': y -= .04; close = .08; break;
    case 'Wave': x += .025 * Math.sin(motionTime * 1.4); break;
  }
  const ease = 1 - Math.exp(-dt * 16);
  gazeX += (THREE.MathUtils.clamp(x, -.1, .1) - gazeX) * ease;
  gazeY += (THREE.MathUtils.clamp(y, -.08, .08) - gazeY) * ease;
  squint += (close - squint) * (1 - Math.exp(-dt * 9));
  const amounts = [Math.max(squint, blink(0)), Math.max(squint, blink(.012))];
  lids.visible = Math.max(...amounts) > .002;
  for (let i = 0; i < 2; ++i) {
    const c = amounts[i];
    eyeRotation.set(gazeY * (1 - c), gazeX * (1 - c), 0);
    eyes[i].quaternion.setFromEuler(eyeRotation);
    lids.morphTargetInfluences[i * 2] = Math.min(c * 2, 2 - c * 2);
    lids.morphTargetInfluences[i * 2 + 1] = Math.max(0, c * 2 - 1);
  }
}
function palette(mesh, seen) {
  if (!mesh.geometry?.getAttribute('_glow_skin_region')) return;
  for (const material of [mesh.material].flat()) {
    if (!material || seen.has(material) || HAT_MATERIALS.has(material.name)) continue;
    seen.add(material);
    material.customProgramCacheKey = () => 'glow-skin-palette-v8';
    material.onBeforeCompile = shader => {
      shader.uniforms.glowSkinTarget = target;
      shader.uniforms.glowSkinStrength = strength;
      shader.uniforms.glowMuscles = muscles;
      shader.vertexShader = 'attribute float _glow_skin_region;\nvarying float vGlowSkinRegion;\nvarying vec3 vGlowMuscle;\nuniform float glowMuscles;\n' + MUSCLE_GLSL + shader.vertexShader;
      shader.vertexShader = shader.vertexShader.replace('#include <beginnormal_vertex>', '#include <beginnormal_vertex>\nfloat glowHdx = glowMuscleHeight(position + vec3(0.004, 0.0, 0.0), normal) - glowMuscleHeight(position - vec3(0.004, 0.0, 0.0), normal);\nfloat glowHdy = glowMuscleHeight(position + vec3(0.0, 0.004, 0.0), normal) - glowMuscleHeight(position - vec3(0.0, 0.004, 0.0), normal);\nobjectNormal = normalize(objectNormal - vec3(glowHdx, glowHdy, 0.0) * (36.0 * glowMuscles));');
      shader.vertexShader = shader.vertexShader.replace('#include <begin_vertex>', '#include <begin_vertex>\nvGlowSkinRegion = _glow_skin_region;\nvGlowMuscle = glowMuscleDraw(position, normal);\ntransformed += normal * glowMuscleHeight(position, normal) * glowMuscles;');
      shader.fragmentShader = 'uniform vec3 glowSkinTarget;\nuniform float glowSkinStrength;\nuniform float glowMuscles;\nvarying float vGlowSkinRegion;\nvarying vec3 vGlowMuscle;\n' + shader.fragmentShader;
      shader.fragmentShader = shader.fragmentShader.replace('#include <map_fragment>', `#include <map_fragment>
        #ifdef USE_MAP
        float greenDominance = (diffuseColor.g - max(diffuseColor.r, diffuseColor.b)) / max(diffuseColor.g, 0.0001);
        float mask = smoothstep(0.20, 0.45, greenDominance) * clamp(vGlowSkinRegion, 0.0, 1.0) * glowSkinStrength;
        float shade = dot(diffuseColor.rgb, vec3(0.2126, 0.7152, 0.0722)) / 0.07652005545;
        diffuseColor.rgb = mix(diffuseColor.rgb, glowSkinTarget * shade, mask);
        float muscleOn = glowMuscles;
        diffuseColor.rgb *= mix(1.0, 0.62, clamp(vGlowMuscle.x, 0.0, 1.0) * muscleOn);
        diffuseColor.rgb *= mix(1.0, 1.28, clamp(vGlowMuscle.y, 0.0, 1.0) * muscleOn);
        diffuseColor.rgb = mix(diffuseColor.rgb, vec3(1.0, 0.75, 0.08), clamp(vGlowMuscle.z, 0.0, 1.0) * muscleOn);
        #endif`);
    };
  }
}
function applyTalkingMouth() {
  if (!jaw || !jawRest || !jawRestPos) return;
  const sad = state.motion === 'Sad';
  jaw.position.set(jawRestPos.x, jawRestPos.y + (sad ? 0.024 : 0), jawRestPos.z);
  if (sad) jaw.quaternion.identity();
  else {
    const u = (time % 2) / 2;
    const syllable = Math.sin(Math.PI * 4 * u) ** 2;
    jaw.quaternion.setFromAxisAngle(jawAxis, 0.08 + 0.30 * syllable);
  }
}
function selectMotion() {
  const next = actions.get(state.motion) ?? actions.get('Idle') ?? actions.values().next().value;
  if (!next || next === active) return;
  next.reset().setEffectiveWeight(1).play();
  if (active) next.crossFadeFrom(active, .3, false);
  active = next;
}
function applyGlasses() {
  if (!model) return;
  const show = state.glasses === true;
  model.traverse(object => {
    for (const material of [object.material].flat().filter(Boolean)) {
      if (material.name === 'Glasses') object.visible = show;
    }
  });
}
function hideFittedMesh() {
  if (!model) return;
  model.traverse(object => {
    for (const material of [object.material].flat().filter(Boolean)) {
      if (material.name === 'Muscles') object.visible = false;
    }
  });
}
function applyHat() {
  if (!model) return;
  const show = state.hat !== false;
  const tint = new THREE.Color(state.hatColor || '#2c2c2e');
  const skin = new THREE.Color(state.color || '#22592a');
  model.traverse(object => {
    for (const material of [object.material].flat().filter(Boolean)) {
      const name = material.name;
      if (!HAT_MATERIALS.has(name)) continue;
      object.visible = show;
      if (!show) continue;
      if (name === 'HatSkin') material.color.copy(skin);
      else {
        const shade = name === 'HatBand' ? .45 : 1;
        material.color.setRGB(tint.r * shade, tint.g * shade, tint.b * shade);
      }
      material.transparent = false;
      material.opacity = 1;
      material.depthWrite = true;
      material.needsUpdate = true;
    }
  });
}
function resize() {
  if (!renderer || !camera) return;
  const w = Math.max(1, innerWidth), h = Math.max(1, innerHeight);
  // Supersampled buffer plus MSAA. The long side stays at 3072 so the
  // silhouette stays sharp without an 8K framebuffer that stalls the GPU.
  const longSide = Math.max(w, h);
  renderer.setPixelRatio(Math.max(1, Math.min(devicePixelRatio || 1, 3, 3072 / longSide)));
  renderer.setSize(w, h, false);
  camera.aspect = w / h; camera.updateProjectionMatrix();
  const fit = Number(state.cameraFit) > 0 ? Number(state.cameraFit) : 1.10;
  const distance = Math.max(3.5, (model?.userData.frameWidth ?? 3.5) / camera.aspect) / (2 * Math.tan(38 * Math.PI / 360)) * fit;
  camera.position.set(.32, 2.06, distance); controls?.update();
  draw();
}
function draw() {
  if (ready && !disposed && state.visible) renderer.render(scene, camera);
}
function schedule() {
  if (!frame && ready && !disposed && !failed && state.visible && !document.hidden) frame = requestAnimationFrame(tick);
}
function tick(now) {
  frame = 0;
  if (disposed || !state.visible || document.hidden) { last = 0; return; }
  const dt = last ? Math.min((now - last) / 1000, .08) : 0; last = now;
  const orbitChanged = controls.update();
  if (state.playing) {
    time += dt; state.position += dt;
    selectMotion(); mixer.update(dt); animateEyes(dt);
    applyTalkingMouth();
  }
  draw();
  if (failed) return;
  if (!firstFrame) { firstFrame = true; send('ready', { triangles: renderer.info.render.triangles, clips: [...actions.keys()] }); }
  if (state.diagnostics) {
    if (!sampleStart) sampleStart = now;
    sampledFrames++;
    if (now - sampleStart >= 5000) {
      send('sample', { fps: +(sampledFrames * 1000 / (now - sampleStart)).toFixed(1), triangles: renderer.info.render.triangles, motion: state.motion, actionTime: active?.time, textures: renderer.info.memory.textures });
      sampledFrames = 0; sampleStart = now;
    }
  }
  if (state.playing || orbitChanged) schedule();
}
function _localUrlAllowed(url) {
  return url.startsWith('blob:') ||
    url.startsWith('data:') ||
    url.startsWith('file:') ||
    url.startsWith('./') ||
    !url.includes('://');
}
function _resourceManager() {
  const manager = new THREE.LoadingManager();
  manager.setURLModifier(url => {
    if (_localUrlAllowed(url)) return url;
    throw new Error('External model resources are not permitted');
  });
  return manager;
}
async function _mountGltf(data) {
  if (disposed) return;
  model = data.scene; scene.add(model);
  const seen = new Set();
  const maxAniso = renderer.capabilities.getMaxAnisotropy?.() ?? 1;
  model.traverse(object => {
    if (object.isSkinnedMesh) object.frustumCulled = false;
    palette(object, seen);
    if (object.morphTargetDictionary?.BlinkLeftClosed !== undefined) { lids = object; lids.visible = false; }
    for (const material of [object.material].flat().filter(Boolean)) {
      if (material.map) {
        material.map.colorSpace = THREE.SRGBColorSpace;
        material.map.anisotropy = Math.min(16, maxAniso);
        material.map.needsUpdate = true;
      }
      if (material.normalMap) {
        material.normalMap.anisotropy = Math.min(16, maxAniso);
        material.normalMap.needsUpdate = true;
      }
      material.needsUpdate = true;
    }
  });
  for (const name of ['EyeLeft', 'EyeRight']) { const eye = model.getObjectByName(name); if (eye) eyes.push(eye); }
  jaw = model.getObjectByName('Jaw'); jawRest = jaw?.quaternion.clone(); jawRestPos = jaw?.position.clone();
  const bounds = new THREE.Box3().setFromObject(model), size = bounds.getSize(new THREE.Vector3()), center = bounds.getCenter(new THREE.Vector3());
  if (!(size.y > 0)) throw new Error('Empty model bounds');
  const scale = 3.5 / size.y;
  model.scale.setScalar(scale); model.position.set(-center.x * scale, -bounds.min.y * scale, -center.z * scale);
  model.userData.frameWidth = size.x * scale;
  mixer = new THREE.AnimationMixer(model);
  for (const clip of data.animations) actions.set(clip.name, mixer.clipAction(clip));
  applyHat();
  applyGlasses();
  hideFittedMesh();
  update(state); selectMotion(); mixer.update(0); ready = true; send('loaded'); resize(); schedule();
}
async function loadLocal(fileName) {
  try {
    const data = await new GLTFLoader(_resourceManager()).loadAsync(fileName);
    await _mountGltf(data);
  } catch (error) { fail(error); }
}
let buffer = null;
function begin(length) { buffer = new Uint8Array(length); }
function appendBatch(parts) {
  for (const [encoded, offset] of parts) {
    const binary = atob(encoded);
    const view = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; ++i) view[i] = binary.charCodeAt(i);
    buffer.set(view, offset);
  }
}
async function loadBuffered() {
  try {
    const bytes = buffer.buffer; buffer = null;
    const data = await new GLTFLoader(_resourceManager()).parseAsync(bytes, '');
    await _mountGltf(data);
  } catch (error) { fail(error); }
}
async function loadFromBase64(encoded) {
  try {
    const binary = atob(encoded);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; ++i) bytes[i] = binary.charCodeAt(i);
    const data = await new GLTFLoader(_resourceManager()).parseAsync(bytes.buffer, '');
    await _mountGltf(data);
  } catch (error) { fail(error); }
}
function update(next) {
  const wasSpeaking = state.speaking;
  const seek = next.seek === true;
  const fitChanged = next.cameraFit !== undefined && next.cameraFit !== state.cameraFit;
  const hatChanged = next.hat !== undefined || next.hatColor !== undefined || next.color !== undefined;
  const glassesChanged = next.glasses !== undefined;
  state = { ...state, ...next };
  target.value.set(state.color); strength.value = state.originalGreen ? 0 : 1;
  muscles.value = state.muscles ? 1 : 0;
  if (next.muscles !== undefined || next.seek === true) hideFittedMesh();
  if (controls) controls.enabled = state.interactive;
  if (state.skeleton && model && !skeleton) { skeleton = new THREE.SkeletonHelper(model); scene.add(skeleton); }
  if (skeleton) skeleton.visible = state.skeleton;
  if (hatChanged || next.seek === true) applyHat();
  if (glassesChanged || next.seek === true) applyGlasses();
  if (mixer) {
    selectMotion();
    if (seek) { mixer.stopAllAction(); active = null; selectMotion(); if (active) active.time = state.position % active.getClip().duration; mixer.update(0); }
    if (wasSpeaking && !state.speaking && jaw && jawRest && jawRestPos) {
      jaw.quaternion.copy(jawRest);
      jaw.position.copy(jawRestPos);
      mixer.update(0);
    }
  }
  if (fitChanged) resize();
  if (!state.visible) { cancelAnimationFrame(frame); frame = 0; last = 0; }
  else schedule();
}
function fail(error) { if (disposed || failed) return; failed = true; cancelAnimationFrame(frame); frame = 0; send('error', { message: String(error?.message ?? error) }); }
function dispose() {
  if (disposed) return;
  disposed = true; ready = false;
  cancelAnimationFrame(frame); controls?.dispose(); mixer?.stopAllAction();
  const textures = new Set(), materials = new Set(), geometries = new Set();
  scene?.traverse(object => {
    if (object.geometry) geometries.add(object.geometry);
    for (const material of [object.material].flat().filter(Boolean)) {
      materials.add(material); for (const value of Object.values(material)) if (value?.isTexture) textures.add(value);
    }
  });
  for (const texture of textures) { texture.source?.data?.close?.(); texture.dispose(); }
  for (const material of materials) material.dispose();
  for (const geometry of geometries) geometry.dispose();
  renderer?.dispose(); renderer?.forceContextLoss();
}
window.GlowViewer = { loadLocal, loadFromBase64, begin, appendBatch, loadBuffered, update, dispose };
try {
  // MSAA on: WebView GL is stable (unlike native flutter_angle FBOs).
  renderer = new THREE.WebGLRenderer({
    antialias: true,
    alpha: false,
    powerPreference: 'high-performance',
    preserveDrawingBuffer: false,
  });
  renderer.setClearColor(0xf4f7f5);
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.NoToneMapping;
  // Keep lighting response close to the web three_js viewer.
  if ('physicallyCorrectLights' in renderer) renderer.physicallyCorrectLights = false;
  renderer.debug.onShaderError = () => fail(new Error('Character shader compilation failed'));
  document.body.appendChild(renderer.domElement);
  renderer.domElement.addEventListener('webglcontextlost', event => { event.preventDefault(); fail(new Error('Graphics context lost')); });
  scene = new THREE.Scene(); camera = new THREE.PerspectiveCamera(38, 1, .05, 100);
  controls = new OrbitControls(camera, renderer.domElement); controls.enablePan = false; controls.enableZoom = false; controls.enableDamping = true; controls.minDistance = 3; controls.maxDistance = 16; controls.target.set(0, 1.78, 0);
  controls.addEventListener('change', () => { if (!state.playing) { draw(); schedule(); } });
  scene.add(new THREE.HemisphereLight(0xeaf6ff, 0x8d8270, .85));
  const key = new THREE.DirectionalLight(0xfff2dc, 1.85); key.position.set(-3, 6, 6); scene.add(key);
  const fill = new THREE.DirectionalLight(0xffffff, .35); fill.position.set(2, 2, 4); scene.add(fill);
  const rim = new THREE.DirectionalLight(0xd7efff, .7); rim.position.set(4, 3, -3); scene.add(rim);
  for (let i = 0; i < 5; i++) {
    const shadow = new THREE.Mesh(new THREE.SphereGeometry(1, 32, 8), new THREE.MeshBasicMaterial({ color: 0x31483b, transparent: true, opacity: .025, depthWrite: false }));
    shadow.position.set(0, -.04 - i * .001, 0); shadow.scale.set(.6 + i * .1, .018, .38 + i * .07); scene.add(shadow);
  }
  addEventListener('resize', resize);
  document.addEventListener('visibilitychange', () => { last = 0; if (document.hidden) { cancelAnimationFrame(frame); frame = 0; } else schedule(); });
  addEventListener('pagehide', dispose);
  addEventListener('error', event => fail(event.error ?? event.message));
  addEventListener('unhandledrejection', event => fail(event.reason));
  send('boot');
} catch (error) { fail(error); }
