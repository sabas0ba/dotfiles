"""Unity 向け FBX の書き出し。bpy に依存する。

.blend では部位ごとに object を分けて編集しやすくし、FBX では skinned mesh の数を減らす
ために Face 以外を 1 つに結合した複製を書き出す。shape key を持つ Face は結合しない。
"""

from __future__ import annotations

import os

import bpy

from avatar.build import OBJECT_BODY, OBJECT_CLOTHES, OBJECT_FACE, OBJECT_HAIR

MERGED_NAME = "Body"


def _duplicate(obj: bpy.types.Object) -> bpy.types.Object:
    copy = obj.copy()
    copy.data = obj.data.copy()
    bpy.context.scene.collection.objects.link(copy)
    return copy


def _join(objects: list[bpy.types.Object], name: str) -> bpy.types.Object:
    active = objects[0]
    bpy.context.view_layer.objects.active = active
    with bpy.context.temp_override(
        active_object=active, selected_objects=objects, selected_editable_objects=objects
    ):
        bpy.ops.object.join()
    active.name = name
    active.data.name = name
    return active


def export_fbx(path: str, merge: bool = True) -> None:
    """FBX を書き出す。merge が真なら Body, Hair, Clothes を結合した複製を使う。"""
    scene = bpy.context.scene
    armature = bpy.data.objects["Armature"]
    face = bpy.data.objects[OBJECT_FACE]
    originals = [bpy.data.objects[n] for n in (OBJECT_BODY, OBJECT_HAIR, OBJECT_CLOTHES)]

    temporary: list[bpy.types.Object] = []
    if merge:
        for obj in originals:
            obj.hide_set(False)
        copies = [_duplicate(obj) for obj in originals]
        for obj in originals:
            obj.name = obj.name + ".src"
        merged = _join(copies, MERGED_NAME)
        temporary.append(merged)
        exported = [armature, merged, face]
    else:
        exported = [armature, face, *originals]

    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with bpy.context.temp_override(selected_objects=exported, scene=scene):
        bpy.ops.export_scene.fbx(
            filepath=os.path.abspath(path),
            use_selection=True,
            apply_unit_scale=True,
            apply_scale_options="FBX_SCALE_ALL",
            axis_forward="-Z",
            axis_up="Y",
            object_types={"ARMATURE", "MESH"},
            use_mesh_modifiers=False,
            mesh_smooth_type="FACE",
            use_tspace=False,
            add_leaf_bones=False,
            primary_bone_axis="Y",
            secondary_bone_axis="X",
            use_armature_deform_only=True,
            bake_anim=False,
            path_mode="COPY",
            embed_textures=False,
        )

    for obj in temporary:
        data = obj.data
        bpy.data.objects.remove(obj)
        bpy.data.meshes.remove(data)
    for obj in originals:
        obj.name = obj.name.removesuffix(".src")
