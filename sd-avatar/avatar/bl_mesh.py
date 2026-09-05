"""Blender 内での mesh object 生成と加工。bpy に依存する。"""

from __future__ import annotations

import bpy

from avatar import spec, weights
from avatar.geometry import Mesh

TAG_PREFIX = "tag:"


def create_object(
    name: str, mesh: Mesh, materials: dict[str, bpy.types.Material]
) -> bpy.types.Object:
    """Mesh から object を作り、材質 slot と tag の vertex group を与える。"""
    data = bpy.data.meshes.new(name)
    data.from_pydata(mesh.verts, [], mesh.faces)
    data.validate(verbose=False)

    slot_index: dict[str, int] = {}
    for material_name in mesh.face_materials:
        if material_name not in slot_index:
            slot_index[material_name] = len(data.materials)
            data.materials.append(materials[material_name])
    for polygon, material_name in zip(data.polygons, mesh.face_materials, strict=True):
        polygon.material_index = slot_index[material_name]
    data.shade_smooth()
    data.update()

    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)

    by_tag: dict[str, list[int]] = {}
    for index, tag in enumerate(mesh.tags):
        by_tag.setdefault(tag, []).append(index)
    for tag, indices in by_tag.items():
        group = obj.vertex_groups.new(name=TAG_PREFIX + tag)
        group.add(indices, 1.0, "REPLACE")
    return obj


def _apply_modifier(obj: bpy.types.Object, modifier: bpy.types.Modifier) -> None:
    bpy.context.view_layer.objects.active = obj
    with bpy.context.temp_override(
        object=obj, active_object=obj, selected_objects=[obj], selected_editable_objects=[obj]
    ):
        bpy.ops.object.modifier_apply(modifier=modifier.name)


def apply_subdivision(obj: bpy.types.Object, levels: int) -> None:
    modifier = obj.modifiers.new("Subdivision", "SUBSURF")
    modifier.levels = levels
    modifier.render_levels = levels
    _apply_modifier(obj, modifier)


def apply_solidify(obj: bpy.types.Object, thickness: float) -> None:
    modifier = obj.modifiers.new("Solidify", "SOLIDIFY")
    modifier.thickness = thickness
    modifier.offset = -1.0
    modifier.use_rim = True
    _apply_modifier(obj, modifier)


def read_tags(obj: bpy.types.Object) -> list[str]:
    """tag の vertex group から各頂点の tag を復元する。

    subdivision 後に補間された頂点は複数の group に属しうるため、最大 weight の group を採る。
    """
    names = {
        g.index: g.name[len(TAG_PREFIX) :]
        for g in obj.vertex_groups
        if g.name.startswith(TAG_PREFIX)
    }
    tags = []
    for vertex in obj.data.vertices:
        best = None
        best_w = -1.0
        for element in vertex.groups:
            if element.group in names and element.weight > best_w:
                best_w = element.weight
                best = names[element.group]
        if best is None:
            raise RuntimeError(f"{obj.name}: tag のない頂点 {vertex.index}")
        tags.append(best)
    return tags


def remove_tag_groups(obj: bpy.types.Object) -> None:
    for group in [g for g in obj.vertex_groups if g.name.startswith(TAG_PREFIX)]:
        obj.vertex_groups.remove(group)


def assign_bone_weights(obj: bpy.types.Object, tags: list[str], rules: dict[str, str]) -> None:
    """tag の weight 規則に従って bone の vertex group を与える。"""
    groups: dict[str, bpy.types.VertexGroup] = {}
    for bone in spec.BONES:
        groups[bone.name] = obj.vertex_groups.new(name=bone.name)
    for vertex, tag in zip(obj.data.vertices, tags, strict=True):
        for bone_name, weight in weights.weights_for(tuple(vertex.co), rules[tag]).items():
            groups[bone_name].add([vertex.index], weight, "REPLACE")


def set_height_uv(obj: bpy.types.Object, z_range: tuple[float, float]) -> None:
    """高さを V に写す UV。gradient texture を貼るために使う。"""
    z0, z1 = z_range
    layer = obj.data.uv_layers.new(name="UVMap")
    for loop in obj.data.loops:
        z = obj.data.vertices[loop.vertex_index].co.z
        # V をちょうど 0 や 1 にすると REPEAT の texture で反対側の端へ回り込むため、内側に留める。
        v = min(0.998, max(0.002, (z - z0) / (z1 - z0)))
        layer.data[loop.index].uv = (0.5, v)


def set_flat_uv(obj: bpy.types.Object) -> None:
    """単色材質用の UV。Unity での texture 差し替えに備えて layer だけ用意する。"""
    layer = obj.data.uv_layers.new(name="UVMap")
    for loop in obj.data.loops:
        layer.data[loop.index].uv = (0.5, 0.5)


def add_shape_keys(
    obj: bpy.types.Object, targets: dict[str, list[tuple[float, float, float]]]
) -> None:
    """targets は key 名 -> 頂点位置の列。"Basis" を先に登録する。"""
    basis = obj.shape_key_add(name="Basis", from_mix=False)
    for point, position in zip(basis.data, targets["Basis"], strict=True):
        point.co = position
    for vertex, position in zip(obj.data.vertices, targets["Basis"], strict=True):
        vertex.co = position
    for name, positions in targets.items():
        if name == "Basis":
            continue
        key = obj.shape_key_add(name=name, from_mix=False)
        # Blender 5.1 では新規 key の value が 1.0 になるため、rest 状態を明示する。
        key.value = 0.0
        key.slider_min = 0.0
        key.slider_max = 1.0
        for point, position in zip(key.data, positions, strict=True):
            point.co = position
    obj.data.shape_keys.use_relative = True
