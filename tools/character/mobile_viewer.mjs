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
  skeleton: false, hat: true, hatColor: '#2c2c2e', originalGreen: true, color: '#22592a', position: 0,
};
const actions = new Map(), eyes = [];
const HAT_MATERIALS = new Set(['Hat', 'HatBand', 'HatTrim', 'HatSkin']);
const target = { value: new THREE.Color() }, strength = { value: 0 };
let nextBlink = 1.8, blinkStart = -10, blinkDuration = .26, nextLook = 1.2;
let lookX = 0, lookY = 0, gazeX = 0, gazeY = 0, squint = 0, speechBlend = 0;
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
    material.customProgramCacheKey = () => 'glow-skin-palette-v1';
    material.onBeforeCompile = shader => {
      shader.uniforms.glowSkinTarget = target; shader.uniforms.glowSkinStrength = strength;
      shader.vertexShader = 'attribute float _glow_skin_region;\nvarying float vGlowSkinRegion;\n' + shader.vertexShader;
      shader.vertexShader = shader.vertexShader.replace('#include <begin_vertex>', '#include <begin_vertex>\nvGlowSkinRegion = _glow_skin_region;');
      shader.fragmentShader = 'uniform vec3 glowSkinTarget;\nuniform float glowSkinStrength;\nvarying float vGlowSkinRegion;\n' + shader.fragmentShader;
      shader.fragmentShader = shader.fragmentShader.replace('#include <map_fragment>', `#include <map_fragment>
        #ifdef USE_MAP
        float greenDominance = (diffuseColor.g - max(diffuseColor.r, diffuseColor.b)) / max(diffuseColor.g, 0.0001);
        float mask = smoothstep(0.20, 0.45, greenDominance) * clamp(vGlowSkinRegion, 0.0, 1.0) * glowSkinStrength;
        float shade = dot(diffuseColor.rgb, vec3(0.2126, 0.7152, 0.0722)) / 0.07652005545;
        diffuseColor.rgb = mix(diffuseColor.rgb, glowSkinTarget * shade, mask);
        #endif`);
    };
  }
}
function selectMotion() {
  const next = actions.get(state.motion) ?? actions.get('Idle') ?? actions.values().next().value;
  if (!next || next === active) return;
  next.reset().setEffectiveWeight(1).play();
  if (active) next.crossFadeFrom(active, .3, false);
  active = next;
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
  // Match web sharpness more closely while keeping a safe mobile cap.
  renderer.setPixelRatio(Math.min(devicePixelRatio || 1, 2, 1280 / Math.max(w, h)));
  renderer.setSize(w, h, false);
  camera.aspect = w / h; camera.updateProjectionMatrix();
  const distance = Math.max(3.5, (model?.userData.frameWidth ?? 3.5) / camera.aspect) / (2 * Math.tan(38 * Math.PI / 360)) * 1.26;
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
    speechBlend += ((state.speaking ? 1 : 0) - speechBlend) * Math.min(1, dt * 12);
    if (speechBlend > .001 && jaw && jawRest) {
      const t = state.position, syllable = Math.sin(t * 10.7) ** 2, envelope = Math.sin(t * 2.1) > -.65 ? 1 : .15;
      const opening = Math.max(2 * Math.atan2(jaw.quaternion.x, jaw.quaternion.w), (.025 + syllable * envelope * .185) * speechBlend);
      jaw.quaternion.copy(jawRest).multiply(jawRotation.setFromAxisAngle(jawAxis, opening));
    }
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
        material.map.anisotropy = Math.min(8, maxAniso);
        material.map.needsUpdate = true;
      }
      if (material.normalMap) {
        material.normalMap.anisotropy = Math.min(8, maxAniso);
        material.normalMap.needsUpdate = true;
      }
      material.needsUpdate = true;
    }
  });
  for (const name of ['EyeLeft', 'EyeRight']) { const eye = model.getObjectByName(name); if (eye) eyes.push(eye); }
  jaw = model.getObjectByName('Jaw'); jawRest = jaw?.quaternion.clone();
  const bounds = new THREE.Box3().setFromObject(model), size = bounds.getSize(new THREE.Vector3()), center = bounds.getCenter(new THREE.Vector3());
  if (!(size.y > 0)) throw new Error('Empty model bounds');
  const scale = 3.5 / size.y;
  model.scale.setScalar(scale); model.position.set(-center.x * scale, -bounds.min.y * scale, -center.z * scale);
  model.userData.frameWidth = size.x * scale;
  mixer = new THREE.AnimationMixer(model);
  for (const clip of data.animations) actions.set(clip.name, mixer.clipAction(clip));
  applyHat();
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
  const hatChanged = next.hat !== undefined || next.hatColor !== undefined || next.color !== undefined;
  state = { ...state, ...next };
  target.value.set(state.color); strength.value = state.originalGreen ? 0 : 1;
  if (controls) controls.enabled = state.interactive;
  if (state.skeleton && model && !skeleton) { skeleton = new THREE.SkeletonHelper(model); scene.add(skeleton); }
  if (skeleton) skeleton.visible = state.skeleton;
  if (hatChanged || next.seek === true) applyHat();
  if (mixer) {
    selectMotion();
    if (seek) { mixer.stopAllAction(); active = null; selectMotion(); if (active) active.time = state.position % active.getClip().duration; mixer.update(0); }
    if (wasSpeaking && !state.speaking && jawRest) { speechBlend = 0; jaw.quaternion.copy(jawRest); mixer.update(0); }
  }
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
  controls = new OrbitControls(camera, renderer.domElement); controls.enablePan = false; controls.enableDamping = true; controls.minDistance = 3; controls.maxDistance = 16; controls.target.set(0, 1.78, 0);
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
