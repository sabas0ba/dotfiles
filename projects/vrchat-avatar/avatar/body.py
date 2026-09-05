"""素体 (胴体、頭部、四肢、手、足、眼球) の loft 定義。

各関数は左側または中央の部品を返し、右側は MeshBuilder.add(mirror_x=True) で作る。
bone weight は ring ごとに明示し、関節では隣接 bone を 0.5 ずつ混ぜる。ring に
weights を書かない箇所は前後の ring から線形補間される。
"""

from __future__ import annotations

import math

from .loft import (
    AXIS_Z_BASIS,
    FRONT_ANGLE,
    LoftResult,
    Ring,
    Vec3,
    add,
    basis_for_direction,
    build_loft,
    gaussian_bulge,
    scale,
)
from .mesh_builder import MeshBuilder
from .params import AvatarSpec, Proportions
from .rig import (
    FINGER_NAMES,
    FINGER_OFFSETS_Y,
    THUMB_DIRECTION,
    finger_joints,
    thumb_joints,
)


def torso(p: Proportions, segments: int) -> LoftResult:
    bust = gaussian_bulge(1.0, [FRONT_ANGLE - 0.42, FRONT_ANGLE + 0.42], 0.36)

    def bust_bulge(amplitude: float):
        return lambda angle: (0.0, bust(angle)[1] * amplitude)

    rings = [
        Ring((0, 0, p.crotch), 0.090, 0.075, weights={"Hips": 1.0}, material="Underwear"),
        Ring((0, 0, 0.830), 0.145, 0.105, material="Underwear"),
        Ring((0, 0.005, p.hip), p.hip_rx, p.hip_ry, weights={"Hips": 1.0}, material="Underwear"),
        Ring((0, 0.003, 0.935), 0.140, 0.102),
        Ring((0, 0, 0.965), 0.130, 0.098, weights={"Hips": 0.5, "Spine": 0.5}),
        Ring((0, 0, p.waist), p.waist_rx, p.waist_ry, weights={"Spine": 1.0}),
        Ring((0, 0, 1.085), 0.108, 0.085, weights={"Spine": 0.6, "Chest": 0.4}),
        Ring((0, 0, p.under_bust), p.under_bust_rx, p.under_bust_ry, weights={"Chest": 1.0}, material="Underwear"),
        Ring((0, 0, 1.175), 0.125, 0.092, bulge=bust_bulge(p.bust_bulge * 0.75), material="Underwear"),
        Ring((0, 0, p.bust_apex), 0.128, p.chest_ry, bulge=bust_bulge(p.bust_bulge), material="Underwear"),
        Ring((0, 0, 1.245), 0.128, p.chest_ry, bulge=bust_bulge(p.bust_bulge * 0.55), material="Underwear"),
        Ring((0, 0, 1.285), 0.128, 0.092, bulge=bust_bulge(p.bust_bulge * 0.15), material="Underwear"),
        Ring((0, 0, p.chest_top), 0.135, 0.085, weights={"Chest": 1.0}),
        Ring((0, 0, p.shoulder_z), 0.150, 0.075),
        Ring((0, 0, 1.395), 0.075, 0.060, weights={"Chest": 0.6, "Neck": 0.4}),
    ]
    return build_loft(rings, segments, "Skin", uv_tile=(0, 0))


def neck(p: Proportions, segments: int) -> LoftResult:
    rings = [
        Ring((0, 0, 1.370), p.neck_rx, p.neck_ry, weights={"Chest": 0.5, "Neck": 0.5}),
        Ring((0, 0, 1.400), p.neck_rx, p.neck_ry, weights={"Neck": 1.0}),
        Ring((0, -0.002, 1.430), p.neck_rx, p.neck_ry, weights={"Neck": 0.6, "Head": 0.4}),
        Ring((0, -0.004, 1.465), p.neck_rx + 0.004, p.neck_ry + 0.004, weights={"Head": 1.0}),
    ]
    return build_loft(rings, segments, "Skin", uv_tile=(1, 0))


def head(p: Proportions, segments: int) -> LoftResult:
    head_w = {"Head": 1.0}
    rings = [
        Ring((0, -0.034, p.head_bottom), 0.050, 0.045, ry_front=0.032, weights=head_w),
        Ring((0, -0.030, 1.460), 0.076, 0.066, ry_front=0.046),
        Ring((0, -0.022, 1.480), 0.100, 0.082, ry_front=0.058),
        Ring((0, -0.012, 1.505), 0.125, 0.095, ry_front=0.068),
        Ring((0, -0.003, 1.535), 0.152, 0.103, ry_front=0.074),
        Ring((0, 0.000, 1.555), 0.160, 0.105, ry_front=0.075),
        Ring((0, 0.000, 1.580), p.head_width, 0.108, ry_front=0.075),
        Ring((0, 0.005, 1.615), 0.160, 0.105, ry_front=0.070),
        Ring((0, 0.010, 1.650), 0.130, 0.085, ry_front=0.060),
        Ring((0, 0.010, 1.672), 0.075, 0.050, ry_front=0.040),
        Ring((0, 0.010, p.head_top), 0.020, 0.015, weights=head_w),
    ]
    return build_loft(rings, segments, "Skin", uv_tile=(2, 0))


