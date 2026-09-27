"""Mount round glasses onto the dinosaur's eyes.

The lenses sit on the measured pupils. Temples are eased outward so they
ride the cheeks instead of passing through the head. Material name
``Glasses`` is the studio toggle.

Run from tools/character:
    python dino/mount_glasses.py PATH/TO/glasses.glb ../../assets/3d/glow_mascot.glb
"""
from __future__ import annotations

import io
import sys
import types
from pathlib import Path

import fast_simplification
import numpy as np
from PIL import Image, ImageDraw
from pygltflib import (
    GLTF2, Attributes, BufferView, Material, PbrMetallicRoughness, Primitive,
    Sampler, Texture, TextureInfo, Image as GltfImage,
)

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
_stub = types.ModuleType('port_arm_split')
for _name in ('find_arm_cuts', 'apply_arm_cuts', 'build_armpit_walls', 'wall_texcoords', 'arm_open_targets'):
    setattr(_stub, _name, lambda *args, **kwargs: None)
sys.modules['port_arm_split'] = _stub
from rig_port_frontal import append_accessor, read_accessor  # noqa: E402

BODY_X = -0.062
# Closer together, and a little lower than the brow.
EYE_L = np.array([0.090, 0.724, 0.205])
EYE_R = np.array([-0.214, 0.724, 0.205])
# Lens centers on the source model (front of the rings, +Z).
LENS_L = np.array([27.58, 18.0, 24.5])
LENS_R = np.array([-27.36, 18.0, 24.5])
LENS_RADIUS = 19.0
# A little smaller than the last fit, still wider than the eye.
TARGET_RADIUS = 0.086
# Far enough in front of the cheek that the whole ring shows.
FACE_GAP = 0.092
TARGET_FACES = 9000
GLASSES_NAME = 'Glasses'
PREVIEW = Path(__file__).resolve().parent


def _image_bytes(gltf: GLTF2) -> bytes:
    image = gltf.images[0]
    view = gltf.bufferViews[image.bufferView]
    blob = gltf.binary_blob()
    return bytes(blob[view.byteOffset: view.byteOffset + view.byteLength])


def _load_source(path: Path):
    g = GLTF2().load_binary(str(path))
    prim = g.meshes[0].primitives[0]
    pos = read_accessor(g, prim.attributes.POSITION).astype(np.float64)
    nrm = read_accessor(g, prim.attributes.NORMAL).astype(np.float64)
    uvs = read_accessor(g, prim.attributes.TEXCOORD_0).astype(np.float64)
    tris = read_accessor(g, prim.indices).reshape(-1, 3).astype(np.int64)
    return pos, nrm, uvs, tris, _image_bytes(g)


def _decimate(pos, nrm, uvs, tris, target):
    welded, inverse = np.unique(np.round(pos, 4), axis=0, return_inverse=True)
    inverse = inverse.ravel()
    w_uv = np.zeros((len(welded), 2))
    w_n = np.zeros((len(welded), 3))
    w_c = np.zeros(len(welded))
    np.add.at(w_uv, inverse, uvs)
    np.add.at(w_n, inverse, nrm)
    np.add.at(w_c, inverse, 1.0)
    w_uv /= w_c[:, None]
    w_n /= np.maximum(np.linalg.norm(w_n, axis=1, keepdims=True), 1e-8)
    wt = inverse[tris]
    ok = (wt[:, 0] != wt[:, 1]) & (wt[:, 1] != wt[:, 2]) & (wt[:, 0] != wt[:, 2])
    points, faces = fast_simplification.simplify(
        welded.astype(np.float64), wt[ok], target_count=target)
    from scipy.spatial import cKDTree
    _, src = cKDTree(welded).query(points)
    return (
        points.astype(np.float64),
        w_n[src].astype(np.float64),
        w_uv[src].astype(np.float32),
        faces.astype(np.int64),
    )


