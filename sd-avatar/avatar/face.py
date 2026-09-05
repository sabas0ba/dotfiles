"""顔パーツ (目、瞳、ハイライト、ドット目、眉、口) の設計形状。

すべて頭部前面の表面に投影した平面的な板で構成する。ここで返す位置は「設計形状」であり、
rest 状態 (口は閉じ、ドット目は隠す) と各 shape key の形状は avatar.shapekeys が導出する。
"""

from __future__ import annotations

from avatar import spec
from avatar.geometry import Mesh, Vec, catmull_rom, disk, tube
from avatar.spec import h

# tag の基底名ごとの表面からの浮かせ量。重なる板の描画順を決める。
OFFSETS: dict[str, float] = {
    "eye": h(0.004),
    "pupil": h(0.007),
    "hl": h(0.010),
    "dot": h(0.012),
    "brow": h(0.005),
    "mouth": h(0.004),
}

WEIGHT_RULES: dict[str, str] = {
    base + sfx: "bone:Head" for base in OFFSETS for sfx in ("", ".L", ".R")
}

X_AXIS = (1.0, 0.0, 0.0)
UP = (0.0, 0.0, 1.0)


def split_tag(tag: str) -> tuple[str, str | None]:
    """ "eye.L" -> ("eye", "L")、"mouth" -> ("mouth", None)。"""
    base, _, side = tag.partition(".")
    return base, (side or None)


def on_surface(x: float, z: float, offset: float) -> Vec:
    """頭部前面の表面から offset だけ手前 (-Y) の点。頭部の外なら前面の最も近い深さを使う。"""
    y = spec.head_surface_y(x, z)
    if y is None:
        y = spec.HEAD_CENTER[1] - spec.HEAD_RADII[1] * 0.6
    return (x, y - offset, z)


def _projector(base: str):
    off = OFFSETS[base]
    return lambda p: on_surface(p[0], p[2], off)


def eye_center(side: str) -> tuple[float, float]:
    sign = 1.0 if side == "L" else -1.0
    return sign * spec.EYE_CENTER_X, spec.EYE_CENTER_Z


def _eye_layers(side: str) -> Mesh:
    cx, cz = eye_center(side)
    hw, hh = spec.EYE_HALF_W, spec.EYE_HALF_H
    mesh = Mesh()

    iris = disk(
        (cx, 0.0, cz), X_AXIS, UP, hw, hh, 4, 24, "Eye", f"eye.{side}", 2.4, _projector("eye")
    )
    # 最外周だけを濃い縁にし、内側は明るい光彩にする。
    for i in range(len(iris.faces)):
        if i < 24 * 3:
            iris.face_materials[i] = "EyeLight"
    mesh.append(iris)

    pupil = disk(
        (cx, 0.0, cz - hh * 0.05),
        X_AXIS,
        UP,
        hw * 0.48,
        hh * 0.52,
        1,
        16,
        "EyeDark",
        f"pupil.{side}",
        2.0,
        _projector("pupil"),
    )
    mesh.append(pupil)

    sign = 1.0 if side == "L" else -1.0
    highlight = disk(
        (cx - sign * hw * 0.35, 0.0, cz + hh * 0.45),
        X_AXIS,
        UP,
        hw * 0.22,
        hh * 0.16,
        1,
        12,
        "Highlight",
        f"hl.{side}",
        2.0,
        _projector("hl"),
    )
    mesh.append(highlight)

    dot = disk(
        (cx, 0.0, cz),
        X_AXIS,
        UP,
        hw * 0.28,
        hh * 0.55,
        1,
        16,
        "EyeDark",
        f"dot.{side}",
        3.0,
        _projector("dot"),
    )
    mesh.append(dot)
    return mesh


def brow_x_range(side: str) -> tuple[float, float]:
    """眉の内端と外端の x 座標 (絶対値)。shape key の傾き計算にも使う。"""
    inner = spec.EYE_CENTER_X - spec.EYE_HALF_W * 0.7
    outer = spec.EYE_CENTER_X + spec.EYE_HALF_W * 0.8
    return inner, outer


def _brow(side: str) -> Mesh:
    sign = 1.0 if side == "L" else -1.0
    inner, outer = brow_x_range(side)
    z = spec.BROW_Z
    off = OFFSETS["brow"]
    controls = [
        on_surface(sign * inner, z - h(0.010), off),
        on_surface(sign * (inner + outer) * 0.5, z + h(0.006), off),
        on_surface(sign * outer, z - h(0.012), off),
    ]
    path = catmull_rom(controls, 7)
    r = h(0.009)
    radii = [(r, r * 0.6)] * len(path)
    forward = (0.0, -1.0, 0.0)
    return tube(path, radii, lambda _p: forward, 6, "Brow", f"brow.{side}")


def mouth() -> Mesh:
    """全開時の口。rest 状態では avatar.shapekeys が薄い線に潰す。"""
    return disk(
        (0.0, 0.0, spec.MOUTH_Z),
        X_AXIS,
        UP,
        spec.MOUTH_HALF_W,
        spec.MOUTH_FULL_H * 0.5,
        2,
        16,
        "Mouth",
        "mouth",
        2.0,
        _projector("mouth"),
    )


def build() -> Mesh:
    mesh = Mesh()
    for side in ("L", "R"):
        mesh.append(_eye_layers(side))
        mesh.append(_brow(side))
    mesh.append(mouth())
    return mesh