def eye(p: Proportions, segments: int, side_sign: float = 1.0) -> LoftResult:
    """眼球。前方 (-Y) を向く扁平な楕円体で、前面の帯を Iris、中心を EyeLine (瞳孔) にする。

    アニメ調の大きな目を、頭部から大きく突出させずに表すため奥行を eye_depth_scale で縮める。
    """
    center: Vec3 = (side_sign * p.eye_spacing, p.eye_center_y, p.eye_level)
    u, v = basis_for_direction((0.0, -1.0, 0.0))
    ring_count = 8
    rings = []
    for j in range(1, ring_count):
        phi = math.pi * j / ring_count
        y = center[1] + p.eye_radius * p.eye_depth_scale * math.cos(phi)
        r = p.eye_radius * math.sin(phi)
        # 前面ほど phi が大きい。帯の material は次の ring との間に適用される。
        front_angle = math.pi - (math.pi * (j + 0.5) / ring_count)
        material = "Sclera"
        if front_angle < math.radians(22):
            material = "EyeLine"
        elif front_angle < math.radians(52):
            material = "Iris"
        rings.append(Ring((center[0], y, center[2]), r, r, u=u, v=v, weights={"LeftEye": 1.0}, material=material))
    return build_loft(rings, segments, "Sclera", uv_tile=(3, 0))


def arm(p: Proportions, segments: int) -> LoftResult:
    u, v = basis_for_direction((1.0, 0.0, 0.0))
    z = p.shoulder_z

    def ring(x: float, r_y: float, r_z: float, weights=None) -> Ring:
        return Ring((x, 0.0, z), r_y, r_z, u=u, v=v, weights=weights)

    rings = [
        ring(0.150, 0.050, 0.050, {"Chest": 0.4, "LeftUpperArm": 0.6}),
        ring(0.200, 0.047, 0.047, {"LeftUpperArm": 1.0}),
        ring(0.300, p.upper_arm_r, p.upper_arm_r + 0.002),
        ring(p.elbow_x - 0.03, 0.035, 0.036, {"LeftUpperArm": 1.0}),
        ring(p.elbow_x, p.elbow_r, p.elbow_r, {"LeftUpperArm": 0.5, "LeftLowerArm": 0.5}),
        ring(p.elbow_x + 0.03, 0.035, 0.035, {"LeftLowerArm": 1.0}),
        ring(0.560, p.forearm_r, p.forearm_r - 0.002),
        ring(0.640, 0.030, 0.026),
        ring(p.wrist_x, p.wrist_rx, p.wrist_ry, {"LeftLowerArm": 1.0}),
    ]
    return build_loft(rings, segments, "Skin", uv_tile=(0, 1))


def palm(p: Proportions, segments: int) -> LoftResult:
    u, v = basis_for_direction((1.0, 0.0, 0.0))
    z = p.shoulder_z
    rings = [
        Ring((p.wrist_x - 0.010, 0, z), p.wrist_rx, p.wrist_ry, u=u, v=v, weights={"LeftLowerArm": 0.5, "LeftHand": 0.5}),
        Ring((p.wrist_x + 0.035, 0, z), 0.036, p.palm_thickness + 0.002, u=u, v=v, weights={"LeftHand": 1.0}),
        Ring((p.knuckle_x, 0, z), p.palm_half_width, p.palm_thickness, u=u, v=v, weights={"LeftHand": 1.0}),
    ]
    return build_loft(rings, segments, "Skin", uv_tile=(1, 1))


def finger(p: Proportions, index: int, segments: int) -> LoftResult:
    u, v = basis_for_direction((1.0, 0.0, 0.0))
    z = p.shoulder_z
    y = FINGER_OFFSETS_Y[index]
    name = FINGER_NAMES[index]
    x0, x1, x2, tip = finger_joints(index, p)
    r0 = p.finger_r + 0.0008
    r1 = p.finger_r
    r2 = p.finger_r - 0.0012
    prox, inter, dist = (f"Left{name}Proximal", f"Left{name}Intermediate", f"Left{name}Distal")

    def ring(x: float, r: float, weights=None) -> Ring:
        return Ring((x, y, z), r, r * 0.9, u=u, v=v, weights=weights)

    rings = [
        ring(x0 - 0.012, r0, {"LeftHand": 1.0}),
        ring(x0, r0, {"LeftHand": 0.5, prox: 0.5}),
        ring((x0 + x1) / 2, r1, {prox: 1.0}),
        ring(x1, r1, {prox: 0.5, inter: 0.5}),
        ring((x1 + x2) / 2, r1, {inter: 1.0}),
        ring(x2, r2 + 0.0005, {inter: 0.5, dist: 0.5}),
        ring((x2 + tip) / 2, r2, {dist: 1.0}),
        ring(tip - 0.003, r2 * 0.7, {dist: 1.0}),
    ]
    return build_loft(rings, segments, "Skin", uv_tile=(2, 1))


