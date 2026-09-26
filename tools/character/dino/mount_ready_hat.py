"""Mount a ready cartoon-hat GLB onto the dinosaur mascot.

Decimates to a mobile budget, paints any baked green accents to charcoal so
the felt stays fully black/tintable, skins to Chest, and names material ``Hat``
for the studio toggle + recolor controls.

Run from tools/character:
    python dino/mount_ready_hat.py PATH/TO/hat.glb ../../assets/3d/glow_mascot.glb
"""
from __future__ import annotations

import io
import sys
from pathlib import Path

import fast_simplification
import numpy as np
from PIL import Image
from pygltflib import (
    GLTF2, Attributes, Material, PbrMetallicRoughness, Primitive,
    TextureInfo, Texture, Image as GltfImage, Sampler,
)

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from rig_port_frontal import append_accessor, read_accessor  # noqa: E402

# Place the ready hat so its brim sits above the dino brows.
CX, CY0, CZ = -.062, .830, .020
SCALE = .72
# Yaw so both crown balls sit forward on the hat (toward the face, +Z).
# 110° + 180°: previous mount had front/back swapped.
YAW = 5.061454830783555  # 290°
TARGET_FACES = 48000
HAT_NAMES = ('Hat', 'HatBand', 'HatTrim', 'HatSkin')


def _chest_index(gltf) -> int:
    return [gltf.nodes[j].name for j in gltf.skins[0].joints].index('Chest')


def _strip_old_hat(gltf: GLTF2) -> None:
    mesh = gltf.meshes[0]
    old_mats = list(gltf.materials or [])
    new_mats, remap = [], {}
    for i, mat in enumerate(old_mats):
        if mat.name in HAT_NAMES:
            continue
        remap[i] = len(new_mats)
        new_mats.append(mat)
    gltf.materials = new_mats
    keep = []
    for prim in mesh.primitives:
        mid = prim.material
        if mid is not None and mid not in remap:
            continue
        if mid is not None:
            prim.material = remap[mid]
        keep.append(prim)
    mesh.primitives = keep


def _load_source(path: Path):
    g = GLTF2().load_binary(str(path))
    prim = g.meshes[0].primitives[0]
    pos = read_accessor(g, prim.attributes.POSITION).astype(np.float64)
    nrm = read_accessor(g, prim.attributes.NORMAL).astype(np.float64)
    uvs = read_accessor(g, prim.attributes.TEXCOORD_0).astype(np.float64)
    tris = read_accessor(g, prim.indices).reshape(-1, 3).astype(np.int64)
    bv = g.bufferViews[g.images[0].bufferView]
    blob = g.binary_blob()
    jpeg = bytes(blob[bv.byteOffset: bv.byteOffset + bv.byteLength])
    return pos, nrm, uvs, tris, jpeg


def _green_mask_rgb(arr: np.ndarray) -> np.ndarray:
    """Boolean mask of baked green / olive pixels in an RGB uint8 image."""
    rgb = arr.astype(np.float64) / 255.0
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx = rgb.max(-1)
    mn = rgb.min(-1)
    df = mx - mn + 1e-9
    hue = np.zeros(mx.shape)
    m = mx == r
    hue[m] = ((g - b) / df)[m] % 6
    m = mx == g
    hue[m] = ((b - r) / df)[m] + 2
    m = mx == b
    hue[m] = ((r - g) / df)[m] + 4
    hue /= 6.0
    sat = df / np.maximum(mx, 1e-9)
    by_hue = (hue > .12) & (hue < .55) & (sat > .06) & (mx > .12)
    by_channel = (g > r + .015) & (g > b) & (g > .18) & (sat > .05)
    return by_hue | by_channel


def _blackout_green(jpeg: bytes) -> bytes:
    """Repaint baked green accents to charcoal so the hat stays fully dark."""
    im = Image.open(io.BytesIO(jpeg)).convert('RGB')
    # 4K atlases crush mobile cold-start; 1024 is enough for the felt hat.
    if max(im.size) > 1024:
        im.thumbnail((1024, 1024), Image.Resampling.LANCZOS)
    arr = np.asarray(im).copy()
    mask = _green_mask_rgb(arr)
    # Match studio default hat charcoal (#2C2C2E).
    arr[mask] = (44, 44, 46)
    out = io.BytesIO()
    Image.fromarray(arr).save(out, format='JPEG', quality=78, optimize=True)
    print('blacked-out green texels', int(mask.sum()), 'size', im.size)
    return out.getvalue()


def _decimate(pos, nrm, uvs, tris, target):
    welded, inverse = np.unique(np.round(pos, 5), axis=0, return_inverse=True)
    inverse = inverse.ravel()
    # Average attributes onto welded verts.
    w_uv = np.zeros((len(welded), 2), np.float64)
    w_n = np.zeros((len(welded), 3), np.float64)
    w_c = np.zeros(len(welded), np.float64)
    np.add.at(w_uv, inverse, uvs)
    np.add.at(w_n, inverse, nrm)
    np.add.at(w_c, inverse, 1.0)
    w_uv /= w_c[:, None]
    w_n /= np.maximum(np.linalg.norm(w_n, axis=1, keepdims=True), 1e-8)
    wt = inverse[tris]
    keep = (wt[:, 0] != wt[:, 1]) & (wt[:, 1] != wt[:, 2]) & (wt[:, 0] != wt[:, 2])
    points, faces = fast_simplification.simplify(
        welded.astype(np.float64), wt[keep], target_count=target)
    # Pull UVs/normals from nearest welded source vertex.
    from scipy.spatial import cKDTree
    tree = cKDTree(welded)
    _, src = tree.query(points)
    return (
        points.astype(np.float32),
        w_n[src].astype(np.float32),
        w_uv[src].astype(np.float32),
        faces.astype(np.uint32),
    )


