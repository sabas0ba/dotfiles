"""Unity Humanoid 互換の armature。

bone 名は Unity の HumanBodyBones と同一にし、VRChat SDK の自動 mapping に依存せず
対応付けが一意になるようにする。位置は params.Proportions から導出し、mesh 側の
bone weight (body.py) と同じ数値を参照する。
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

from .loft import Vec3, add, scale
from .params import Proportions

FINGER_NAMES = ("Index", "Middle", "Ring", "Little")
FINGER_OFFSETS_Y = (-0.026, -0.009, 0.009, 0.026)
FINGER_TIP_X = (0.865, 0.875, 0.868, 0.845)
FINGER_SEGMENT_RATIO = (0.42, 0.30, 0.28)

THUMB_BASE: Vec3 = (0.740, -0.032, 1.355)
THUMB_DIRECTION: Vec3 = (0.55, -0.835, 0.0)
THUMB_SEGMENT_LENGTHS = (0.025, 0.022, 0.020)

# Unity Humanoid が必須とする bone。validate_fbx.py が同じ一覧で検査する。
REQUIRED_BONES = (
    "Hips",
    "Spine",
    "Chest",
    "Neck",
    "Head",
    "LeftUpperArm",
    "LeftLowerArm",
    "LeftHand",
    "RightUpperArm",
    "RightLowerArm",
    "RightHand",
    "LeftUpperLeg",
    "LeftLowerLeg",
    "LeftFoot",
    "RightUpperLeg",
    "RightLowerLeg",
    "RightFoot",
)

# 視線追従、指、つま先など VRChat で推奨される任意 bone。
RECOMMENDED_BONES = (
    "LeftEye",
    "RightEye",
    "LeftShoulder",
    "RightShoulder",
    "LeftToes",
    "RightToes",
) + tuple(
    f"{side}{finger}{segment}"
    for side in ("Left", "Right")
    for finger in ("Thumb",) + FINGER_NAMES
    for segment in ("Proximal", "Intermediate", "Distal")
)


@dataclass(frozen=True)
class Bone:
    name: str
    head: Vec3
    tail: Vec3
    parent: Optional[str]


def finger_joints(finger_index: int, p: Proportions) -> list[float]:
    """指の関節の x 座標 [knuckle, joint1, joint2, tip] を返す。"""
    x0 = p.knuckle_x
    length = FINGER_TIP_X[finger_index] - x0
    x1 = x0 + length * FINGER_SEGMENT_RATIO[0]
    x2 = x1 + length * FINGER_SEGMENT_RATIO[1]
    return [x0, x1, x2, FINGER_TIP_X[finger_index]]


def thumb_joints() -> list[Vec3]:
    points = [THUMB_BASE]
    for length in THUMB_SEGMENT_LENGTHS:
        points.append(add(points[-1], scale(THUMB_DIRECTION, length)))
    return points


def left_side_bones(p: Proportions) -> list[Bone]:
    z = p.shoulder_z
    bones = [
        Bone("LeftShoulder", (0.03, 0.0, z), (p.shoulder_x, 0.0, z), "Chest"),
        Bone("LeftUpperArm", (p.shoulder_x, 0.0, z), (p.elbow_x, 0.0, z), "LeftShoulder"),
        Bone("LeftLowerArm", (p.elbow_x, 0.0, z), (p.wrist_x, 0.0, z), "LeftUpperArm"),
        Bone("LeftHand", (p.wrist_x, 0.0, z), (p.knuckle_x, 0.0, z), "LeftLowerArm"),
        Bone("LeftEye", (p.eye_spacing, p.eye_center_y, p.eye_level), (p.eye_spacing, p.eye_center_y - 0.03, p.eye_level), "Head"),
        Bone("LeftUpperLeg", (p.leg_x, 0.0, p.hip - 0.02), (p.leg_x, 0.0, p.knee_z), "Hips"),
        Bone("LeftLowerLeg", (p.leg_x, 0.0, p.knee_z), (p.leg_x, 0.0, p.ankle_z), "LeftUpperLeg"),
        Bone("LeftFoot", (p.leg_x, 0.0, p.ankle_z), (p.leg_x, -0.12, 0.02), "LeftLowerLeg"),
        Bone("LeftToes", (p.leg_x, -0.12, 0.02), (p.leg_x, -0.18, 0.015), "LeftFoot"),
    ]
    for index, name in enumerate(FINGER_NAMES):
        joints = finger_joints(index, p)
        y = FINGER_OFFSETS_Y[index]
        parent = "LeftHand"
        for segment, (x_from, x_to) in zip(("Proximal", "Intermediate", "Distal"), zip(joints, joints[1:])):
            bone_name = f"Left{name}{segment}"
            bones.append(Bone(bone_name, (x_from, y, z), (x_to, y, z), parent))
            parent = bone_name
    joints3 = thumb_joints()
    parent = "LeftHand"
    for segment, (p_from, p_to) in zip(("Proximal", "Intermediate", "Distal"), zip(joints3, joints3[1:])):
        bone_name = f"LeftThumb{segment}"
        bones.append(Bone(bone_name, p_from, p_to, parent))
        parent = bone_name
    return bones


def mirror_bone(bone: Bone) -> Bone:
    def flip(v: Vec3) -> Vec3:
        return (-v[0], v[1], v[2])

    def rename(name: Optional[str]) -> Optional[str]:
        if name is None:
            return None
        return "Right" + name[len("Left") :] if name.startswith("Left") else name

    return Bone(rename(bone.name), flip(bone.head), flip(bone.tail), rename(bone.parent))


def all_bones(p: Proportions) -> list[Bone]:
    center = [
        Bone("Hips", (0.0, 0.0, p.hip - 0.02), (0.0, 0.0, 0.98), None),
        Bone("Spine", (0.0, 0.0, 0.98), (0.0, 0.0, 1.12), "Hips"),
        Bone("Chest", (0.0, 0.0, 1.12), (0.0, 0.0, p.neck_base), "Spine"),
        Bone("Neck", (0.0, 0.0, p.neck_base), (0.0, -0.005, p.head_bottom + 0.01), "Chest"),
        Bone("Head", (0.0, -0.005, p.head_bottom + 0.01), (0.0, -0.005, p.head_top), "Neck"),
    ]
    left = left_side_bones(p)
    right = [mirror_bone(b) for b in left]
    return center + left + right


def create_armature(p: Proportions, name: str = "Armature"):
    """armature object を作成して scene に link し、返す。"""
    import bpy

    armature = bpy.data.armatures.new(name)
    obj = bpy.data.objects.new(name, armature)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    bpy.ops.object.mode_set(mode="EDIT")
    edit_bones = {}
    for bone in all_bones(p):
        eb = armature.edit_bones.new(bone.name)
        eb.head = bone.head
        eb.tail = bone.tail
        eb.use_connect = False
        if bone.parent is not None:
            eb.parent = edit_bones[bone.parent]
        edit_bones[bone.name] = eb
    bpy.ops.object.mode_set(mode="OBJECT")
    obj.select_set(False)
    return obj


def bind(mesh_obj, armature_obj) -> None:
    """mesh を armature の子にし、Armature modifier で変形させる。weight は既に vertex group にある。"""
    mesh_obj.parent = armature_obj
    modifier = mesh_obj.modifiers.new("Armature", "ARMATURE")
    modifier.object = armature_obj
    modifier.use_vertex_groups = True
