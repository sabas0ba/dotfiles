"""モデル生成の手順全体。bpy に依存する。

1. 材質と texture を用意する
2. 素体、顔、髪、衣装の各 object を pure Python の mesh から生成する
3. 素体と衣装に subdivision、髪の殻に厚みを与える
4. 最終形状の頂点へ解析的に bone weight を割り当てる
5. 顔に shape key を登録する
6. armature を作り、各 object を bind する
"""

from __future__ import annotations

import os

import bpy

from avatar import bl_materials, bl_mesh, bl_rig, body, clothes, face, hair, shapekeys, spec
from avatar.spec import h

OBJECT_BODY = "Body"
OBJECT_FACE = "Face"
OBJECT_HAIR = "Hair"
OBJECT_CLOTHES = "Clothes"

SUBDIVISION_LEVELS = 1
HAIR_SHELL_THICKNESS = h(0.012)


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0


def _finalize(obj: bpy.types.Object, rules: dict[str, str]) -> list[str]:
    tags = bl_mesh.read_tags(obj)
    bl_mesh.assign_bone_weights(obj, tags, rules)
    bl_mesh.remove_tag_groups(obj)
    return tags


def build_body(materials) -> bpy.types.Object:
    obj = bl_mesh.create_object(OBJECT_BODY, body.build(), materials)
    bl_mesh.apply_subdivision(obj, SUBDIVISION_LEVELS)
    _finalize(obj, body.WEIGHT_RULES)
    bl_mesh.set_flat_uv(obj)
    return obj


def build_clothes(materials) -> bpy.types.Object:
    obj = bl_mesh.create_object(OBJECT_CLOTHES, clothes.build(), materials)
    bl_mesh.apply_subdivision(obj, SUBDIVISION_LEVELS)
    _finalize(obj, clothes.WEIGHT_RULES)
    bl_mesh.set_flat_uv(obj)
    return obj


def build_hair(materials) -> bpy.types.Object:
    obj = bl_mesh.create_object(OBJECT_HAIR, hair.build(), materials)
    # 殻の下端が開いているため厚みを与え、下から見上げても裏面が抜けないようにする。
    bl_mesh.apply_solidify(obj, HAIR_SHELL_THICKNESS)
    _finalize(obj, hair.WEIGHT_RULES)
    bl_mesh.set_height_uv(obj, spec.HAIR_GRADIENT_Z)
    return obj


def build_face(materials) -> bpy.types.Object:
    mesh = face.build()
    obj = bl_mesh.create_object(OBJECT_FACE, mesh, materials)
    tags = _finalize(obj, face.WEIGHT_RULES)
    bl_mesh.set_flat_uv(obj)
    targets = {
        key: shapekeys.positions(key, mesh.verts, tags) for key in ("Basis", *spec.SHAPE_KEYS)
    }
    bl_mesh.add_shape_keys(obj, targets)
    return obj


def build_all(texture_dir: str) -> bpy.types.Object:
    reset_scene()
    materials = bl_materials.create_materials(texture_dir)
    objects = [
        build_body(materials),
        build_face(materials),
        build_hair(materials),
        build_clothes(materials),
    ]
    armature = bl_rig.create_armature()
    for obj in objects:
        bl_rig.bind(obj, armature)
    bpy.context.view_layer.objects.active = armature
    return armature


def save_blend(path: str) -> None:
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(path), relative_remap=True)
