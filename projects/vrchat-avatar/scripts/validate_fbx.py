"""書き出した FBX を再読込し、VRChat で必要な構造を検査する。

使い方: blender -b --python-exit-code 1 --python scripts/validate_fbx.py -- build/avatar.fbx

検査項目:
- Unity Humanoid の必須 bone がすべて存在する
- 推奨 bone (目、指、つま先) が存在する
- viseme とまばたきの shape key が Body に存在する
- すべての頂点が 1 つ以上の bone weight を持つ
- 三角形数を VRChat の performance rank の目安と比較する

三角形数の閾値は creators.vrchat.com の Avatar Performance Ranking System に基づく
値であり、docs/spec.md に出典を記載する。
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from avatar.rig import RECOMMENDED_BONES, REQUIRED_BONES  # noqa: E402
from avatar.shapekeys import EYE_SHAPE_NAMES, VISEME_NAMES  # noqa: E402

TRIANGLE_BUDGET = {
    "pc_excellent": 32000,
    "pc_good": 70000,
    "quest_excellent": 7500,
    "quest_good": 10000,
    "quest_medium": 15000,
    "quest_poor": 20000,
}


def import_fbx(path: Path):
    import bpy

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=str(path))
    return bpy.context.scene.objects


def rank(triangles: int, prefix: str) -> str:
    """三角形数だけから見た rank の目安。他の指標 (bone 数、material 数等) は含まない。"""
    for name in ("excellent", "good", "medium", "poor"):
        key = f"{prefix}_{name}"
        if key in TRIANGLE_BUDGET and triangles <= TRIANGLE_BUDGET[key]:
            return name
    return "exceeds_listed_budgets"


def validate(path: Path) -> dict:
    objects = import_fbx(path)
    armatures = [o for o in objects if o.type == "ARMATURE"]
    meshes = [o for o in objects if o.type == "MESH"]
    failures = []

    if len(armatures) != 1:
        failures.append(f"armature は 1 つであること: {len(armatures)}")
        bones = set()
    else:
        bones = {b.name for b in armatures[0].data.bones}
        root = [b.name for b in armatures[0].data.bones if b.parent is None]
        if root != ["Hips"]:
            failures.append(f"root bone は Hips のみであること: {root}")

    missing_required = sorted(set(REQUIRED_BONES) - bones)
    missing_recommended = sorted(set(RECOMMENDED_BONES) - bones)
    if missing_required:
        failures.append(f"必須 bone が不足: {missing_required}")
    if missing_recommended:
        failures.append(f"推奨 bone が不足: {missing_recommended}")

    body = next((m for m in meshes if m.name == "Body"), None)
    if body is None:
        failures.append("Body mesh が存在しない")
        shape_keys = set()
    else:
        shape_keys = {k.name for k in body.data.shape_keys.key_blocks} if body.data.shape_keys else set()
    missing_shapes = sorted((set(VISEME_NAMES) | set(EYE_SHAPE_NAMES)) - shape_keys)
    if missing_shapes:
        failures.append(f"shape key が不足: {missing_shapes}")

    mesh_reports = {}
    total = 0
    for mesh in meshes:
        group_names = {g.index: g.name for g in mesh.vertex_groups}
        unweighted = 0
        unknown_groups = set()
        for v in mesh.data.vertices:
            weight = 0.0
            for g in v.groups:
                weight += g.weight
                name = group_names.get(g.group)
                if name not in bones:
                    unknown_groups.add(name)
            if weight <= 0.0:
                unweighted += 1
        triangles = sum(len(p.vertices) - 2 for p in mesh.data.polygons)
        total += triangles
        mesh_reports[mesh.name] = {
            "vertices": len(mesh.data.vertices),
            "triangles": triangles,
            "unweighted_vertices": unweighted,
            "materials": [m.name for m in mesh.data.materials if m is not None],
        }
        if unweighted:
            failures.append(f"{mesh.name}: weight を持たない頂点が {unweighted} 個ある")
        if unknown_groups:
            failures.append(f"{mesh.name}: bone に対応しない vertex group: {sorted(unknown_groups)}")
        if mesh.parent is None or mesh.parent.type != "ARMATURE":
            failures.append(f"{mesh.name}: armature の子ではない")

    report = {
        "fbx": str(path),
        "bones": len(bones),
        "meshes": mesh_reports,
        "triangles_total": total,
        "rank": {"pc": rank(total, "pc"), "quest": rank(total, "quest")},
        "failures": failures,
    }
    return report


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(argv) != 1:
        print("使い方: validate_fbx.py -- <avatar.fbx>", file=sys.stderr)
        sys.exit(2)
    report = validate(Path(argv[0]))
    print(json.dumps(report, indent=2, ensure_ascii=False))
    if report["failures"]:
        sys.exit(1)


if __name__ == "__main__":
    main()