def thumb(p: Proportions, segments: int) -> LoftResult:
    direction = THUMB_DIRECTION
    u, v = basis_for_direction(direction)
    joints = thumb_joints()
    prox, inter, dist = ("LeftThumbProximal", "LeftThumbIntermediate", "LeftThumbDistal")

    def along(point: Vec3, offset: float) -> Vec3:
        return add(point, scale(direction, offset))

    def mid(a: Vec3, b: Vec3) -> Vec3:
        return ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2)

    r = p.finger_r + 0.0015
    rings = [
        Ring(along(joints[0], -0.012), r + 0.002, r, u=u, v=v, weights={"LeftHand": 1.0}),
        Ring(joints[0], r + 0.001, r, u=u, v=v, weights={"LeftHand": 0.5, prox: 0.5}),
        Ring(mid(joints[0], joints[1]), r, r * 0.9, u=u, v=v, weights={prox: 1.0}),
        Ring(joints[1], r, r * 0.9, u=u, v=v, weights={prox: 0.5, inter: 0.5}),
        Ring(mid(joints[1], joints[2]), r * 0.95, r * 0.85, u=u, v=v, weights={inter: 1.0}),
        Ring(joints[2], r * 0.9, r * 0.8, u=u, v=v, weights={inter: 0.5, dist: 0.5}),
        Ring(along(joints[3], -0.003), r * 0.6, r * 0.55, u=u, v=v, weights={dist: 1.0}),
    ]
    return build_loft(rings, segments, "Skin", uv_tile=(3, 1))


def leg(p: Proportions, segments: int) -> LoftResult:
    x = p.leg_x
    upper, lower = "LeftUpperLeg", "LeftLowerLeg"
    rings = [
        Ring((x, 0, p.ankle_z), p.ankle_r, p.ankle_r + 0.004, weights={lower: 0.5, "LeftFoot": 0.5}),
        Ring((x, 0, 0.150), 0.040, 0.045, weights={lower: 1.0}),
        Ring((x, 0.008, p.calf_z), p.calf_r, p.calf_r + 0.008, weights={lower: 1.0}),
        Ring((x, 0.002, p.knee_z - 0.04), 0.054, 0.058, weights={lower: 1.0}),
        Ring((x, 0, p.knee_z), p.knee_r, p.knee_r + 0.006, weights={upper: 0.5, lower: 0.5}),
        Ring((x, 0, p.knee_z + 0.04), 0.058, 0.064, weights={upper: 1.0}),
        Ring((x, 0, 0.560), 0.066, 0.074),
        Ring((x, 0, 0.700), 0.076, 0.086),
        Ring((x + 0.005, 0, 0.800), p.thigh_r + 0.002, 0.092, weights={upper: 1.0}),
        Ring((x + 0.005, 0, 0.860), p.thigh_r, 0.095, weights={upper: 0.7, "Hips": 0.3}),
    ]
    return build_loft(rings, segments, "Skin", uv_tile=(0, 2))


def foot(p: Proportions, segments: int) -> LoftResult:
    x = p.leg_x
    u, v = basis_for_direction((0.0, -1.0, 0.0))
    toe_y = -(p.foot_length - p.foot_heel)
    rings = [
        Ring((x, p.foot_heel, 0.034), 0.034, 0.028, u=u, v=v, weights={"LeftFoot": 1.0}),
        Ring((x, 0.010, 0.037), p.foot_width - 0.002, 0.036, u=u, v=v, weights={"LeftFoot": 1.0}),
        Ring((x, -0.050, 0.030), p.foot_width, 0.030, u=u, v=v),
        Ring((x, -0.110, 0.020), p.foot_width + 0.002, 0.020, u=u, v=v, weights={"LeftFoot": 0.5, "LeftToes": 0.5}),
        Ring((x, -0.160, 0.013), p.foot_width - 0.002, 0.013, u=u, v=v, weights={"LeftToes": 1.0}),
        Ring((x, toe_y, 0.010), 0.030, 0.009, u=u, v=v, weights={"LeftToes": 1.0}),
    ]
    return build_loft(rings, segments, "Skin", uv_tile=(1, 2))


def build_body(spec: AvatarSpec) -> MeshBuilder:
    p = spec.proportions
    r = spec.resolution
    builder = MeshBuilder()

    builder.add(torso(p, r.torso))
    builder.add(neck(p, r.limb))
    builder.add(head(p, r.head))

    for mirror in (False, True):
        builder.add(eye(p, r.eye), mirror_x=mirror)
        builder.add(arm(p, r.limb), mirror_x=mirror)
        builder.add(palm(p, r.limb), mirror_x=mirror)
        for index in range(len(FINGER_NAMES)):
            builder.add(finger(p, index, r.finger), mirror_x=mirror)
        builder.add(thumb(p, r.finger), mirror_x=mirror)
        builder.add(leg(p, r.limb), mirror_x=mirror)
        builder.add(foot(p, r.limb), mirror_x=mirror)

    return builder


__all__ = ["build_body", "AXIS_Z_BASIS"]
