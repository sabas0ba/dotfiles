"""髪 (資料 2 の項目 4)。後ろ髪の shell と、前髪・サイド髪・アホ毛の房で構成する。

房は頭部楕円体の表面に沿う spline に沿った tube で、頭部中心からの放射方向を断面の法線に
使うため捩れない。毛先の gradient は Blender 側で高さから UV を与えて表現する。
"""

from __future__ import annotations

import math

from avatar import spec
from avatar.geometry import Mesh, Vec, catmull_rom, loft, normalize, sub, tube
from avatar.spec import h

WEIGHT_RULES: dict[str, str] = {"hair": "bone:Head"}

SHELL_AZIMUTHS = 32
SHELL_RINGS = 12
CLUMP_SAMPLES = 12
CLUMP_SEGMENTS = 8


def _radial(p: Vec) -> Vec:
    return normalize(sub(p, spec.HEAD_CENTER))


def _shell_polar_max(azimuth: float) -> float:
    """方位角ごとの shell の下端の極角。前面は生え際で止め、側面から後ろは顎の高さまで下げる。"""
    a = abs(azimuth)
    base = math.radians(38.0)
    full = math.radians(128.0)
    t = _smooth(math.radians(40.0), math.radians(85.0), a)
    polar = base + (full - base) * t
    # 毛先の房を表す波。下端が十分に下がる範囲だけに掛ける。
    wave = math.radians(4.0) * math.sin(9.0 * azimuth) * _smooth(math.radians(100.0), full, polar)
    return polar + wave


def _shell_radius_factor(polar: float) -> float:
    return 1.07 + 0.06 * _smooth(math.radians(50.0), math.radians(120.0), polar)


def _smooth(edge0: float, edge1: float, x: float) -> float:
    t = min(1.0, max(0.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def shell() -> Mesh:
    """後ろ髪と側頭部を覆う殻。頭頂側は閉じ、下端は開く。"""
    rings = []
    polar_start = math.radians(6.0)
    for i in range(SHELL_RINGS + 1):
        f = i / SHELL_RINGS
        pts = []
        for j in range(SHELL_AZIMUTHS):
            azimuth = -math.pi + 2.0 * math.pi * j / SHELL_AZIMUTHS
            polar = polar_start + (_shell_polar_max(azimuth) - polar_start) * f
            pts.append(spec.head_point(azimuth, polar, _shell_radius_factor(polar)))
        rings.append(pts)
    return loft(rings, "Hair", "hair", cap_start=True, cap_end=False)


def clump(
    start: tuple[float, float],
    end: tuple[float, float],
    width: float,
    thickness: float,
) -> Mesh:
    """(方位角, 極角) の start から end へ頭部表面に沿って流れる房。先端は尖らせる。"""
    a0, p0 = start
    a1, p1 = end
    # 頭部の殻 (radius factor 1.07〜1.13) の上に載せ、先端は殻から離しすぎない。
    controls = [
        spec.head_point(a0, p0, 1.08),
        spec.head_point(a0 + (a1 - a0) * 0.3, p0 + (p1 - p0) * 0.35, 1.12),
        spec.head_point(a0 + (a1 - a0) * 0.7, p0 + (p1 - p0) * 0.70, 1.11),
        spec.head_point(a1, p1, 1.06),
    ]
    path = catmull_rom(controls, CLUMP_SAMPLES)
    radii = []
    for i in range(CLUMP_SAMPLES):
        t = i / (CLUMP_SAMPLES - 1)
        # 先端近くまで幅を保ち、最後に尖らせる。隣の房と重なり合って面として見えるようにする。
        envelope = (0.7 + 0.3 * math.sin(math.pi * t)) * (1.0 - t**6)
        radii.append((max(width * envelope, h(0.004)), max(thickness * envelope, h(0.003))))
    return tube(path, radii, _radial, CLUMP_SEGMENTS, "Hair", "hair")


# (start azimuth, start polar, end azimuth, end polar, width, thickness)。
# 左側の定義であり、右側は鏡映して作る。
BANGS: list[tuple[float, float, float, float, float, float]] = [
    (3.0, 12.0, 7.0, 90.0, 0.090, 0.030),
    (12.0, 12.0, 18.0, 96.0, 0.100, 0.032),
    (22.0, 13.0, 30.0, 100.0, 0.100, 0.032),
    (34.0, 15.0, 44.0, 102.0, 0.095, 0.030),
    (46.0, 20.0, 57.0, 112.0, 0.085, 0.030),
]

SIDE_LOCKS: list[tuple[float, float, float, float, float, float]] = [
    (58.0, 30.0, 64.0, 128.0, 0.075, 0.035),
    (72.0, 35.0, 78.0, 136.0, 0.070, 0.035),
]


def ahoge() -> Mesh:
    """頭頂から前へ跳ねる一房。"""
    top = spec.head_point(0.0, math.radians(8.0), 1.08)
    controls = [
        top,
        (top[0] + h(0.01), top[1] - h(0.03), top[2] + h(0.09)),
        (top[0] + h(0.03), top[1] - h(0.10), top[2] + h(0.15)),
        (top[0] + h(0.02), top[1] - h(0.19), top[2] + h(0.13)),
    ]
    path = catmull_rom(controls, 8)
    radii = []
    for i in range(len(path)):
        t = i / (len(path) - 1)
        r = h(0.022) * (1.0 - t**2) + h(0.003)
        radii.append((r, r * 0.7))
    return tube(path, radii, lambda _p: (1.0, 0.0, 0.0), 6, "Hair", "hair")


def build() -> Mesh:
    mesh = Mesh()
    mesh.append(shell())
    for a0, p0, a1, p1, width, thickness in BANGS + SIDE_LOCKS:
        left = clump(
            (math.radians(a0), math.radians(p0)),
            (math.radians(a1), math.radians(p1)),
            h(width),
            h(thickness),
        )
        mesh.append(left)
        mesh.append(left.mirrored_x())
    mesh.append(ahoge())
    return mesh
