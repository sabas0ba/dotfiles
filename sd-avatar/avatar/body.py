"""素体 (資料 1) の mesh。頭部、胴、腕、ミトン手、脚、ブロック足を loft で構成する。

各部位は独立した閉じた shell とし、関節の内部で重ねる。tag は weight 規則の選択に使う。
"""

from __future__ import annotations

import math

from avatar import spec
from avatar.geometry import Mesh, add, loft, loft_along_axis, ring, tube
from avatar.spec import h

SEGMENTS_TORSO = 24
SEGMENTS_HEAD = 32
SEGMENTS_LIMB = 14

# tag ごとの weight 規則 (avatar.weights.weights_for を参照)。
WEIGHT_RULES: dict[str, str] = {
    "head": "bone:Head",
    "torso": "chain:torso",
    "arm.L": "chain:arm.L",
    "arm.R": "chain:arm.R",
    "leg.L": "chain:leg.L",
    "leg.R": "chain:leg.R",
}

X_AXIS = (1.0, 0.0, 0.0)
UP = (0.0, 0.0, 1.0)
DOWN = (0.0, 0.0, -1.0)


def head() -> Mesh:
    """横に広い楕円体を顎に向けて絞った頭部。"""
    cx, cy, cz = spec.HEAD_CENTER
    rx, ry, rz = spec.HEAD_RADII
    rings = []
    steps = 16
    for i in range(steps + 1):
        polar = math.radians(8.0 + (172.0 - 8.0) * i / steps)
        z = cz + rz * math.cos(polar)
        s = math.sin(polar) * spec.jaw_scale(z)
        rings.append(ring((cx, cy, z), X_AXIS, (0.0, 1.0, 0.0), rx * s, ry * s, SEGMENTS_HEAD))
    # 頭頂側 (polar 小) が最後の ring になるよう並びは上から下ではなく下から上にする。
    rings.reverse()
    return loft(rings, "Skin", "head")


def torso() -> Mesh:
    """股から首までの胴。肩の張りと短い首を含む。"""
    profile = [
        (h(0.74), h(0.06), h(0.05)),
        (h(0.77), h(0.15), h(0.11)),
        (h(0.82), h(0.19), h(0.13)),
        (h(0.90), h(0.21), h(0.14)),
        (h(1.00), h(0.205), h(0.135)),
        (h(1.10), h(0.19), h(0.125)),
        (h(1.20), h(0.20), h(0.13)),
        (h(1.28), h(0.215), h(0.13)),
        (h(1.33), h(0.19), h(0.125)),
        (h(1.37), h(0.13), h(0.10)),
        (h(1.41), h(0.10), h(0.09)),
        (h(1.50), h(0.095), h(0.085)),
    ]
    return loft_along_axis((0.0, 0.0, 0.0), UP, profile, SEGMENTS_TORSO, "Skin", "torso", X_AXIS)


def leg(side: float) -> Mesh:
    tag = "leg.L" if side > 0 else "leg.R"
    profile = [
        (h(0.00), h(0.095), h(0.10)),
        (h(0.15), h(0.09), h(0.095)),
        (h(0.30), h(0.085), h(0.09)),
        (h(0.45), h(0.08), h(0.085)),
        (h(0.60), h(0.075), h(0.08)),
        (h(0.75), h(0.07), h(0.075)),
        (h(0.82), h(0.065), h(0.07)),
    ]
    start = (side * spec.LEG_X, 0.0, h(0.92))
    return loft_along_axis(start, DOWN, profile, SEGMENTS_LIMB, "Skin", tag, X_AXIS)


def foot(side: float) -> Mesh:
    """踵から爪先へ向かう丸みのあるブロック足。底面は平らにする。"""
    tag = "leg.L" if side > 0 else "leg.R"
    profile = [
        (h(0.000), h(0.02), h(0.02)),
        (h(0.015), h(0.06), h(0.055)),
        (h(0.060), h(0.075), h(0.065)),
        (h(0.130), h(0.075), h(0.06)),
        (h(0.200), h(0.07), h(0.05)),
        (h(0.240), h(0.05), h(0.035)),
        (h(0.255), h(0.01), h(0.01)),
    ]
    start = (side * spec.LEG_X, -h(0.09), h(0.065))
    mesh = loft_along_axis(start, (0.0, 1.0, 0.0), profile, SEGMENTS_LIMB, "Skin", tag, X_AXIS)
    floor = h(0.006)
    mesh.verts = [(v[0], v[1], max(v[2], floor)) for v in mesh.verts]
    return mesh


def arm(side: float) -> Mesh:
    tag = "arm.L" if side > 0 else "arm.R"
    profile = [
        (h(0.00), h(0.060), h(0.060)),
        (h(0.06), h(0.068), h(0.066)),
        (h(0.28), h(0.058), h(0.056)),
        (h(0.44), h(0.052), h(0.050)),
        (h(0.50), h(0.048), h(0.045)),
        (h(0.53), h(0.045), h(0.042)),
    ]
    start = spec.along_arm(-h(0.04), side)
    direction = (side * spec.ARM_DIR[0], spec.ARM_DIR[1], spec.ARM_DIR[2])
    return loft_along_axis(start, direction, profile, SEGMENTS_LIMB, "Skin", tag)


def hand(side: float) -> Mesh:
    """ミトン形状の手。掌は体側を向き、前後に広く左右に薄い。"""
    tag = "arm.L" if side > 0 else "arm.R"
    profile = [
        (h(0.00), h(0.040), h(0.035)),
        (h(0.03), h(0.060), h(0.042)),
        (h(0.08), h(0.066), h(0.045)),
        (h(0.12), h(0.060), h(0.040)),
        (h(0.15), h(0.035), h(0.025)),
        (h(0.16), h(0.010), h(0.008)),
    ]
    start = spec.along_arm(spec.WRIST_DIST - h(0.02), side)
    direction = (side * spec.ARM_DIR[0], spec.ARM_DIR[1], spec.ARM_DIR[2])
    mesh = loft_along_axis(start, direction, profile, SEGMENTS_LIMB, "Skin", tag)
    mesh.append(thumb(side))
    return mesh


def thumb(side: float) -> Mesh:
    tag = "arm.L" if side > 0 else "arm.R"
    p0 = spec.along_arm(spec.WRIST_DIST + h(0.02), side)
    path = [
        p0,
        add(p0, (-side * h(0.02), -h(0.035), -h(0.02))),
        add(p0, (-side * h(0.03), -h(0.060), -h(0.045))),
    ]
    radii = [(h(0.022), h(0.020)), (h(0.020), h(0.018)), (h(0.006), h(0.006))]
    return tube(path, radii, lambda _p: UP, 8, "Skin", tag)


def build() -> Mesh:
    mesh = Mesh()
    mesh.append(head())
    mesh.append(torso())
    for side in (1.0, -1.0):
        mesh.append(arm(side))
        mesh.append(hand(side))
        mesh.append(leg(side))
        mesh.append(foot(side))
    return mesh
