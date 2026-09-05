"""顔の shape key を設計形状から導出する。

各 key は「tag ごとの変形」の組で表す。変形は顔平面 (x, z) 上で行い、その後に頭部表面へ
再投影する。表示しない部品は表面の内側 (+Y) へ平行移動して隠す。平行移動なら、隠した状態を
基準にした他の key の差分が相殺されず、DotEyes と Blink を同時に使っても形が保たれる。
"""

from __future__ import annotations

from collections.abc import Callable

from avatar import face, spec
from avatar.geometry import Vec
from avatar.spec import h

HIDE_DEPTH = h(0.06)
MOUTH_CLOSED = 0.08  # 閉じた口の高さ倍率。0 にすると面が縮退するため小さな正の値にする

# 変形関数: (side, x, z) -> (x', z')
Deform = Callable[[str | None, float, float], tuple[float, float]]

ANIME_EYE = ("eye", "pupil", "hl")
ALL_EYE = (*ANIME_EYE, "dot")


def _center(side: str | None) -> tuple[float, float]:
    return face.eye_center(side or "L")


def squash(factor: float) -> Deform:
    def f(side, x, z):
        _cx, cz = _center(side)
        return x, cz + (z - cz) * factor

    return f


def grow(factor: float) -> Deform:
    def f(side, x, z):
        cx, cz = _center(side)
        return cx + (x - cx) * factor, cz + (z - cz) * factor

    return f


def arc() -> Deform:
    """目を上向きの弧 (笑顔の目) にする。"""

    def f(side, x, z):
        cx, cz = _center(side)
        rel = (x - cx) / spec.EYE_HALF_W
        thickness = (z - cz) / spec.EYE_HALF_H * h(0.008)
        return x, cz + h(0.03) - h(0.05) * rel * rel + thickness

    return f


def mouth_shape(width: float, height: float, bend: float) -> Deform:
    """口の横幅、開口、口角の上下 (bend > 0 で口角が上がる)。"""

    def f(_side, x, z):
        cz = spec.MOUTH_Z
        nx = x * width
        rel = nx / (spec.MOUTH_HALF_W * width)
        return nx, cz + (z - cz) * max(height, MOUTH_CLOSED) + bend * rel * rel

    return f


def brow_tilt(inner_dz: float, outer_dz: float) -> Deform:
    def f(side, x, z):
        inner, outer = face.brow_x_range(side or "L")
        t = min(1.0, max(0.0, (abs(x) - inner) / (outer - inner)))
        return x, z + inner_dz + (outer_dz - inner_dz) * t

    return f


def identity() -> Deform:
    return lambda _side, x, z: (x, z)


def _sided(deform: Deform, only: str) -> Deform:
    def f(side, x, z):
        if side == only:
            return deform(side, x, z)
        return x, z

    return f


def _for(bases: tuple[str, ...], deform: Deform) -> dict[str, Deform]:
    return dict.fromkeys(bases, deform)


def _key_table() -> dict[str, dict[str, Deform]]:
    table: dict[str, dict[str, Deform]] = {}
    table["Basis"] = {"mouth": mouth_shape(1.0, MOUTH_CLOSED, 0.0)}
    for name, (width, height) in spec.VISEMES.items():
        table[name] = {"mouth": mouth_shape(width, height, 0.0)}
    table["Blink"] = _for(ALL_EYE, squash(0.06))
    table["Blink_L"] = _for(ALL_EYE, _sided(squash(0.06), "L"))
    table["Blink_R"] = _for(ALL_EYE, _sided(squash(0.06), "R"))
    table["Wink"] = {
        **_for(ALL_EYE, _sided(squash(0.06), "L")),
        "mouth": mouth_shape(1.15, 0.12, h(0.02)),
    }
    table["Smile"] = {
        **_for(ALL_EYE, arc()),
        "mouth": mouth_shape(1.3, 0.15, h(0.03)),
    }
    table["Angry"] = {
        **_for(ALL_EYE, squash(0.85)),
        "brow": brow_tilt(-h(0.04), h(0.005)),
        "mouth": mouth_shape(0.9, 0.12, -h(0.02)),
    }
    table["Sad"] = {
        **_for(ALL_EYE, squash(0.9)),
        "brow": brow_tilt(h(0.005), -h(0.04)),
        "mouth": mouth_shape(1.1, 0.10, -h(0.03)),
    }
    table["Surprised"] = {
        **_for(("eye", "dot"), grow(1.12)),
        "pupil": grow(0.6),
        "mouth": mouth_shape(0.55, 0.6, 0.0),
    }
    table["DotEyes"] = {}
    for name in ("Basis", *spec.SHAPE_KEYS):
        table.setdefault(name, {})
    return table


KEY_TABLE = _key_table()


def is_hidden(key: str, base: str) -> bool:
    """key の状態で base 部品を表面の内側へ隠すか。"""
    if base == "dot":
        return key != "DotEyes"
    if base in ANIME_EYE:
        return key == "DotEyes"
    return False


def target_position(key: str, tag: str, design: Vec) -> Vec:
    """設計位置 design にある tag の頂点の、key における位置。"""
    base, side = face.split_tag(tag)
    deform = KEY_TABLE[key].get(base)
    x, z = design[0], design[2]
    if deform is not None:
        x, z = deform(side, x, z)
    p = face.on_surface(x, z, face.OFFSETS[base])
    if is_hidden(key, base):
        p = (p[0], p[1] + HIDE_DEPTH, p[2])
    return p


def positions(key: str, design: list[Vec], tags: list[str]) -> list[Vec]:
    return [target_position(key, tag, p) for p, tag in zip(design, tags, strict=True)]
