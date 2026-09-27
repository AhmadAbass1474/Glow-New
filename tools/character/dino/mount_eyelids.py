"""Add retractable eyelids on the dinosaur's painted eyes.

The open shape is a thin cap on the upper rim. Half and closed shapes are
morph targets named the way CharacterEyeAnimation already drives them:
BlinkLeftHalf, BlinkLeftClosed, BlinkRightHalf, BlinkRightClosed.
The upper lid does most of the travel and meets the lower lid just below
the pupil. Both lids are skinned to Chest so they move with the face.

Run from tools/character:
    python dino/mount_eyelids.py ../../assets/3d/glow_mascot.glb
"""
from __future__ import annotations

import sys
import types
from pathlib import Path

import numpy as np
from pygltflib import GLTF2, Attributes, Material, Mesh, Node, Primitive
from scipy.spatial import cKDTree

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
_stub = types.ModuleType('port_arm_split')
for _name in ('find_arm_cuts', 'apply_arm_cuts', 'build_armpit_walls', 'wall_texcoords', 'arm_open_targets'):
    setattr(_stub, _name, lambda *args, **kwargs: None)
sys.modules['port_arm_split'] = _stub
from rig_port_frontal import append_accessor, read_accessor  # noqa: E402

# Same centers the glasses were fitted to. Radius sits inside the lens.
EYES = (
    ('EyeLeft', np.array([0.090, 0.724]), 0.078, 0.072),
    ('EyeRight', np.array([-0.214, 0.724]), 0.078, 0.072),
)
# Free edge, in units of the local vertical radius. Positive is up.
# Open is a thin hood on the rim. Closed overlaps on a seam below center
# so the painted eye does not show through the meeting line.
UPPER_EDGE = (0.78, 0.04, -0.20)
LOWER_EDGE = (-0.94, -0.52, -0.04)
TARGET_NAMES = ['BlinkLeftHalf', 'BlinkLeftClosed', 'BlinkRightHalf', 'BlinkRightClosed']
CLEARANCE = 0.012
COLUMNS = 33
UPPER_ROWS = 6
LOWER_ROWS = 4


def _normals(pos: np.ndarray, faces: np.ndarray) -> np.ndarray:
    normal = np.zeros_like(pos)
    a, b, c = pos[faces[:, 0]], pos[faces[:, 1]], pos[faces[:, 2]]
    face = np.cross(b - a, c - a)
    for corner in range(3):
        np.add.at(normal, faces[:, corner], face)
    length = np.linalg.norm(normal, axis=1, keepdims=True)
    normal /= np.maximum(length, 1e-8)
    if float(normal[:, 2].mean()) < 0:
        normal *= -1
        faces[:] = faces[:, ::-1]
    return normal.astype(np.float32)


def _sheet(cx, cy, rx, ry, upper: bool):
    """Grid positions for open, half, and closed. Returns (3, rows*cols, 3)."""
    rows = UPPER_ROWS if upper else LOWER_ROWS
    edge = UPPER_EDGE if upper else LOWER_EDGE
    us = np.linspace(-0.998, 0.998, COLUMNS)
    arc = np.sqrt(np.maximum(0.0, 1.0 - us * us))
    rim = (ry if upper else -ry) * arc
    states = []
    for amount in edge:
        free = amount * ry * arc
        grid = np.zeros((rows, COLUMNS, 3), np.float64)
        for row, v in enumerate(np.linspace(0.0, 1.0, rows)):
            y = (1.0 - v) * rim + v * free
            grid[row, :, 0] = cx + rx * us
            grid[row, :, 1] = cy + y
        states.append(grid.reshape(-1, 3))
    return states


def _faces(row_offset: int, rows: int, upper: bool) -> list[tuple[int, int, int]]:
    faces = []
    for row in range(1, rows):
        for col in range(1, COLUMNS):
            d = row_offset + row * COLUMNS + col
            c = d - 1
            b = d - COLUMNS
            a = b - 1
            # Viewed from the front (+Z), the upper sheet's rows run downward.
            if upper:
                faces.extend(((a, c, b), (b, c, d)))
            else:
                faces.extend(((a, b, c), (b, d, c)))
    return faces


