"""モデルの寸法、bone 配置、配色の単一情報源。

すべて meter 単位。頭身の基準として頭部の高さ HEAD_H を定義し、各寸法は設定資料
(約 2.4〜2.5 頭身) の比率をこの値に掛けて求める。Blender の座標系で正面は -Y、上は +Z、
キャラクターの左手側は +X である。
"""

from __future__ import annotations

import math
from dataclasses import dataclass

# 頭部の高さ (頭頂から顎まで)。全高は約 2.45 倍 (約 0.98 m) になる。
HEAD_H = 0.40


def h(value: float) -> float:
    """頭身単位の値を meter に変換する。"""
    return value * HEAD_H


# --- 頭部 ------------------------------------------------------------------
# 頭部は横にやや広い楕円体とし、中心より下で顎に向かって絞る。
HEAD_CENTER = (0.0, 0.0, h(1.93))
HEAD_RADII = (h(0.52), h(0.50), h(0.50))
JAW_TAPER = 0.22  # 顎での絞り率 (中心から下端で 1 - JAW_TAPER 倍)

# 顔パーツの配置。目の中心は頭部の中心よりやや下に置き、頭を大きく見せる。
EYE_CENTER_X = h(0.19)
EYE_CENTER_Z = h(1.81)
EYE_HALF_W = h(0.095)
EYE_HALF_H = h(0.115)
BROW_Z = h(1.99)
MOUTH_Z = h(1.635)
MOUTH_HALF_W = h(0.03)
MOUTH_FULL_H = h(0.055)
EARRING_POS = (h(0.47), h(0.02), h(1.53))

# 視点 (VRChat の View Position) は目の高さ、やや前方に置く。
VIEW_POSITION = (0.0, -h(0.42), EYE_CENTER_Z)


def jaw_scale(z: float) -> float:
    """高さ z における頭部の水平方向の縮小率。中心より上は 1.0 とする。"""
    cz = HEAD_CENTER[2]
    rz = HEAD_RADII[2]
    if z >= cz:
        return 1.0
    t = min(1.0, (cz - z) / rz)
    return 1.0 - JAW_TAPER * t**1.5


def head_surface_y(x: float, z: float) -> float | None:
    """頭部前面の表面の y 座標を返す。点 (x, z) が頭部の外なら None。"""
    cx, _cy, cz = HEAD_CENTER
    rx, ry, rz = HEAD_RADII
    s = jaw_scale(z)
    u = ((x - cx) / (rx * s)) ** 2 + ((z - cz) / rz) ** 2
    if u >= 1.0:
        return None
    return HEAD_CENTER[1] - ry * s * math.sqrt(1.0 - u)


def head_direction(azimuth: float, polar: float) -> tuple[float, float, float]:
    """頭部中心から見た方向ベクトル。

    azimuth は正面 (-Y) から +X へ向かう角、polar は頭頂からの角。
    """
    sp = math.sin(polar)
    return (sp * math.sin(azimuth), -sp * math.cos(azimuth), math.cos(polar))


def head_point(azimuth: float, polar: float, radius_factor: float) -> tuple[float, float, float]:
    """頭部楕円体の表面を radius_factor 倍した位置。髪の配置に使う (顎の絞りは無視する)。"""
    d = head_direction(azimuth, polar)
    return (
        HEAD_CENTER[0] + d[0] * HEAD_RADII[0] * radius_factor,
        HEAD_CENTER[1] + d[1] * HEAD_RADII[1] * radius_factor,
        HEAD_CENTER[2] + d[2] * HEAD_RADII[2] * radius_factor,
    )


# --- 関節 ------------------------------------------------------------------
# 資料 1 の項目 5 (関節位置) を頭身比で写した値。
HIP_Z = h(0.86)
KNEE_Z = h(0.45)
ANKLE_Z = h(0.12)
LEG_X = h(0.10)
SHOULDER = (h(0.19), 0.0, h(1.30))
# 腕は体側からわずかに開いた A ポーズ。垂直から ARM_ANGLE だけ外へ傾ける。
ARM_ANGLE = math.radians(20.0)
ARM_DIR = (math.sin(ARM_ANGLE), 0.0, -math.cos(ARM_ANGLE))
UPPER_ARM_LEN = h(0.24)
LOWER_ARM_LEN = h(0.22)
HAND_LEN = h(0.14)


