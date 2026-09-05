"""生成の手順全体。`blender -b --python scripts/build_avatar.py` から呼ばれる。

1. 空の scene を用意する
2. Body と Hair の mesh を loft から生成する
3. subdivision を適用して滑らかにする (shape key の追加より前に行う)
4. shape key、armature、親子付けを設定する
5. FBX と .blend を書き出し、統計を report.json に残す
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from .body import build_body
from .hair import build_hair
from .materials import create_materials
from .params import DEFAULT_SPEC, AvatarSpec, MeshResolution
from .rig import all_bones, bind, create_armature
from .shapekeys import add_shape_keys

FBX_NAME = "avatar.fbx"
BLEND_NAME = "avatar.blend"
REPORT_NAME = "report.json"


def reset_scene() -> None:
    import bpy

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0


def apply_subdivision(obj, levels: int) -> None:
    import bpy

    if levels <= 0:
        return
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    modifier = obj.modifiers.new("Subdivision", "SUBSURF")
    modifier.levels = levels
    modifier.render_levels = levels
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.select_set(False)


def triangle_count(obj) -> int:
    return sum(len(poly.vertices) - 2 for poly in obj.data.polygons)


def export_fbx(path: Path) -> None:
    import bpy

    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.export_scene.fbx(
        filepath=str(path),
        use_selection=False,
        object_types={"ARMATURE", "MESH"},
        # Unity で scale factor 1、単位 1 m として読める設定。
        apply_scale_options="FBX_SCALE_ALL",
        apply_unit_scale=True,
        # subdivision は既に適用済み。shape key を保つため modifier は適用しない。
        use_mesh_modifiers=False,
        mesh_smooth_type="FACE",
        add_leaf_bones=False,
        primary_bone_axis="Y",
        secondary_bone_axis="X",
        armature_nodetype="NULL",
        bake_anim=False,
        path_mode="AUTO",
    )


def build(spec: AvatarSpec, out_dir: Path) -> dict:
    import bpy

    out_dir.mkdir(parents=True, exist_ok=True)
    reset_scene()
    materials = create_materials(spec.palette)

    body = build_body(spec).to_object("Body", materials)
    hair = build_hair(spec).to_object("Hair", materials)
    for obj in (body, hair):
        apply_subdivision(obj, spec.resolution.subdivision_levels)

    add_shape_keys(body, spec.proportions)

    armature = create_armature(spec.proportions)
    for obj in (body, hair):
        bind(obj, armature)

    fbx_path = out_dir / FBX_NAME
    blend_path = out_dir / BLEND_NAME
    export_fbx(fbx_path)
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path), compress=True)

    report = {
        "fbx": str(fbx_path),
        "blend": str(blend_path),
        "height_m": spec.proportions.height,
        "subdivision_levels": spec.resolution.subdivision_levels,
        "bones": len(all_bones(spec.proportions)),
        "meshes": {
            obj.name: {
                "vertices": len(obj.data.vertices),
                "triangles": triangle_count(obj),
                "materials": [m.name for m in obj.data.materials],
                "shape_keys": [k.name for k in obj.data.shape_keys.key_blocks] if obj.data.shape_keys else [],
            }
            for obj in (body, hair)
        },
    }
    report["triangles_total"] = sum(m["triangles"] for m in report["meshes"].values())
    (out_dir / REPORT_NAME).write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return report


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="VRChat 向け素体を生成して FBX に書き出す")
    parser.add_argument("--out", type=Path, default=Path("build"), help="出力先ディレクトリ")
    parser.add_argument(
        "--subdivision",
        type=int,
        default=DEFAULT_SPEC.resolution.subdivision_levels,
        help="subdivision surface の段数 (0 で無効)",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> None:
    args = parse_args(argv)
    resolution = MeshResolution(subdivision_levels=args.subdivision)
    spec = AvatarSpec(resolution=resolution)
    report = build(spec, args.out)
    print(json.dumps(report, indent=2, ensure_ascii=False))
