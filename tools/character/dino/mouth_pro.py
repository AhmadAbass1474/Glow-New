"""Symmetric open/close smile for the dinosaur.

The seam is a parabola measured on the painted smile and mirrored about the
face midline. Jaw weight is the same on both sides: full at the centre of the
lower lip, zero on the upper lip, zero at both corners, short fade on cream.
"""
from __future__ import annotations

import numpy as np
from scipy.sparse import coo_matrix
from scipy.spatial import cKDTree

from port_face_rig import normals, pack
from port_lip_surface import split_lips

# Measured on dino_mirror.glb. Midline is the sculpt mirror plane.
BODY_X = -.062
MOUTH_HALF = .111
MOUTH_Y0 = .585
MOUTH_LIFT = .033
JAW_INDEX = 16


def lip_field(p):
    u = (p[:, 0] - BODY_X) / MOUTH_HALF
    return p[:, 1] - (MOUTH_Y0 + MOUTH_LIFT * u * u)


def _envelope(x):
    u = np.clip((x - BODY_X) / MOUTH_HALF, -1, 1)
    return np.cos(u * np.pi / 2)


def _seam_curve(points):
    u = np.linspace(-1, 1, 25)
    curve = np.column_stack([
        BODY_X + u * MOUTH_HALF,
        MOUTH_Y0 + MOUTH_LIFT * u * u,
        np.zeros(len(u)),
    ])
    depth = []
    for point in curve:
        dist = np.hypot(points[:, 0] - point[0], points[:, 1] - point[1])
        near = dist < .015
        depth.append(float(points[near, 2].max()) if near.any() else np.nan)
    depth = np.array(depth)
    if np.isnan(depth).any():
        known = np.flatnonzero(~np.isnan(depth))
        depth[np.isnan(depth)] = np.interp(np.flatnonzero(np.isnan(depth)), known, depth[known])
    depth = .5 * (depth + depth[::-1])
    curve[:, 2] = depth
    return curve


def _jaw_weights(points, faces, surface):
    x = points[:, 0]
    field = lip_field(points)
    envelope = _envelope(x)
    rise = np.clip(-field / .008, 0, 1)
    fade = 1 - np.clip((-field - .010) / .022, 0, 1)
    jaw = envelope * rise * fade
    jaw[(field > .001) | (points[:, 2] < .185) | (np.abs(x - BODY_X) > MOUTH_HALF)] = 0
    jaw[surface['upper']] = 0
    jaw[surface['upperCopies']] = 0
    jaw[surface['lower']] = envelope[surface['lower']]
    jaw[surface['lowerCopies']] = envelope[surface['lowerCopies']]

    mirror = points.copy()
    mirror[:, 0] = 2 * BODY_X - mirror[:, 0]
    dist, twin = cKDTree(points).query(mirror, k=1)
    paired = dist < .004
    jaw[paired] = .5 * (jaw[paired] + jaw[twin[paired]])

    edges = np.concatenate([faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 0]]])
    weights = coo_matrix((np.ones(len(edges)), (edges[:, 0], edges[:, 1])), shape=(len(points),) * 2).tocsr()
    degree = np.asarray(weights.sum(1)).ravel()
    neighbour = np.asarray(weights @ jaw).ravel() / np.maximum(degree, 1)
    # Only kill a lone high weight on the cheek, never the lip centre.
    spike = (jaw > .5) & (neighbour < .25) & (envelope < .55)
    jaw[spike] = neighbour[spike]
    jaw[jaw < .02] = 0
    return jaw.astype(np.float64), int(spike.sum())


def _pink_cavity(curve, envelope):
    """Recessed cavity: covered by the closed lips, visible only in the open gap."""
    count = len(curve)
    rows = 7
    lift = np.cos(np.linspace(-1, 1, count) * np.pi / 2)
    pos, jaw = [], []
    for s in np.linspace(0, 1, rows):
        for i in range(count):
            point = curve[i].copy()
            # Sit behind the seam so a closed mouth hides the whole sheet.
            point[1] -= s * .006 * lift[i]
            point[2] -= (.010 + .032 * s) * max(float(lift[i]), .15)
            pos.append(point)
            jaw.append(s * float(envelope[i]))
    pos = np.array(pos, np.float32)
    tri = []
    for row in range(1, rows):
        for col in range(count - 1):
            a = (row - 1) * count + col
            b, c, d = a + 1, row * count + col, row * count + col + 1
            # Winding faces outward (+z) so the cavity reads from the front.
            tri.extend(((a, c, b), (b, c, d)))
    tri = np.array(tri, np.int64)
    full = np.zeros((len(pos), JAW_INDEX + 1), np.float64)
    jaw = np.array(jaw)
    full[:, JAW_INDEX] = jaw
    full[:, 0] = 1 - jaw
    joints, packed = pack(full)
    return dict(positions=pos, normals=normals(pos, tri), indices=tri,
                joints=joints, weights=packed, name='MouthInterior',
                color=[.52, .14, .16, 1.], roughness=.72, metallic=0.)


def build_mouth(p, n, uv, triangles, joints, weights, *, n_bones):
    triangles = triangles.reshape(-1, 3).astype(np.int64)
    source_count = len(p)
    surface = split_lips(p, n, uv, triangles, f=lip_field(p), body_x=BODY_X,
                         cut_x=MOUTH_HALF + .004, cut_z=.190, cut_y_min=.560,
                         mouth_half=MOUTH_HALF)
    p = surface['positions'].astype(np.float64)
    n = surface['normals'].astype(np.float32)
    uv = surface['uvs'].astype(np.float32)
    faces = surface['indices'].astype(np.int64)
    full = np.zeros((len(p), n_bones), np.float64)
    for slot in range(4):
        np.add.at(full[:source_count], (np.arange(source_count), joints[:, slot]), weights[:, slot])
    full[source_count:, 0] = 1

    jaw, spikes = _jaw_weights(p, faces, surface)
    active = jaw > 0
    full[active] = 0
    full[active, JAW_INDEX] = jaw[active]
    full[active, 0] = 1 - jaw[active]
    out_j, out_w = pack(full)

    curve = _seam_curve(p)
    left = jaw[p[:, 0] < BODY_X - .02].max() if np.any(p[:, 0] < BODY_X - .02) else 0
    right = jaw[p[:, 0] > BODY_X + .02].max() if np.any(p[:, 0] > BODY_X + .02) else 0
    print('jaw verts', int(active.sum()), 'max', round(float(jaw.max()), 3),
          'left', round(float(left), 3), 'right', round(float(right), 3),
          'spikes', spikes)
    hinge_z = float(curve[len(curve) // 2, 2] - .050)
    return dict(positions=p.astype(np.float32), normals=n, uvs=uv, indices=faces,
                joints=out_j, weights=out_w,
                interior=[_pink_cavity(curve, _envelope(curve[:, 0]))],
                anchors={'Jaw': (BODY_X, MOUTH_Y0 - .040, hinge_z)})
