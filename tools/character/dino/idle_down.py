"""Hang the sculpted arm straight down in Idle.

Wave keeps that arm raised. Idle should be the same arm, only lowered, so the
forearm and hand stay as they are in the raised pose.
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np
from pygltflib import (
    GLTF2, Accessor, AnimationChannel, AnimationChannelTarget, AnimationSampler, BufferView,
)

ROOT = Path(__file__).resolve().parents[3]
MASCOT = ROOT / 'assets' / '3d' / 'glow_mascot.glb'
PREVIEW = ROOT / 'build' / 'character_preview' / 'assets' / 'assets' / '3d' / 'glow_mascot.glb'
# Local drop. 2.10 is straight down; more than that swings the arm across the body.
ARM_OUT = 2.10
# Extra drop of the whole arm from the shoulder, in metres. Rotation cannot go lower.
SHOULDER_DROP = 0.07

COMPONENT = {5126: np.dtype('<f4'), 5123: np.dtype('<u2'), 5125: np.dtype('<u4')}
WIDTH = {'SCALAR': 1, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}


def quat(x, y, z):
    sx, sy, sz = math.sin(x / 2), math.sin(y / 2), math.sin(z / 2)
    cx, cy, cz = math.cos(x / 2), math.cos(y / 2), math.cos(z / 2)
    return np.array([
        sx * cy * cz + cx * sy * sz,
        cx * sy * cz - sx * cy * sz,
        cx * cy * sz + sx * sy * cz,
        cx * cy * cz - sx * sy * sz,
    ], np.float64)


def quat_mul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return np.array([
        aw * bx + ax * bw + ay * bz - az * by,
        aw * by - ax * bz + ay * bw + az * bx,
        aw * bz + ax * by - ay * bx + az * bw,
        aw * bw - ax * bx - ay * by - az * bz,
    ], np.float64)


def quat_axis(axis, angle):
    axis = np.asarray(axis, np.float64)
    axis = axis / np.linalg.norm(axis)
    half = math.sin(angle / 2.0)
    return np.array([*(axis * half), math.cos(angle / 2.0)], np.float64)


def joint_points(gltf):
    skin = gltf.skins[0]
    parents = {}
    for index, node in enumerate(gltf.nodes):
        for child in node.children or []:
            parents[child] = index

    def matrix(node):
        x, y, z, w = node.rotation or [0, 0, 0, 1]
        rotation = np.array([
            [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
        ], np.float64)
        scale = np.array(node.scale or [1, 1, 1], np.float64)
        rotation *= scale
        out = np.eye(4)
        out[:3, :3] = rotation
        out[:3, 3] = node.translation or [0, 0, 0]
        return out

    cache = {}

    def world(index):
        if index in cache:
            return cache[index]
        local = matrix(gltf.nodes[index])
        parent = parents.get(index)
        cache[index] = local if parent is None else world(parent) @ local
        return cache[index]

    names = [gltf.nodes[index].name for index in skin.joints]
    points = {name: world(index)[:3, 3] for name, index in zip(names, skin.joints)}
    return points


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


def append_vec3(gltf, blob, values):
    payload = np.ascontiguousarray(values, np.float32).tobytes()
    while len(blob) % 4:
        blob.append(0)
    offset = len(blob)
    blob.extend(payload)
    gltf.bufferViews.append(BufferView(buffer=0, byteOffset=offset, byteLength=len(payload)))
    gltf.accessors.append(Accessor(
        bufferView=len(gltf.bufferViews) - 1,
        byteOffset=0,
        componentType=5126,
        count=len(values),
        type='VEC3',
        min=[float(v) for v in values.min(axis=0)],
        max=[float(v) for v in values.max(axis=0)],
    ))
    return len(gltf.accessors) - 1


def drop_shoulders(gltf, blob):
    """Lower both upper arms in Idle. Other clips keep the rest translation."""
    names = {node.name: index for index, node in enumerate(gltf.nodes)}
    rest = {}
    idle_pos = {}
    for side in ('Left', 'Right'):
        name = f'{side}UpperArm'
        rest[name] = np.array(gltf.nodes[names[name]].translation, np.float64)
        idle_pos[name] = rest[name] + np.array([0.0, -SHOULDER_DROP, 0.0])
    print('shoulder drop', SHOULDER_DROP, 'idle', np.round(idle_pos['LeftUpperArm'], 4))
    for anim in gltf.animations:
        for name, node in ((n, names[n]) for n in rest):
            rot = next(
                channel for channel in anim.channels
                if channel.target.node == node and channel.target.path == 'rotation'
            )
            count = gltf.accessors[anim.samplers[rot.sampler].input].count
            target = idle_pos[name] if anim.name == 'Idle' else rest[name]
            values = np.tile(target.astype(np.float32), (count, 1))
            existing = next((
                channel for channel in anim.channels
                if channel.target.node == node and channel.target.path == 'translation'
            ), None)
            if existing is not None:
                accessor = gltf.accessors[anim.samplers[existing.sampler].output]
                view = gltf.bufferViews[accessor.bufferView]
                if accessor.count != count or view.byteStride not in (None, 0, 12):
                    raise SystemExit(f'{anim.name} {name} translation cannot be rewritten.')
                offset = (view.byteOffset or 0) + (accessor.byteOffset or 0)
                blob[offset:offset + values.nbytes] = values.tobytes()
                continue
            output = append_vec3(gltf, blob, values)
            anim.samplers.append(AnimationSampler(
                input=anim.samplers[rot.sampler].input,
                output=output,
                interpolation='LINEAR',
            ))
            anim.channels.append(AnimationChannel(
                sampler=len(anim.samplers) - 1,
                target=AnimationChannelTarget(node=node, path='translation'),
            ))


def main():
    gltf = GLTF2().load_binary(str(MASCOT))
    points = joint_points(gltf)
    identity = np.array([0, 0, 0, 1], np.float64)
    targets = {
        'LeftForeArm': identity,
        'RightForeArm': identity,
        'LeftHand': identity,
        'RightHand': identity,
    }
    # Roll the whole arm around its length. The hand stays identity, so it turns with the arm.
    for side, hang_z, roll in (('Left', -ARM_OUT, math.radians(150)), ('Right', ARM_OUT, math.radians(-150))):
        axis = points[f'{side}Hand'] - points[f'{side}UpperArm']
        targets[f'{side}UpperArm'] = quat_mul(quat(0, 0, hang_z), quat_axis(axis, roll))
        print(side, 'axis', np.round(axis / np.linalg.norm(axis), 3))
    idle = next(item for item in gltf.animations if item.name == 'Idle')
    blob = bytearray(gltf.binary_blob())
    found = set()
    for channel in idle.channels:
        if channel.target.path != 'rotation':
            continue
        name = gltf.nodes[channel.target.node].name
        if name not in targets:
            continue
        sampler = idle.samplers[channel.sampler]
        accessor = gltf.accessors[sampler.output]
        view = gltf.bufferViews[accessor.bufferView]
        if view.byteStride not in (None, 0, 16):
            raise SystemExit(f'{name} keys are interleaved.')
        current = read_accessor(gltf, sampler.output)
        print(name, 'was', np.round(current[0], 4), 'keys', len(current))
        values = np.tile(targets[name].astype(np.float32), (len(current), 1))
        offset = (view.byteOffset or 0) + (accessor.byteOffset or 0)
        blob[offset:offset + values.nbytes] = values.tobytes()
        found.add(name)
    missing = set(targets) - found
    if missing:
        raise SystemExit(f'Missing idle bones: {sorted(missing)}')
    drop_shoulders(gltf, blob)
    gltf.buffers[0].byteLength = len(blob)
    gltf.set_binary_blob(bytes(blob))
    if '--write' not in sys.argv:
        print('preview only')
        return
    tmp = MASCOT.with_suffix('.glb.tmp')
    gltf.save_binary(str(tmp))
    tmp.replace(MASCOT)
    if PREVIEW.parent.exists():
        PREVIEW.write_bytes(MASCOT.read_bytes())
        print('updated preview')
    print('saved', MASCOT)


if __name__ == '__main__':
    main()
