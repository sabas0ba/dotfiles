"""確認用の render。bpy に依存する。

headless 環境では EEVEE と Workbench が GPU context を要求して失敗するため Cycles (CPU) を使う。
三面図 (正面、側面、背面) と、表情ごとの顔の一覧を書き出す。
"""

from __future__ import annotations

import math
import os

import bpy

from avatar import spec
from avatar.build import OBJECT_BODY, OBJECT_CLOTHES, OBJECT_FACE, OBJECT_HAIR

SAMPLES = 48
MODEL_OBJECTS = (OBJECT_BODY, OBJECT_FACE, OBJECT_HAIR, OBJECT_CLOTHES)


def _setup_scene(width: int, height: int) -> bpy.types.Scene:
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = SAMPLES
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 2
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "Standard"
    scene.display_settings.display_device = "sRGB"

    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    if background is not None:
        # 無彩色の環境光にし、白に近い髪や肌へ色が被らないようにする。
        background.inputs["Color"].default_value = (0.93, 0.93, 0.93, 1.0)
        background.inputs["Strength"].default_value = 0.9

    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 2.0
    sun.data.angle = math.radians(15.0)
    sun.rotation_euler = (math.radians(50.0), math.radians(-10.0), math.radians(-30.0))
    scene.collection.objects.link(sun)
    return scene


def _camera(name: str, location, rotation, ortho_scale: float) -> bpy.types.Object:
    data = bpy.data.cameras.new(name)
    data.type = "ORTHO"
    data.ortho_scale = ortho_scale
    obj = bpy.data.objects.new(name, data)
    obj.location = location
    obj.rotation_euler = rotation
    bpy.context.scene.collection.objects.link(obj)
    return obj


def _instance_model(angle: float, offset_x: float, face_data=None) -> list[bpy.types.Object]:
    """armature と部位をまとめて複製し、Z 軸まわりに回して横へ並べる。"""
    armature = bpy.data.objects["Armature"]
    copies: dict[str, bpy.types.Object] = {}
    new_armature = armature.copy()
    # 複製元は非表示にしてあるため、複製側で表示状態を戻す。
    new_armature.hide_render = False
    new_armature.hide_viewport = False
    new_armature.location = (offset_x, 0.0, 0.0)
    new_armature.rotation_euler = (0.0, 0.0, angle)
    bpy.context.scene.collection.objects.link(new_armature)
    copies[armature.name] = new_armature
    result = [new_armature]
    for name in MODEL_OBJECTS:
        source = bpy.data.objects[name]
        obj = source.copy()
        obj.hide_render = False
        obj.hide_viewport = False
        if name == OBJECT_FACE and face_data is not None:
            obj.data = face_data
        obj.parent = new_armature
        obj.matrix_parent_inverse = source.matrix_parent_inverse.copy()
        for modifier in obj.modifiers:
            if modifier.type == "ARMATURE":
                modifier.object = new_armature
        bpy.context.scene.collection.objects.link(obj)
        result.append(obj)
    return result


def _hide_originals() -> None:
    for name in ("Armature", *MODEL_OBJECTS):
        obj = bpy.data.objects[name]
        obj.hide_render = True
        obj.hide_viewport = True


def render_turnaround(path: str) -> None:
    """正面、側面 (右)、背面を 1 枚に並べる。"""
    scene = _setup_scene(1500, 900)
    _hide_originals()
    spacing = 0.9
    for index, angle in enumerate((0.0, math.radians(-90.0), math.radians(180.0))):
        _instance_model(angle, (index - 1) * spacing)
    height = spec.HEAD_CENTER[2] + spec.HEAD_RADII[2]
    camera = _camera(
        "TurnaroundCamera",
        (0.0, -5.0, height * 0.5),
        (math.radians(90.0), 0.0, 0.0),
        spacing * 3.0,
    )
    scene.camera = camera
    scene.render.filepath = os.path.abspath(path)
    bpy.ops.render.render(write_still=True)


def render_expressions(path: str, keys: list[str]) -> None:
    """表情ごとに顔を複製し、横に並べて描く。"""
    scene = _setup_scene(300 * len(keys), 360)
    _hide_originals()
    spacing = spec.HEAD_RADII[0] * 2.6
    face = bpy.data.objects[OBJECT_FACE]
    for index, key in enumerate(keys):
        data = face.data.copy()
        for block in data.shape_keys.key_blocks:
            block.value = 0.0
        for name in key.split("+"):
            if name != "Basis":
                data.shape_keys.key_blocks[name].value = 1.0
        _instance_model(0.0, (index - (len(keys) - 1) / 2.0) * spacing, data)
    camera = _camera(
        "ExpressionCamera",
        (0.0, -5.0, spec.HEAD_CENTER[2] - spec.HEAD_RADII[2] * 0.1),
        (math.radians(90.0), 0.0, 0.0),
        spacing * len(keys),
    )
    scene.camera = camera
    scene.render.filepath = os.path.abspath(path)
    bpy.ops.render.render(write_still=True)
