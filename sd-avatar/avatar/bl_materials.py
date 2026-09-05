"""材質と texture。bpy に依存する。

Unity 側では lilToon などの toon shader へ差し替える前提のため、Blender 側の材質は
Principled BSDF の base color と、髪の gradient texture の参照だけを持つ最小構成にする。
"""

from __future__ import annotations

import os

import bpy

from avatar import png, spec

HAIR_TEXTURE_NAME = "hair_gradient.png"


def _principled(material: bpy.types.Material) -> bpy.types.ShaderNode:
    for node in material.node_tree.nodes:
        if node.type == "BSDF_PRINCIPLED":
            return node
    raise RuntimeError("Principled BSDF が見つからない")


def create_materials(texture_dir: str) -> dict[str, bpy.types.Material]:
    os.makedirs(texture_dir, exist_ok=True)
    hair_path = os.path.join(texture_dir, HAIR_TEXTURE_NAME)
    png.write_hair_gradient(hair_path)

    materials: dict[str, bpy.types.Material] = {}
    for name, palette_key in spec.MATERIALS.items():
        material = bpy.data.materials.new(name)
        material.use_nodes = True
        bsdf = _principled(material)
        bsdf.inputs["Base Color"].default_value = png.hex_to_linear_rgba(spec.PALETTE[palette_key])
        bsdf.inputs["Roughness"].default_value = 0.85
        bsdf.inputs["Specular IOR Level"].default_value = 0.2
        material.diffuse_color = png.hex_to_linear_rgba(spec.PALETTE[palette_key])
        if name == "Hair":
            _attach_texture(material, bsdf, hair_path)
        materials[name] = material
    return materials


def _attach_texture(material: bpy.types.Material, bsdf: bpy.types.ShaderNode, path: str) -> None:
    image = bpy.data.images.load(path)
    image.colorspace_settings.name = "sRGB"
    tree = material.node_tree
    tex = tree.nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.interpolation = "Linear"
    tex.extension = "EXTEND"
    tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
