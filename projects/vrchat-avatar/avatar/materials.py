"""Principled BSDF の base color だけを持つ単純な material。

FBX は base color を保持するため、Unity 側で material を作り直す際の初期値になる。
texture は本 project の範囲外であり、Blender GUI での作業に委ねる。
"""

from __future__ import annotations

from .params import Palette

MATERIAL_NAMES = (
    "Skin",
    "Underwear",
    "HairMain",
    "HairShadow",
    "HairInner",
    "EyeLine",
    "Iris",
    "Sclera",
)


def palette_color(palette: Palette, name: str) -> tuple:
    return {
        "Skin": palette.skin,
        "Underwear": palette.underwear,
        "HairMain": palette.hair_main,
        "HairShadow": palette.hair_shadow,
        "HairInner": palette.hair_inner,
        "EyeLine": palette.eye_line,
        "Iris": palette.iris,
        "Sclera": palette.sclera,
    }[name]


def create_materials(palette: Palette) -> dict[str, object]:
    import bpy

    materials = {}
    for name in MATERIAL_NAMES:
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        color = palette_color(palette, name)
        if bsdf is not None:
            bsdf.inputs["Base Color"].default_value = color
            bsdf.inputs["Roughness"].default_value = 0.35 if name in ("Iris", "Sclera") else 0.7
        mat.diffuse_color = color
        materials[name] = mat
    return materials