def build(head: np.ndarray, skin_uv: np.ndarray):
    tree = cKDTree(head[:, :2])
    points = []
    shapes = [[], [], []]
    faces = []
    eye_ids = []
    for eye, (_, center, rx, ry) in enumerate(EYES):
        cx, cy = float(center[0]), float(center[1])
        for upper in (True, False):
            sheets = _sheet(cx, cy, rx, ry, upper)
            offset = len(points)
            rows = UPPER_ROWS if upper else LOWER_ROWS
            count = rows * COLUMNS
            points.extend([0] * count)
            eye_ids.extend([eye] * count)
            for state, sheet in enumerate(sheets):
                shapes[state].extend(sheet.tolist())
            faces.extend(_faces(offset, rows, upper))
    poses = [np.array(value, np.float32) for value in shapes]
    ids = np.array(eye_ids)
    for pose in poses:
        _dist, index = tree.query(pose[:, :2], k=8)
        pose[:, 2] = head[index, 2].max(axis=1) + CLEARANCE
        for _, center, rx, ry in EYES:
            local = ((pose[:, 0] - center[0]) / rx) ** 2 + ((pose[:, 1] - center[1]) / ry) ** 2
            pose[:, 2] += (0.007 * np.sqrt(np.maximum(0.0, 1.0 - np.clip(local, 0.0, 1.0)))).astype(np.float32)
    faces = np.array(faces, np.uint32)
    closed_normals = _normals(poses[2].astype(np.float64), faces.astype(np.int64))
    targets = []
    for eye in range(2):
        for state in (1, 2):
            delta = np.zeros_like(poses[0])
            delta[ids == eye] = poses[state][ids == eye] - poses[0][ids == eye]
            targets.append(delta.astype(np.float32))
    uvs = np.repeat(skin_uv.reshape(1, 2), len(poses[0]), axis=0).astype(np.float32)
    print(
        'lid verts', len(poses[0]),
        'span', np.round(poses[2].min(0), 3), np.round(poses[2].max(0), 3),
    )
    return poses[0], closed_normals, uvs, faces, targets


def _strip(gltf: GLTF2) -> None:
    drop_nodes = {i for i, node in enumerate(gltf.nodes) if node.name in {'EyeLids', 'EyeLeft', 'EyeRight'}}
    if drop_nodes:
        gltf.scenes[gltf.scene or 0].nodes = [
            index for index in gltf.scenes[gltf.scene or 0].nodes if index not in drop_nodes
        ]
    gltf.meshes = [mesh for mesh in gltf.meshes if mesh.name != 'EyeLids']
    gltf.materials = [mat for mat in gltf.materials if mat.name != 'EyeLidSkin']


def mount(destination: Path) -> None:
    gltf = GLTF2().load_binary(str(destination))
    _strip(gltf)
    prim = gltf.meshes[0].primitives[0]
    pos = read_accessor(gltf, prim.attributes.POSITION).astype(np.float64)
    uv = read_accessor(gltf, prim.attributes.TEXCOORD_0).astype(np.float64)
    head = pos[(pos[:, 1] > 0.55) & (pos[:, 1] < 0.98) & (pos[:, 2] > 0.08)]
    brow = np.linalg.norm(pos[:, :2] - np.array([0.090, 0.86]), axis=1)
    skin_uv = uv[int(np.argmin(brow))]
    positions, normals, uvs, faces, targets = build(head, skin_uv)

    chest = [gltf.nodes[j].name for j in gltf.skins[0].joints].index('Chest')
    binary = bytearray(gltf.binary_blob())
    count = len(positions)
    joints = np.zeros((count, 4), np.uint16)
    weights = np.zeros((count, 4), np.float32)
    joints[:, 0] = chest
    weights[:, 0] = 1.0
    region = np.ones(count, np.float32)
    attrs = Attributes(
        POSITION=append_accessor(gltf, binary, positions, 5126, 'VEC3', target=34962, bounds=True),
        NORMAL=append_accessor(gltf, binary, normals, 5126, 'VEC3', target=34962),
        TEXCOORD_0=append_accessor(gltf, binary, uvs, 5126, 'VEC2', target=34962),
        JOINTS_0=append_accessor(gltf, binary, joints, 5123, 'VEC4', target=34962),
        WEIGHTS_0=append_accessor(gltf, binary, weights, 5126, 'VEC4', target=34962),
    )
    setattr(attrs, '_GLOW_SKIN_REGION', append_accessor(gltf, binary, region, 5126, 'SCALAR', target=34962))
    lid_targets = [
        Attributes(POSITION=append_accessor(gltf, binary, delta, 5126, 'VEC3', target=34962, bounds=True))
        for delta in targets
    ]
    source = gltf.materials[0]
    lid_material = Material(
        name='EyeLidSkin',
        doubleSided=True,
        alphaMode='OPAQUE',
        pbrMetallicRoughness=source.pbrMetallicRoughness,
    )
    gltf.materials.append(lid_material)
    gltf.meshes.append(Mesh(
        name='EyeLids',
        weights=[0.0, 0.0, 0.0, 0.0],
        extras={'targetNames': TARGET_NAMES},
        primitives=[Primitive(
            attributes=attrs,
            material=len(gltf.materials) - 1,
            targets=lid_targets,
            indices=append_accessor(gltf, binary, faces.reshape(-1), 5125, 'SCALAR', target=34963),
        )],
    ))
    skin = gltf.nodes[0].skin
    scene = gltf.scenes[gltf.scene or 0]
    gltf.nodes.append(Node(name='EyeLids', mesh=len(gltf.meshes) - 1, skin=skin))
    scene.nodes.append(len(gltf.nodes) - 1)
    for name, center, *_rest in EYES:
        gltf.nodes.append(Node(
            name=name,
            translation=[float(center[0]), float(center[1]), 0.22],
        ))
        scene.nodes.append(len(gltf.nodes) - 1)
    gltf.buffers[0].byteLength = len(binary)
    gltf.set_binary_blob(bytes(binary))
    gltf.save_binary(str(destination))
    print('saved', destination, 'bytes', destination.stat().st_size)


if __name__ == '__main__':
    mount(Path(sys.argv[1]))