def along_arm(distance: float, side: float = 1.0) -> tuple[float, float, float]:
    """肩関節から腕の軸に沿って distance だけ進んだ点。side は +1 (左) / -1 (右)。"""
    return (
        side * (SHOULDER[0] + ARM_DIR[0] * distance),
        SHOULDER[1] + ARM_DIR[1] * distance,
        SHOULDER[2] + ARM_DIR[2] * distance,
    )


ELBOW_DIST = UPPER_ARM_LEN
WRIST_DIST = UPPER_ARM_LEN + LOWER_ARM_LEN
HAND_END_DIST = WRIST_DIST + HAND_LEN


# --- Armature --------------------------------------------------------------
@dataclass(frozen=True)
class BoneSpec:
    name: str
    head: tuple[float, float, float]
    tail: tuple[float, float, float]
    parent: str | None


def _mirror(p: tuple[float, float, float]) -> tuple[float, float, float]:
    return (-p[0], p[1], p[2])


def _side_bones(side: str) -> list[BoneSpec]:
    sign = 1.0 if side == "L" else -1.0
    sfx = f".{side}"
    shoulder_root = (sign * h(0.06), 0.0, h(1.33))
    shoulder = (sign * SHOULDER[0], SHOULDER[1], SHOULDER[2])
    hip = (sign * LEG_X, 0.0, HIP_Z)
    knee = (sign * LEG_X, 0.0, KNEE_Z)
    ankle = (sign * LEG_X, 0.0, ANKLE_Z)
    toe_base = (sign * LEG_X, h(0.09), h(0.02))
    toe_end = (sign * LEG_X, h(0.17), h(0.02))
    eye = (sign * EYE_CENTER_X, HEAD_CENTER[1] - h(0.30), EYE_CENTER_Z)
    return [
        BoneSpec("Shoulder" + sfx, shoulder_root, shoulder, "Chest"),
        BoneSpec("UpperArm" + sfx, shoulder, along_arm(ELBOW_DIST, sign), "Shoulder" + sfx),
        BoneSpec(
            "LowerArm" + sfx,
            along_arm(ELBOW_DIST, sign),
            along_arm(WRIST_DIST, sign),
            "UpperArm" + sfx,
        ),
        BoneSpec(
            "Hand" + sfx,
            along_arm(WRIST_DIST, sign),
            along_arm(HAND_END_DIST, sign),
            "LowerArm" + sfx,
        ),
        BoneSpec("UpperLeg" + sfx, hip, knee, "Hips"),
        BoneSpec("LowerLeg" + sfx, knee, ankle, "UpperLeg" + sfx),
        BoneSpec("Foot" + sfx, ankle, toe_base, "LowerLeg" + sfx),
        BoneSpec("Toes" + sfx, toe_base, toe_end, "Foot" + sfx),
        BoneSpec("Eye" + sfx, eye, (eye[0], eye[1] - h(0.05), eye[2]), "Head"),
    ]


HEAD_TOP = (0.0, 0.0, HEAD_CENTER[2] + HEAD_RADII[2])

BONES: list[BoneSpec] = [
    BoneSpec("Hips", (0.0, 0.0, h(0.88)), (0.0, 0.0, h(1.02)), None),
    BoneSpec("Spine", (0.0, 0.0, h(1.02)), (0.0, 0.0, h(1.16)), "Hips"),
    BoneSpec("Chest", (0.0, 0.0, h(1.16)), (0.0, 0.0, h(1.36)), "Spine"),
    BoneSpec("Neck", (0.0, 0.0, h(1.36)), (0.0, 0.0, h(1.46)), "Chest"),
    BoneSpec("Head", (0.0, 0.0, h(1.46)), HEAD_TOP, "Neck"),
    *_side_bones("L"),
    *_side_bones("R"),
]

