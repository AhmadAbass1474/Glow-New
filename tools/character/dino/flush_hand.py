"""Pull hand bulges on both sides back onto the arm's own radius.

The hand stays attached. Only vertices that stick out past the forearm,
inside or outside, move inward. Hat, glasses, eyelids and the mouth are untouched.
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from pygltflib import GLTF2

ROOT = Path(__file__).resolve().parents[3]
MASCOT = ROOT / 'assets' / '3d' / 'glow_mascot.glb'
PREVIEW = ROOT / 'build' / 'character_preview' / 'assets' / 'assets' / '3d' / 'glow_mascot.glb'

COMPONENT = {5126: np.dtype('<f4'), 5123: np.dtype('<u2'), 5125: np.dtype('<u4'), 5121: np.dtype('u1')}
WIDTH = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}


def read_accessor(gltf, index):
    accessor = gltf.accessors[index]
    view = gltf.bufferViews[accessor.bufferView]
    dtype = COMPONENT[accessor.componentType]
    columns = WIDTH[accessor.type]
    stride = view.byteStride or columns * dtype.itemsize
    offset = (view.byteOffset or 0) + (accessor.byteOffset or 0)
    return np.ndarray(
        (accessor.count, columns), dtype=dtype, buffer=gltf.binary_blob(),
        offset=offset, strides=(stride, dtype.itemsize),
    ).copy()


def write_positions(gltf, accessor_index, values):
    accessor = gltf.accessors[accessor_index]
    view = gltf.bufferViews[accessor.bufferView]
    if view.byteStride not in (None, 0, 12):
        raise SystemExit('Positions are interleaved.')
    values = np.ascontiguousarray(values, np.float32)
    blob = bytearray(gltf.binary_blob())
    offset = (view.byteOffset or 0) + (accessor.byteOffset or 0)
    blob[offset:offset + values.nbytes] = values.tobytes()
    rows = values.reshape(len(values), -1)
    accessor.min = [float(item) for item in rows.min(0)]
    accessor.max = [float(item) for item in rows.max(0)]
    gltf.set_binary_blob(bytes(blob))


def bone_weight(joints, weights, slot):
    total = np.zeros(len(joints))
    for column in range(4):
        hit = joints[:, column] == slot
        total[hit] += weights[hit, column]
    return total


def local_matrix(node):
    translation = np.array(node.translation or [0, 0, 0], np.float64)
    rotation = np.array(node.rotation or [0, 0, 0, 1], np.float64)
    scale = np.array(node.scale or [1, 1, 1], np.float64)
    x, y, z, w = rotation
    matrix = np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w), 0],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w), 0],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y), 0],
        [0, 0, 0, 1],
    ], np.float64)
    matrix[:3, :3] *= scale
    matrix[:3, 3] = translation
    return matrix


def world_joints(gltf, skin):
    parents = {}
    for index, node in enumerate(gltf.nodes):
        for child in node.children or []:
            parents[child] = index
    cache = {}

    def world(index):
        if index in cache:
            return cache[index]
        local = local_matrix(gltf.nodes[index])
        parent = parents.get(index)
        cache[index] = local if parent is None else world(parent) @ local
        return cache[index]

    return [world(index)[:3, 3] for index in skin.joints]


def flush(pos, joints, weights, names, points):
    slot = {name: index for index, name in enumerate(names)}
    moved = np.zeros(len(pos), dtype=bool)
    report = []
    for side in ('Left', 'Right'):
        fore = bone_weight(joints, weights, slot[f'{side}ForeArm'])
        hand = bone_weight(joints, weights, slot[f'{side}Hand'])
        shaft = fore > 0.45
        if shaft.sum() < 12:
            raise SystemExit(f'{side} forearm surface was not found.')
        origin = pos[shaft].mean(0)
        _, _, basis = np.linalg.svd(pos[shaft] - origin, full_matrices=False)
        axis = basis[0]
        along = (pos - origin) @ axis
        # Point the axis toward the hand.
        if along[hand > 0.4].mean() < 0:
            axis = -axis
            along = -along
        radial = pos - origin - axis * along[:, None]
        radius = np.linalg.norm(radial, axis=1)
        arm_radius = float(np.percentile(radius[shaft], 86))
        hand_along = along[hand > 0.4]
        hand_band = (hand > 0.22) & (along > np.percentile(hand_along, 15))
        excess = radius - arm_radius
        bulge = hand_band & (excess > 0.0015)
        fade = np.clip((along - np.percentile(hand_along, 20)) / max(float(np.ptp(hand_along)) * 0.35, 1e-4), 0, 1)
        pull = np.clip(excess, 0, None) * np.maximum(fade, 0.35)
        pull[~bulge] = 0
        scale = np.ones(len(pos))
        far = radius > 1e-6
        scale[far] = np.clip((radius[far] - pull[far]) / radius[far], 0.25, 1)
        pos[far] = origin + axis * along[far, None] + radial[far] * scale[far, None]
        moved |= pull > 0.0004
        report.append((
            side, int(bulge.sum()), round(arm_radius, 4),
            round(float(excess[hand_band].max()) if hand_band.any() else 0, 4),
            int(hand_band.sum()),
        ))
    return pos, moved, report


def main():
    gltf = GLTF2().load_binary(str(MASCOT))
    skin = gltf.skins[0]
    names = [gltf.nodes[index].name for index in skin.joints]
    prim = gltf.meshes[0].primitives[0]
    position_index = prim.attributes.POSITION
    pos = read_accessor(gltf, position_index).astype(np.float64)
    joints = read_accessor(gltf, prim.attributes.JOINTS_0).astype(np.int64)
    weights = read_accessor(gltf, prim.attributes.WEIGHTS_0).astype(np.float64)
    points = world_joints(gltf, skin)
    updated, moved, report = flush(pos.copy(), joints, weights, names, points)
    for side, count, radius, excess, hand_count in report:
        print(side, 'bulges', count, 'of', hand_count, 'arm radius', radius, 'max stick-out', excess)
    print('moved', int(moved.sum()))
    if '--write' not in sys.argv:
        print('preview only')
        return
    write_positions(gltf, position_index, updated)
    tmp = MASCOT.with_suffix('.glb.tmp')
    gltf.save_binary(str(tmp))
    tmp.replace(MASCOT)
    if PREVIEW.parent.exists():
        PREVIEW.write_bytes(MASCOT.read_bytes())
        print('updated preview')
    print('saved', MASCOT)


if __name__ == '__main__':
    main()