def _place(pos: np.ndarray) -> np.ndarray:
    """Put each ring on an eye. The bridge stretches across the wide-set eyes."""
    scale = TARGET_RADIUS / LENS_RADIUS
    out = np.empty_like(pos)
    left = pos[:, 0] >= 6.0
    right = pos[:, 0] <= -6.0
    out[left] = EYE_L + (pos[left] - LENS_L) * scale
    out[right] = EYE_R + (pos[right] - LENS_R) * scale
    bridge = ~left & ~right
    if bridge.any():
        t = (pos[bridge, 0] + 6.0) / 12.0
        y = EYE_L[1] + (pos[bridge, 1] - LENS_L[1]) * scale
        z = EYE_L[2] + (pos[bridge, 2] - LENS_L[2]) * scale
        x_left = (EYE_L + (np.array([6.0, LENS_L[1], LENS_L[2]]) - LENS_L) * scale)[0]
        x_right = (EYE_R + (np.array([-6.0, LENS_R[1], LENS_R[2]]) - LENS_R) * scale)[0]
        out[bridge, 0] = x_right + t * (x_left - x_right)
        out[bridge, 1] = y
        out[bridge, 2] = z
    out[:, 2] += FACE_GAP
    print(f'scale {scale:.5f} radius {TARGET_RADIUS:.3f}')
    return out


def _seat_temples(pos: np.ndarray, head: np.ndarray) -> np.ndarray:
    """Stretch the arms back to the middle of the head. The hinge stays put."""
    hinge_z = float(EYE_L[2] + FACE_GAP) - 0.004
    near = head[np.abs(head[:, 1] - float(EYE_L[1])) < 0.12]
    sample = near if len(near) > 40 else head
    mid_z = 0.5 * (float(sample[:, 2].min()) + float(sample[:, 2].max()))
    out = pos.copy()
    behind = out[:, 2] < hinge_z
    depth = hinge_z - out[behind, 2]
    reach = max(float(depth.max()), 1e-4)
    target = max(hinge_z - mid_z, reach) + 0.07
    out[behind, 2] = hinge_z - depth * (target / reach)
    # The end was buried in the skull. Slide it out; the hinge does not move.
    travel = np.clip(depth / reach, 0.0, 1.0)
    side = np.where(out[behind, 0] >= BODY_X, 1.0, -1.0)
    out[behind, 0] += side * 0.040 * travel
    print(f'temple reaches z {hinge_z - target:.3f} head mid {mid_z:.3f}')
    return out


def _head_points(gltf: GLTF2) -> np.ndarray:
    prim = gltf.meshes[0].primitives[0]
    pos = read_accessor(gltf, prim.attributes.POSITION).astype(np.float64)
    band = (pos[:, 1] > 0.62) & (pos[:, 1] < 0.98)
    return pos[band]


def _chest_index(gltf: GLTF2) -> int:
    return [gltf.nodes[j].name for j in gltf.skins[0].joints].index('Chest')


def _strip(gltf: GLTF2) -> None:
    drop = {i for i, mat in enumerate(gltf.materials or []) if mat.name == GLASSES_NAME}
    if not drop:
        return
    remap, kept = {}, []
    for i, mat in enumerate(gltf.materials):
        if i in drop:
            continue
        remap[i] = len(kept)
        kept.append(mat)
    gltf.materials = kept
    prims = []
    for prim in gltf.meshes[0].primitives:
        if prim.material in drop:
            continue
        if prim.material is not None:
            prim.material = remap[prim.material]
        prims.append(prim)
    gltf.meshes[0].primitives = prims


def _jpeg(raw: bytes) -> bytes:
    image = Image.open(io.BytesIO(raw)).convert('RGB')
    if max(image.size) > 1024:
        image.thumbnail((1024, 1024), Image.Resampling.LANCZOS)
    buf = io.BytesIO()
    image.save(buf, format='JPEG', quality=84, optimize=True)
    print('texture', image.size, 'bytes', buf.tell())
    return buf.getvalue()


def _append_texture(gltf, binary, jpeg: bytes) -> int:
    while len(binary) % 4:
        binary.append(0)
    view = len(gltf.bufferViews)
    gltf.bufferViews.append(BufferView(buffer=0, byteOffset=len(binary), byteLength=len(jpeg)))
    binary.extend(jpeg)
    gltf.images = list(gltf.images or [])
    gltf.images.append(GltfImage(mimeType='image/jpeg', bufferView=view))
    gltf.samplers = list(gltf.samplers or [])
    gltf.samplers.append(Sampler(magFilter=9729, minFilter=9987, wrapS=10497, wrapT=10497))
    gltf.textures = list(gltf.textures or [])
    gltf.textures.append(Texture(sampler=len(gltf.samplers) - 1, source=len(gltf.images) - 1))
    gltf.materials.append(Material(
        name=GLASSES_NAME, doubleSided=True, alphaMode='OPAQUE',
        pbrMetallicRoughness=PbrMetallicRoughness(
            baseColorFactor=[1., 1., 1., 1.],
            baseColorTexture=TextureInfo(index=len(gltf.textures) - 1),
            metallicFactor=0.15, roughnessFactor=0.38)))
    return len(gltf.materials) - 1


