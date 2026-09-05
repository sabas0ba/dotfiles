"""Unity Humanoid 互換の armature。bpy に依存する。"""

from __future__ import annotations

import bpy

from avatar import spec

ARMATURE_NAME = "Armature"


def create_armature() -> bpy.types.Object:
    data = bpy.data.armatures.new(ARMATURE_NAME)
    obj = bpy.data.objects.new(ARMATURE_NAME, data)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj

    bpy.ops.object.mode_set(mode="EDIT")
    edit_bones = data.edit_bones
    for bone in spec.BONES:
        eb = edit_bones.new(bone.name)
        eb.head = bone.head
        eb.tail = bone.tail
        eb.roll = 0.0
    for bone in spec.BONES:
        if bone.parent is not None:
            edit_bones[bone.name].parent = edit_bones[bone.parent]
    bpy.ops.object.mode_set(mode="OBJECT")

    data.display_type = "STICK"
    return obj


def bind(obj: bpy.types.Object, armature: bpy.types.Object) -> None:
    """object を armature の子にし、Armature modifier で変形する。"""
    obj.parent = armature
    modifier = obj.modifiers.new("Armature", "ARMATURE")
    modifier.object = armature
    modifier.use_vertex_groups = True
