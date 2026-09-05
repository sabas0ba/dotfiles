"""衣装 (黒のタートルネック、パンツ、ショートブーツ) とピアス。

素体の各部位を外側へ offset した shell として構成し、素体と同じ chain の weight を与える。
"""

from __future__ import annotations

from avatar import spec
from avatar.body import DOWN, SEGMENTS_LIMB, SEGMENTS_TORSO, UP, X_AXIS
from avatar.geometry import Mesh, loft_along_axis, octahedron
from avatar.spec import h

WEIGHT_RULES: dict[str, str] = {
    "sweater": "chain:torso",
    "sleeve.L": "chain:arm.L",
    "sleeve.R": "chain:arm.R",
    "pants": "chain:torso",
    "pantleg.L": "chain:leg.L",
    "pantleg.R": "chain:leg.R",
    "boot.L": "chain:leg.L",
    "boot.R": "chain:leg.R",
    "earring": "bone:Head",
}


def sweater_body() -> Mesh:
    """裾から襟まで。肩を張らせた箱型のシルエットと、顎の下まで立つ襟。"""
    profile = [
        (h(0.96), h(0.20), h(0.14)),
        (h(0.98), h(0.245), h(0.175)),
        (h(1.08), h(0.24), h(0.170)),
        (h(1.20), h(0.245), h(0.170)),
        (h(1.30), h(0.255), h(0.170)),
        (h(1.36), h(0.20), h(0.150)),
        (h(1.40), h(0.15), h(0.130)),
        (h(1.47), h(0.15), h(0.130)),
        (h(1.49), h(0.13), h(0.115)),
    ]
    return loft_along_axis((0.0, 0.0, 0.0), UP, profile, SEGMENTS_TORSO, "Cloth", "sweater", X_AXIS)


def sleeve(side: float) -> Mesh:
    """ふくらみのある袖。手首で絞り、手の先だけを見せる。"""
    tag = "sleeve.L" if side > 0 else "sleeve.R"
    profile = [
        (h(0.00), h(0.085), h(0.085)),
        (h(0.08), h(0.105), h(0.100)),
        (h(0.26), h(0.100), h(0.095)),
        (h(0.42), h(0.095), h(0.090)),
        (h(0.50), h(0.075), h(0.070)),
        (h(0.54), h(0.068), h(0.062)),
        (h(0.56), h(0.055), h(0.050)),
    ]
    start = spec.along_arm(-h(0.03), side)
    direction = (side * spec.ARM_DIR[0], spec.ARM_DIR[1], spec.ARM_DIR[2])
    return loft_along_axis(start, direction, profile, SEGMENTS_LIMB, "Cloth", tag)


def pants_pelvis() -> Mesh:
    profile = [
        (h(0.72), h(0.10), h(0.08)),
        (h(0.76), h(0.19), h(0.14)),
        (h(0.84), h(0.22), h(0.155)),
        (h(0.94), h(0.23), h(0.160)),
        (h(1.02), h(0.22), h(0.150)),
    ]
    return loft_along_axis((0.0, 0.0, 0.0), UP, profile, SEGMENTS_TORSO, "Cloth", "pants", X_AXIS)


def pants_leg(side: float) -> Mesh:
    tag = "pantleg.L" if side > 0 else "pantleg.R"
    profile = [
        (h(0.00), h(0.115), h(0.120)),
        (h(0.20), h(0.110), h(0.115)),
        (h(0.40), h(0.105), h(0.110)),
        (h(0.55), h(0.100), h(0.105)),
        (h(0.60), h(0.095), h(0.100)),
    ]
    start = (side * spec.LEG_X, 0.0, h(0.92))
    return loft_along_axis(start, DOWN, profile, SEGMENTS_LIMB, "Cloth", tag, X_AXIS)


def boot(side: float) -> Mesh:
    """足を覆う部分と、折り返しのある短い筒。"""
    tag = "boot.L" if side > 0 else "boot.R"
    mesh = Mesh()
    foot_profile = [
        (h(0.000), h(0.03), h(0.03)),
        (h(0.015), h(0.08), h(0.070)),
        (h(0.060), h(0.09), h(0.080)),
        (h(0.130), h(0.09), h(0.075)),
        (h(0.200), h(0.085), h(0.065)),
        (h(0.250), h(0.065), h(0.045)),
        (h(0.270), h(0.015), h(0.015)),
    ]
    start = (side * spec.LEG_X, -h(0.105), h(0.075))
    foot = loft_along_axis(
        start, (0.0, 1.0, 0.0), foot_profile, SEGMENTS_LIMB, "Boots", tag, X_AXIS
    )
    floor = h(0.002)
    foot.verts = [(v[0], v[1], max(v[2], floor)) for v in foot.verts]
    mesh.append(foot)
    shaft_profile = [
        (h(0.00), h(0.095), h(0.100)),
        (h(0.18), h(0.095), h(0.100)),
        (h(0.22), h(0.110), h(0.115)),
        (h(0.30), h(0.112), h(0.117)),
        (h(0.32), h(0.100), h(0.105)),
    ]
    shaft_start = (side * spec.LEG_X, h(0.005), h(0.03))
    mesh.append(
        loft_along_axis(shaft_start, UP, shaft_profile, SEGMENTS_LIMB, "Boots", tag, X_AXIS)
    )
    return mesh


def earring(side: float) -> Mesh:
    x, y, z = spec.EARRING_POS
    stem = loft_along_axis(
        (side * x, y, z + h(0.05)),
        DOWN,
        [(0.0, h(0.004), h(0.004)), (h(0.04), h(0.004), h(0.004))],
        6,
        "Earring",
        "earring",
        X_AXIS,
    )
    gem = octahedron((side * x, y, z), h(0.018), h(0.018), h(0.03), "Earring", "earring")
    stem.append(gem)
    return stem


def build() -> Mesh:
    mesh = Mesh()
    mesh.append(sweater_body())
    mesh.append(pants_pelvis())
    for side in (1.0, -1.0):
        mesh.append(sleeve(side))
        mesh.append(pants_leg(side))
        mesh.append(boot(side))
        mesh.append(earring(side))
    return mesh