def _transform(pos: np.ndarray, nrm: np.ndarray):
    """Scale, yaw 180° so crown balls face +Z, then place on the dino head."""
    c, s = np.cos(YAW), np.sin(YAW)
    x, y, z = pos[:, 0], pos[:, 1], pos[:, 2]
    xr = c * x + s * z
    zr = -s * x + c * z
    out = np.column_stack([CX + SCALE * xr, CY0 + SCALE * y, CZ + SCALE * zr])
    nx, ny, nz = nrm[:, 0], nrm[:, 1], nrm[:, 2]
    nn = np.column_stack([c * nx + s * nz, ny, -s * nx + c * nz])
    nn /= np.maximum(np.linalg.norm(nn, axis=1, keepdims=True), 1e-8)
    return out.astype(np.float32), nn.astype(np.float32)


def _append_textured(gltf, binary, jpeg: bytes) -> int:
    """Embed JPEG and return material index for Hat (textured)."""
    while len(binary) % 4:
        binary.append(0)
    view = len(gltf.bufferViews)
    from pygltflib import BufferView
    gltf.bufferViews.append(BufferView(
        buffer=0, byteOffset=len(binary), byteLength=len(jpeg)))
    binary.extend(jpeg)
    image = GltfImage(mimeType='image/jpeg', bufferView=view)
    gltf.images = list(gltf.images or [])
    gltf.images.append(image)
    gltf.samplers = list(gltf.samplers or [])
    gltf.samplers.append(Sampler(magFilter=9729, minFilter=9987, wrapS=10497, wrapT=10497))
    gltf.textures = list(gltf.textures or [])
    gltf.textures.append(Texture(sampler=len(gltf.samplers) - 1, source=len(gltf.images) - 1))
    mat = Material(
        name='Hat', doubleSided=True, alphaMode='OPAQUE',
        pbrMetallicRoughness=PbrMetallicRoughness(
            baseColorFactor=[1., 1., 1., 1.],
            baseColorTexture=TextureInfo(index=len(gltf.textures) - 1),
            metallicFactor=0., roughnessFactor=.85))
    gltf.materials.append(mat)
    return len(gltf.materials) - 1


def _append_prim(gltf, binary, positions, normals, uvs, indices, material, chest):
    count = len(positions)
    joints = np.zeros((count, 4), np.uint16)
    weights = np.zeros((count, 4), np.float32)
    joints[:, 0] = chest
    weights[:, 0] = 1.0
    attrs = Attributes(
        POSITION=append_accessor(gltf, binary, positions, 5126, 'VEC3', target=34962, bounds=True),
        NORMAL=append_accessor(gltf, binary, normals, 5126, 'VEC3', target=34962),
        TEXCOORD_0=append_accessor(gltf, binary, uvs, 5126, 'VEC2', target=34962),
        JOINTS_0=append_accessor(gltf, binary, joints, 5123, 'VEC4', target=34962),
        WEIGHTS_0=append_accessor(gltf, binary, weights, 5126, 'VEC4', target=34962),
    )
    setattr(attrs, '_GLOW_SKIN_REGION',
            append_accessor(gltf, binary, np.ones(count, np.float32), 5126, 'SCALAR', target=34962))
    index_type, index_arr = ((5123, np.uint16) if indices.max() < 65535 else (5125, np.uint32))
    gltf.meshes[0].primitives.append(Primitive(
        attributes=attrs, material=material,
        indices=append_accessor(gltf, binary, indices.astype(index_arr).reshape(-1),
                                index_type, 'SCALAR', target=34963)))


def mount(source: Path, destination: Path) -> None:
    print('loading', source)
    pos, nrm, uvs, tris, jpeg = _load_source(source)
    jpeg = _blackout_green(jpeg)
    print('source tris', len(tris))

    print('decimating to', TARGET_FACES)
    points, normals, out_uvs, faces = _decimate(pos, nrm, uvs, tris, TARGET_FACES)
    points, normals = _transform(points, normals)
    print('hat tris', len(faces))

    dest = GLTF2().load_binary(str(destination))
    _strip_old_hat(dest)
    chest = _chest_index(dest)
    binary = bytearray(dest.binary_blob())

    hat_mat = _append_textured(dest, binary, jpeg)
    used = np.unique(faces.reshape(-1))
    remap = np.full(len(points), -1, np.int64)
    remap[used] = np.arange(len(used))
    _append_prim(
        dest, binary,
        points[used], normals[used], out_uvs[used],
        remap[faces].astype(np.uint32),
        hat_mat, chest)

    extras = dict(dest.extras or {})
    extras['hat'] = 'ready-cartoon-v2-black'
    dest.extras = extras
    dest.buffers[0].byteLength = len(binary)
    dest.set_binary_blob(bytes(binary))
    dest.save_binary(str(destination))
    print('saved', destination, 'prims', len(dest.meshes[0].primitives))


if __name__ == '__main__':
    src = Path(sys.argv[1])
    dst = Path(sys.argv[2] if len(sys.argv) > 2 else '../../assets/3d/glow_mascot.glb')
    mount(src.resolve(), dst.resolve())
