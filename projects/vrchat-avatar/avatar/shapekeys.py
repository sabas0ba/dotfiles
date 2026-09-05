"""VRChat が参照する shape key (viseme、まばたき) を Body mesh に追加する。

素体の顔には口の形状が無いため、各 viseme は口周辺の頂点を「開く・横に広げる・
すぼめる・前に出す」の 4 成分で変位させる近似である。Blender GUI で顔を作り込む
際は、同名の shape key を作り直せば Unity 側の設定を変えずに置き換えられる。
"""

from __future__ import annotations

import math
from dataclasses import dataclass

from .params import Proportions

# VRChat の Viseme Blend Shape の名前 (SDK が既定で探す順序)。
VISEME_NAMES = (
    "vrc.v_sil",
    "vrc.v_pp",
    "vrc.v_ff",
    "vrc.v_th",
    "vrc.v_dd",
    "vrc.v_kk",
    "vrc.v_ch",
    "vrc.v_ss",
    "vrc.v_nn",
    "vrc.v_rr",
    "vrc.v_aa",
    "vrc.v_e",
    "vrc.v_ih",
    "vrc.v_oh",
    "vrc.v_ou",
)

# VRChat SDK3 の Avatar Descriptor (Eyelids: Blendshapes) が既定で探す名前。
# LookingUp / LookingDown は瞼の形状が無いため変位を持たない placeholder である。
EYE_SHAPE_NAMES = (
    "Blink",
    "Blink_L",
    "Blink_R",
    "LookingUp",
    "LookingDown",
)


@dataclass(frozen=True)
class MouthShape:
    open: float = 0.0  # 下方向への開き (m)
    widen: float = 0.0  # 横方向への拡大率 (0 で変化なし)
    pucker: float = 0.0  # 中心へすぼめる率
    forward: float = 0.0  # 前方 (-Y) への突出 (m)


VISEME_SHAPES = {
    "vrc.v_sil": MouthShape(),
    "vrc.v_pp": MouthShape(open=0.0, forward=-0.002),
    "vrc.v_ff": MouthShape(open=0.002, forward=-0.003),
    "vrc.v_th": MouthShape(open=0.003),
    "vrc.v_dd": MouthShape(open=0.004),
    "vrc.v_kk": MouthShape(open=0.005),
    "vrc.v_ch": MouthShape(open=0.003, widen=0.10),
    "vrc.v_ss": MouthShape(open=0.002, widen=0.12),
    "vrc.v_nn": MouthShape(open=0.003),
    "vrc.v_rr": MouthShape(open=0.004, pucker=0.15),
    "vrc.v_aa": MouthShape(open=0.012),
    "vrc.v_e": MouthShape(open=0.006, widen=0.15),
    "vrc.v_ih": MouthShape(open=0.004, widen=0.10),
    "vrc.v_oh": MouthShape(open=0.007, pucker=0.30, forward=0.006),
    "vrc.v_ou": MouthShape(open=0.005, pucker=0.45, forward=0.008),
}

MOUTH_RADIUS = 0.045


def smoothstep(t: float) -> float:
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


def group_weight(obj, vertex, group_name: str) -> float:
    group = obj.vertex_groups.get(group_name)
    if group is None:
        return 0.0
    for g in vertex.groups:
        if g.group == group.index:
            return g.weight
    return 0.0


def mouth_influence(co, p: Proportions) -> float:
    """口の中心からの距離による影響度 [0, 1]。前面の頂点だけを対象にする。"""
    if co.y > -0.030:
        return 0.0
    dx = co.x
    dz = co.z - p.mouth_level
    distance = math.sqrt(dx * dx + (dz * 1.4) ** 2)
    return 1.0 - smoothstep(distance / MOUTH_RADIUS)


def add_shape_keys(obj, p: Proportions) -> None:
    mesh = obj.data
    if obj.data.shape_keys is None:
        obj.shape_key_add(name="Basis", from_mix=False)

    head_vertices = [
        v for v in mesh.vertices if group_weight(obj, v, "Head") > 0.5 and group_weight(obj, v, "LeftEye") == 0.0 and group_weight(obj, v, "RightEye") == 0.0
    ]
    mouth = [(v.index, mouth_influence(v.co, p)) for v in head_vertices]
    mouth = [(i, w) for i, w in mouth if w > 0.0]

    for name in VISEME_NAMES:
        shape = VISEME_SHAPES[name]
        key = obj.shape_key_add(name=name, from_mix=False)
        for index, w in mouth:
            co = mesh.vertices[index].co.copy()
            below = co.z < p.mouth_level
            if below:
                co.z -= shape.open * w
            co.x *= 1.0 + shape.widen * w - shape.pucker * w
            co.y -= shape.forward * w
            key.data[index].co = co

    # 瞼の形状が無いため、まばたきは眼球を上下方向に潰して閉眼を表す近似とする。
    eyes = {
        "Blink_L": [v for v in mesh.vertices if group_weight(obj, v, "LeftEye") > 0.5],
        "Blink_R": [v for v in mesh.vertices if group_weight(obj, v, "RightEye") > 0.5],
    }
    eyes["Blink"] = eyes["Blink_L"] + eyes["Blink_R"]
    for name in ("Blink", "Blink_L", "Blink_R"):
        key = obj.shape_key_add(name=name, from_mix=False)
        for v in eyes[name]:
            co = v.co.copy()
            co.z = p.eye_level + (co.z - p.eye_level) * 0.05
            key.data[v.index].co = co

    for name in ("LookingUp", "LookingDown"):
        obj.shape_key_add(name=name, from_mix=False)