BONE_BY_NAME = {b.name: b for b in BONES}

# weight 計算に使う bone chain。各 chain は根元から先端へ並べた bone 名の列。
CHAINS: dict[str, list[str]] = {
    "torso": ["Hips", "Spine", "Chest", "Neck", "Head"],
    "arm.L": ["Shoulder.L", "UpperArm.L", "LowerArm.L", "Hand.L"],
    "arm.R": ["Shoulder.R", "UpperArm.R", "LowerArm.R", "Hand.R"],
    "leg.L": ["UpperLeg.L", "LowerLeg.L", "Foot.L", "Toes.L"],
    "leg.R": ["UpperLeg.R", "LowerLeg.R", "Foot.R", "Toes.R"],
}

# 関節での weight の混合幅 (meter)。
JOINT_BLEND = h(0.05)


# --- 配色 ------------------------------------------------------------------
# 資料 2 の項目 7 のカラーパレット (sRGB)。色味は目安であり Unity 側で調整する。
PALETTE: dict[str, str] = {
    "skin": "#FBEFEA",
    "hair_base": "#F5EAEC",
    "hair_pink": "#EDCBD6",
    "hair_lavender": "#C9B6E8",
    "hair_blue": "#B5C3F2",
    "eye": "#A64460",
    "eye_light": "#D97C93",
    "eye_dark": "#5E2436",
    "brow": "#D9AEBB",
    "mouth": "#B0525F",
    "cloth": "#2A2A2F",
    "boots": "#1E1E22",
    "earring": "#9A6BD8",
    "white": "#FFFFFF",
}

# 材質名と palette の対応。
MATERIALS: dict[str, str] = {
    "Skin": "skin",
    "Hair": "hair_base",
    "Eye": "eye",
    "EyeLight": "eye_light",
    "EyeDark": "eye_dark",
    "Brow": "brow",
    "Mouth": "mouth",
    "Cloth": "cloth",
    "Boots": "boots",
    "Earring": "earring",
    "Highlight": "white",
}

# 髪の gradient (UV の V 方向)。0 が毛先、1 が頭頂側。
HAIR_GRADIENT_STOPS: list[tuple[float, str]] = [
    (0.00, "hair_blue"),
    (0.18, "hair_lavender"),
    (0.42, "hair_pink"),
    (0.70, "hair_base"),
    (1.00, "hair_base"),
]
# この範囲の高さを V = 0..1 に写す。下限は側面の毛先、上限は前髪の毛先のやや上に置く。
HAIR_GRADIENT_Z = (h(1.50), h(1.80))


# --- VRChat の shape key ---------------------------------------------------
# (横方向の倍率, 開口の倍率)。開口 1.0 で MOUTH_FULL_H の高さになる。
VISEMES: dict[str, tuple[float, float]] = {
    "vrc.v_sil": (1.00, 0.00),
    "vrc.v_pp": (0.80, 0.10),
    "vrc.v_ff": (1.00, 0.25),
    "vrc.v_th": (1.00, 0.35),
    "vrc.v_dd": (1.00, 0.40),
    "vrc.v_kk": (0.90, 0.45),
    "vrc.v_ch": (0.90, 0.50),
    "vrc.v_ss": (1.10, 0.30),
    "vrc.v_nn": (0.90, 0.35),
    "vrc.v_rr": (0.90, 0.45),
    "vrc.v_aa": (1.10, 1.00),
    "vrc.v_e": (1.25, 0.55),
    "vrc.v_ih": (1.10, 0.40),
    "vrc.v_oh": (0.80, 0.85),
    "vrc.v_ou": (0.60, 0.70),
}

EXPRESSIONS: list[str] = [
    "Blink",
    "Blink_L",
    "Blink_R",
    "Wink",
    "Smile",
    "Angry",
    "Sad",
    "Surprised",
    "DotEyes",
]

SHAPE_KEYS: list[str] = [*VISEMES.keys(), *EXPRESSIONS]

# 出力の三角面数の上限 (VRChat PC の Excellent 帯)。
MAX_TRIANGLES = 32000