def _append_prim(gltf, binary, positions, normals, uvs, indices, material, chest):
    count = len(positions)
    joints = np.zeros((count, 4), np.uint16)
    weights = np.zeros((count, 4), np.float32)
    joints[:, 0] = chest
    weights[:, 0] = 1.0
    attrs = Attributes(
        POSITION=append_accessor(gltf, binary, positions.astype(np.float32), 5126, 'VEC3', target=34962, bounds=True),
        NORMAL=append_accessor(gltf, binary, normals.astype(np.float32), 5126, 'VEC3', target=34962),
        TEXCOORD_0=append_accessor(gltf, binary, uvs.astype(np.float32), 5126, 'VEC2', target=34962),
        JOINTS_0=append_accessor(gltf, binary, joints, 5123, 'VEC4', target=34962),
        WEIGHTS_0=append_accessor(gltf, binary, weights, 5126, 'VEC4', target=34962),
    )
    index_type, index_arr = ((5123, np.uint16) if indices.max() < 65535 else (5125, np.uint32))
    gltf.meshes[0].primitives.append(Primitive(
        attributes=attrs, material=material,
        indices=append_accessor(
            gltf, binary, indices.astype(index_arr).reshape(-1),
            index_type, 'SCALAR', target=34963)))


def _preview(head, glasses, path):
    canvas = Image.new('RGB', (720, 900), (24, 26, 28))
    pen = ImageDraw.Draw(canvas)
    cloud = head[::5][:, [0, 1]]
    both = np.vstack([cloud, glasses[:, [0, 1]]])
    lo, hi = both.min(0) - 0.02, both.max(0) + 0.02
    span = np.maximum(hi - lo, 1e-4)

    def project(p):
        u = (p[:, 0] - lo[0]) / span[0]
        v = (p[:, 1] - lo[1]) / span[1]
        return np.column_stack([28 + u * 664, 872 - v * 820])

    for x, y in project(cloud):
        pen.ellipse((x - 1, y - 1, x + 1, y + 1), fill=(70, 120, 78))
    order = np.argsort(glasses[:, 2])
    gp = project(glasses[:, [0, 1]])
    for i in order:
        x, y = gp[i]
        pen.ellipse((x - 1.6, y - 1.6, x + 1.6, y + 1.6), fill=(230, 230, 235))
    canvas.save(path)


def mount(source: Path, destination: Path) -> None:
    print('loading', source)
    pos, nrm, uvs, tris, raw = _load_source(source)
    print('source tris', len(tris))
    pos, nrm, uvs, tris = _decimate(pos, nrm, uvs, tris, TARGET_FACES)
    dest = GLTF2().load_binary(str(destination))
    _strip(dest)
    head = _head_points(dest)
    placed = _seat_temples(_place(pos), head)
    print(
        'placed',
        np.round(placed.min(0), 3),
        np.round(placed.max(0), 3),
    )
    _preview(head, placed[::2], PREVIEW / '_glasses_fit.png')
    chest = _chest_index(dest)
    binary = bytearray(dest.binary_blob())
    material = _append_texture(dest, binary, _jpeg(raw))
    used = np.unique(tris.reshape(-1))
    remap = np.full(len(placed), -1, np.int64)
    remap[used] = np.arange(len(used))
    _append_prim(
        dest, binary, placed[used], nrm[used], uvs[used],
        remap[tris].astype(np.uint32), material, chest)
    dest.buffers[0].byteLength = len(binary)
    dest.set_binary_blob(bytes(binary))
    dest.save_binary(str(destination))
    print('saved', destination, 'tris', len(tris), 'bytes', destination.stat().st_size)


if __name__ == '__main__':
    mount(Path(sys.argv[1]), Path(sys.argv[2]))
