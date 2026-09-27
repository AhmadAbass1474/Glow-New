"""Rig the reduced green dinosaur with the Glow app skeleton and clips.

The sculpt is authored with its left (+x) arm raised in a wave and its right
arm hanging. Both arms are separate from the flank below the shoulder, so each
limb is skinned rigidly to one bone with a short harmonic blend at the joint.

Run from tools/character:
    python dino/rig_dino.py dino/dino_green.glb dino/dino_rigged.glb
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np
from pygltflib import (
    GLTF2, Animation, AnimationChannel, AnimationChannelTarget, AnimationSampler,
    Attributes, Material, PbrMetallicRoughness, Primitive, Skin,
)
from scipy.sparse import coo_matrix, diags
from scipy.sparse.csgraph import connected_components
from scipy.sparse.linalg import spsolve

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from rig_port_frontal import append_accessor, make_skeleton, quat, read_accessor  # noqa: E402
from mouth_pro import BODY_X as MOUTH_X, MOUTH_Y0, build_mouth  # noqa: E402

# Front-view landmarks of the +x side as (x, y); the mesh is mirrored about
# BODY_X and depth comes from the mesh.
BODY_X = -.062
M = lambda x: 2*BODY_X-x
SHOULDER = {'Left': (.140, .462), 'Right': (M(.140), .462)}
HAND = {'Left': (.330, .572), 'Right': (M(.330), .572)}
LEG_X = {'Left': .050, 'Right': M(.050)}
HIP_Y, KNEE_Y, ANKLE_Y = .150, .095, .045
# Hanging arms: rotation from the sculpted raised pose about the view axis.
ARM_DOWN = 1.40
# The belly's widest point is 0.169 from the midline and the shoulder bone
# sits at 0.140, so a straight drop drives the paw through the body. Idle
# keeps that shoulder pose, folds the forearm 0.18 rad, and rolls the paw
# 0.90 rad so the open face points back. Both paws stay about 6cm clear.
IDLE_FOREARM_DROP = 0.18
IDLE_HAND_TWIST = -0.90
LIMBS = ['LeftUpperArm', 'RightUpperArm', 'LeftUpperLeg', 'RightUpperLeg']


def smooth(a, b, x):
    t = np.clip((x-a)/(b-a), 0, 1)
    return t*t*(3-2*t)


def depth_mid(points, x, y, r=.025):
    near = points[(np.abs(points[:, 0]-x) < r) & (np.abs(points[:, 1]-y) < r)]
    return float((near[:, 2].min()+near[:, 2].max())/2)


def layout_for(points):
    lay = {}
    z_hip = depth_mid(points, BODY_X, .20, .04)
    lay['Root'] = (BODY_X, 0., z_hip)
    lay['Hips'] = (BODY_X, HIP_Y+.03, z_hip)
    lay['Spine'] = (BODY_X, .30, depth_mid(points, BODY_X, .30, .04))
    lay['Chest'] = (BODY_X, .42, depth_mid(points, BODY_X, .42, .04))
    for side in ('Left', 'Right'):
        s = np.array([*SHOULDER[side], depth_mid(points, *SHOULDER[side])])
        h = np.array([*HAND[side], depth_mid(points, *HAND[side])])
        lay[f'{side}UpperArm'] = tuple(s)
        lay[f'{side}ForeArm'] = tuple(s+.55*(h-s))
        lay[f'{side}Hand'] = tuple(h)
        x = LEG_X[side]
        lay[f'{side}UpperLeg'] = (x, HIP_Y, depth_mid(points, x, HIP_Y))
        lay[f'{side}LowerLeg'] = (x, KNEE_Y, depth_mid(points, x, KNEE_Y))
        lay[f'{side}Foot'] = (x, ANKLE_Y, depth_mid(points, x, ANKLE_Y))
    # Jaw hinge on the face midline, just behind and below the smile.
    lay['Jaw'] = (MOUTH_X, MOUTH_Y0 - .040, .190)
    return {k: tuple(float(c) for c in v) for k, v in lay.items()}


def weld(positions, triangles):
    _, first, inverse = np.unique(np.round(positions/2e-5).astype(np.int64), axis=0,
                                  return_index=True, return_inverse=True)
    inverse = inverse.reshape(-1)
    return positions[first], inverse[triangles]


def graph(count, faces):
    e = np.concatenate([faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 0]]])
    e = np.concatenate([e, e[:, ::-1]])
    return coo_matrix((np.ones(len(e)), (e[:, 0], e[:, 1])), shape=(count, count)).tocsr()


def component_from(adjacency, mask, seed):
    idx = np.flatnonzero(mask)
    sub = adjacency[idx][:, idx]
    _, labels = connected_components(sub, directed=False)
    local = np.flatnonzero(idx == seed)[0]
    out = np.zeros(len(mask), bool)
    out[idx[labels == labels[local]]] = True
    return out


def limb_zones(points, lay):
    """Per limb: vertices pinned to the bone, and the zone where it may blend."""
    zones = {}
    for side in ('Left', 'Right'):
        s = np.array(lay[f'{side}UpperArm'])
        h = np.array(lay[f'{side}Hand'])
        axis = (h-s)/np.linalg.norm(h-s)
        t = (points-s) @ axis
        radial = np.linalg.norm(points-s-t[:, None]*axis, axis=1)
        # The fist is wider than the arm; near the shoulder the limit stays
        # tight so the overhanging cheek remains on the body.
        limit = .085+.6*np.clip(t-.08, 0, .1)
        # Only the head overhangs; under the raised arm there is open air.
        below = points[:, 1] < s[1]+t*axis[1]
        limit = np.where(below, np.maximum(limit, .085+.055*smooth(.03, .10, t)), limit)
        core = (t > .045) & (radial < limit)
        zones[f'{side}UpperArm'] = dict(core=core, blend=(t > -.035) & (radial < limit+.03),
                                        seed=np.argmax(np.where(core, t, -9)))
        x = LEG_X[side]
        lateral = np.hypot(points[:, 0]-x, points[:, 2]-lay[f'{side}UpperLeg'][2])
        core = (points[:, 1] < .085) & (lateral < .12)
        zones[f'{side}UpperLeg'] = dict(core=core, blend=(points[:, 1] < .19) & (lateral < .13),
                                        seed=np.argmin(np.where(core, lateral+points[:, 1], 9)))
    return zones


def transfer_forearm_shell(joints, weights, positions, lay, order):
    """Move the outer arm from the shoulder bone onto the forearm bone.

    The paw can then fold down in Idle without dragging the upper arm into
    the flank. Vertices on the shoulder stay where they are.
    """
    joints = joints.copy()
    weights = weights.copy()
    for side in ('Left', 'Right'):
        shoulder = np.array(lay[f'{side}UpperArm'], dtype=np.float64)
        hand = np.array(lay[f'{side}Hand'], dtype=np.float64)
        axis = hand - shoulder
        axis /= np.linalg.norm(axis)
        upper = order.index(f'{side}UpperArm')
        fore = order.index(f'{side}ForeArm')
        along = (positions - shoulder) @ axis
        share = smooth(0.155, 0.195, along)
        for index in np.flatnonzero(share > 1e-4):
            slots = joints[index]
            influence = weights[index]
            hit = np.flatnonzero(slots == upper)
            if len(hit) == 0 or influence[hit[0]] <= 0:
                continue
            moved = float(influence[hit[0]] * share[index])
            influence[hit[0]] -= moved
            fore_slot = np.flatnonzero(slots == fore)
            if len(fore_slot):
                influence[fore_slot[0]] += moved
            else:
                empty = np.flatnonzero(influence <= 1e-6)
                if len(empty) == 0:
                    continue
                slots[empty[0]] = fore
                influence[empty[0]] = moved
            total = float(influence.sum())
            if total > 0:
                influence /= total
    return joints, weights


def forearm_quat(side):
    sign = 1.0 if side == 'Left' else -1.0
    return np.array(quat(0.0, 0.0, -sign * IDLE_FOREARM_DROP))


def hand_twist_quat(side, lay):
    """Roll the paw around the arm. Negative twist turns the open face back."""
    shoulder = np.array(lay[f'{side}UpperArm'], dtype=np.float64)
    tip = np.array(lay[f'{side}Hand'], dtype=np.float64)
    axis = tip - shoulder
    axis /= np.linalg.norm(axis)
    sign = 1.0 if side == 'Left' else -1.0
    angle = -sign * IDLE_HAND_TWIST
    half = math.sin(angle / 2.0)
    return np.array([axis[0] * half, axis[1] * half, axis[2] * half, math.cos(angle / 2.0)])


def transfer_hand_shell(joints, weights, positions, lay, order):
    """Move the paw from the forearm bone onto the hand bone.

    Idle can then roll the palm without twisting the upper arm. The wrist
    keeps a short blend so the paw does not tear off the forearm.
    """
    joints = joints.copy()
    weights = weights.copy()
    for side in ('Left', 'Right'):
        shoulder = np.array(lay[f'{side}UpperArm'], dtype=np.float64)
        hand = np.array(lay[f'{side}Hand'], dtype=np.float64)
        axis = hand - shoulder
        axis /= np.linalg.norm(axis)
        fore = order.index(f'{side}ForeArm')
        palm = order.index(f'{side}Hand')
        along = (positions - shoulder) @ axis
        share = smooth(0.172, 0.192, along)
        for index in np.flatnonzero(share > 1e-4):
            slots = joints[index]
            influence = weights[index]
            hit = np.flatnonzero(slots == fore)
            if len(hit) == 0 or influence[hit[0]] <= 0:
                continue
            moved = float(influence[hit[0]] * share[index])
            influence[hit[0]] -= moved
            hand_slot = np.flatnonzero(slots == palm)
            if len(hand_slot):
                influence[hand_slot[0]] += moved
            else:
                empty = np.flatnonzero(influence <= 1e-6)
                if len(empty) == 0:
                    continue
                slots[empty[0]] = palm
                influence[empty[0]] = moved
            total = float(influence.sum())
            if total > 0:
                influence /= total
    return joints, weights


def solve_limb_weights(points, faces, lay):
    adjacency = graph(len(points), faces)
    zones = limb_zones(points, lay)
    cores = {name: component_from(adjacency, z['core'], z['seed']) for name, z in zones.items()}
    free_any = np.zeros(len(points), bool)
    for z in zones.values():
        free_any |= z['blend']
    # Edge weights by inverse length keep the blend band metric on uneven triangles.
    coo = adjacency.tocoo()
    length = np.linalg.norm(points[coo.row]-points[coo.col], axis=1)
    w = coo_matrix((1/np.maximum(length, 1e-5), (coo.row, coo.col)), shape=adjacency.shape).tocsr()
    lap = diags(np.asarray(w.sum(axis=1)).ravel())-w
    result = {}
    for name, core in cores.items():
        fixed = ~free_any | np.logical_or.reduce([c for n, c in cores.items()])
        free = ~fixed
        value = core.astype(np.float64)
        rhs = -lap[free][:, fixed] @ value[fixed]
        value[free] = spsolve(lap[free][:, free].tocsc(), rhs)
        result[name] = smooth(0, 1, np.clip(value, 0, 1))
        print(name, 'core', int(core.sum()), 'influenced', int((result[name] > .01).sum()))
    return result


def build_animations(gltf, binary, bones, lay):
    ident = np.array([0., 0., 0., 1.])
    sin, tau = math.sin, math.tau

    def e(x=0., y=0., z=0.):
        return np.array(quat(x, y, z))

    def arm(side, lift=0., swing=0.):
        """``lift`` raises the arm out from hanging (ARM_DOWN is the sculpt);
        ``swing`` moves it forward (negative) or back."""
        sign = 1 if side == 'Left' else -1
        return e(swing, 0, sign*(lift-ARM_DOWN))

    def clip(name, duration, tracks, jaw=None):
        count = max(3, int(round(duration*20))+1)
        times = np.linspace(0, duration, count, dtype=np.float32)
        t_acc = append_accessor(gltf, binary, times, 5126, 'SCALAR', bounds=True)
        anim = Animation(name=name, channels=[], samplers=[])
        limbs = ['LeftUpperArm', 'LeftForeArm', 'LeftHand', 'RightUpperArm', 'RightForeArm', 'RightHand',
                 'LeftUpperLeg', 'LeftLowerLeg', 'LeftFoot', 'RightUpperLeg', 'RightLowerLeg', 'RightFoot']
        defaults = {'LeftUpperArm': lambda u: arm('Left'), 'RightUpperArm': lambda u: arm('Right')}
        if jaw is not None and 'Jaw' in bones:
            tracks = {**tracks, 'Jaw': jaw}
            limbs = limbs + ['Jaw']
        for bone in limbs:
            fn = tracks.get(bone, defaults.get(bone, lambda u: ident))
            q = np.array([fn(i/(count-1)) for i in range(count)], np.float32)
            for i in range(1, count):
                if float(q[i-1] @ q[i]) < 0:
                    q[i] *= -1
            out = append_accessor(gltf, binary, q, 5126, 'VEC4')
            anim.channels.append(AnimationChannel(sampler=len(anim.samplers),
                                                  target=AnimationChannelTarget(node=bones[bone], path='rotation')))
            anim.samplers.append(AnimationSampler(input=t_acc, output=out, interpolation='LINEAR'))
        anim.extras = {'loop': True, 'durationSeconds': duration}
        gltf.animations.append(anim)

    both = lambda f: {'LeftUpperArm': lambda u: arm('Left', *f(u)), 'RightUpperArm': lambda u: arm('Right', *f(u))}
    idle_arms = {
        **both(lambda u: (.04, 0)),
        'LeftForeArm': lambda u: forearm_quat('Left'),
        'RightForeArm': lambda u: forearm_quat('Right'),
        'LeftHand': lambda u: hand_twist_quat('Left', lay),
        'RightHand': lambda u: hand_twist_quat('Right', lay),
    }
    # Happy/Laugh open wide; Sad keeps the jaw shut.
    open_smile = lambda u: e(.22, 0, 0)
    happy = lambda u: e(.52, 0, 0)
    talk = lambda u: e(.08 + .30 * (math.sin(math.pi * 4 * u) ** 2), 0, 0)
    laugh = lambda u: e(.20 + .26 * (.5 - .5 * math.cos(tau * 2 * u)), 0, 0)
    closed = lambda u: e(0, 0, 0)
    clip('Idle', 4.0, idle_arms, jaw=closed)
    clip('Talk', 2.0, {
        'LeftUpperArm': lambda u: arm('Left', .35+.10*sin(tau*2*u), -.35-.10*sin(tau*2*u)),
        'RightUpperArm': lambda u: arm('Right', .10, -.08),
    }, jaw=talk)
    clip('Wave', 2.4, {
        'LeftUpperArm': lambda u: arm('Left', ARM_DOWN+.15+.28*sin(tau*2*u)),
        'RightUpperArm': lambda u: arm('Right', .04),
    }, jaw=open_smile)
    clip('Happy', 2.0, {
        **both(lambda u: (.55+.14*sin(tau*2*u), 0)),
        'LeftUpperLeg': lambda u: e(.08*sin(tau*2*u), 0, 0),
        'RightUpperLeg': lambda u: e(-.08*sin(tau*2*u), 0, 0),
    }, jaw=happy)
    clip('Sad', 4.0, both(lambda u: (-.05, .12)), jaw=closed)
    clip('Thinking', 4.0, {
        'RightUpperArm': lambda u: arm('Right', .55+.03*sin(tau*u), -1.0),
    })
    clip('Victory', 2.4, both(lambda u: (ARM_DOWN+.35+.07*sin(tau*2*u), 0)), jaw=open_smile)
    clip('Walk', 1.2, {
        'LeftUpperLeg': lambda u: e(.30*sin(tau*u), 0, 0),
        'RightUpperLeg': lambda u: e(-.30*sin(tau*u), 0, 0),
        'LeftUpperArm': lambda u: arm('Left', .08, -.30*sin(tau*u)),
        'RightUpperArm': lambda u: arm('Right', .08, .30*sin(tau*u)),
    })
    clip('Smile', 4.0, both(lambda u: (.04+.03*sin(tau*u), 0)), jaw=open_smile)
    clip('Laugh', 2.0, both(lambda u: (ARM_DOWN-.25+.18*sin(tau*3*u), 0)), jaw=laugh)


def main(source, output):
    gltf = GLTF2().load_binary(source)
    prim = gltf.meshes[0].primitives[0]
    positions = read_accessor(gltf, prim.attributes.POSITION).astype(np.float64)
    normals_v = read_accessor(gltf, prim.attributes.NORMAL).astype(np.float32)
    uvs = read_accessor(gltf, prim.attributes.TEXCOORD_0).astype(np.float32)
    triangles = read_accessor(gltf, prim.indices).reshape(-1, 3).astype(np.int64)
    points, faces = weld(positions, triangles)
    _, inverse = np.unique(np.round(positions/2e-5).astype(np.int64), axis=0, return_inverse=True)
    inverse = inverse.reshape(-1)
    lay = layout_for(points)
    limb = solve_limb_weights(points, faces, lay)

    bones = make_skeleton(gltf, lay)
    order = list(bones)
    count = len(positions)
    joints = np.zeros((count, 4), np.uint16)
    weights = np.zeros((count, 4), np.float32)
    stack = np.stack([limb[name][inverse] for name in LIMBS], 1)
    pick = np.argsort(-stack, axis=1)[:, :3]
    ids = np.array([order.index(name) for name in LIMBS])
    joints[:, 1:] = ids[pick]
    weights[:, 1:] = np.take_along_axis(stack, pick, 1)
    total = weights[:, 1:].sum(1)
    over = total > 1
    weights[over, 1:] /= total[over, None]
    weights[:, 0] = 1-weights[:, 1:].sum(1)
    joints[:, 0] = order.index('Chest')
    if order.index('Jaw') != 16:
        raise RuntimeError('Jaw must stay bone 16 so the mouth weights line up')
    mouth = build_mouth(positions, normals_v, uvs, triangles, joints, weights, n_bones=len(order))
    positions = mouth['positions']
    normals_v = mouth['normals']
    uvs = mouth['uvs']
    triangles = mouth['indices']
    joints = mouth['joints']
    weights = mouth['weights']
    joints, weights = transfer_forearm_shell(joints, weights, positions, lay, order)
    joints, weights = transfer_hand_shell(joints, weights, positions, lay, order)
    lay['Jaw'] = mouth['anchors']['Jaw']
    # Refresh the jaw node translation after the measured hinge is known.
    jaw_node = gltf.nodes[bones['Jaw']]
    root = np.array(lay['Root'], dtype=np.float32)
    jaw_node.translation = (np.array(lay['Jaw'], dtype=np.float32) - root).tolist()

    binary = bytearray(gltf.binary_blob())
    index_type, index_arr = ((5123, np.uint16) if triangles.max() < 65535 else (5125, np.uint32))
    prim.indices = append_accessor(gltf, binary, triangles.reshape(-1).astype(index_arr),
                                   index_type, 'SCALAR', target=34963)
    prim.attributes.POSITION = append_accessor(gltf, binary, positions.astype(np.float32), 5126, 'VEC3',
                                               target=34962, bounds=True)
    prim.attributes.NORMAL = append_accessor(gltf, binary, normals_v.astype(np.float32), 5126, 'VEC3',
                                             target=34962)
    prim.attributes.TEXCOORD_0 = append_accessor(gltf, binary, uvs.astype(np.float32), 5126, 'VEC2',
                                                 target=34962)
    prim.attributes.JOINTS_0 = append_accessor(gltf, binary, joints, 5123, 'VEC4', target=34962)
    prim.attributes.WEIGHTS_0 = append_accessor(gltf, binary, weights, 5126, 'VEC4', target=34962)
    setattr(prim.attributes, '_GLOW_SKIN_REGION',
            append_accessor(gltf, binary, np.ones(len(positions), np.float32), 5126, 'SCALAR', target=34962))
    for part in mouth['interior']:
        attrs = Attributes(
            POSITION=append_accessor(gltf, binary, part['positions'], 5126, 'VEC3', target=34962, bounds=True),
            NORMAL=append_accessor(gltf, binary, part['normals'], 5126, 'VEC3', target=34962),
            JOINTS_0=append_accessor(gltf, binary, part['joints'], 5123, 'VEC4', target=34962),
            WEIGHTS_0=append_accessor(gltf, binary, part['weights'], 5126, 'VEC4', target=34962))
        setattr(attrs, '_GLOW_SKIN_REGION', append_accessor(
            gltf, binary, np.zeros(len(part['positions']), np.float32), 5126, 'SCALAR', target=34962))
        gltf.materials.append(Material(
            name=part['name'], doubleSided=True,
            pbrMetallicRoughness=PbrMetallicRoughness(
                baseColorFactor=part['color'], metallicFactor=0., roughnessFactor=part['roughness'])))
        gltf.meshes[0].primitives.append(Primitive(
            attributes=attrs, material=len(gltf.materials) - 1,
            indices=append_accessor(gltf, binary, part['indices'].reshape(-1).astype(np.uint32),
                                    5125, 'SCALAR', target=34963)))
    inv = [(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -x, -y, -z, 1) for x, y, z in (lay[n] for n in order)]
    gltf.skins = [Skin(name='DinoRig', skeleton=bones['Root'], joints=[bones[n] for n in order],
                       inverseBindMatrices=append_accessor(gltf, binary, np.array(inv, np.float32), 5126, 'MAT4'))]
    node = gltf.nodes[0]
    node.name = 'GlowCharacter'
    node.skin = 0

    gltf.animations = []
    build_animations(gltf, binary, bones, lay)
    gltf.buffers[0].byteLength = len(binary)
    gltf.set_binary_blob(bytes(binary))
    gltf.extras = {'character': 'Glow dinosaur', 'rigVersion': 7,
                   'face': 'open-close smile', 'skinPalette': 'localized-green-chroma-v1'}
    gltf.save_binary(output)
    print('saved', output, 'verts', len(positions), 'tris', len(triangles))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
