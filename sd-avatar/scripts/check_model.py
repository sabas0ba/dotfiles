"""生成した .blend の構成を検査する。Blender から実行する。

    blender -b --python-exit-code 1 -P scripts/check_model.py -- --blend build/avatar.blend

検査項目: object の存在、bone 名、shape key 名、三角面数の上限、weight の正規化、
頭部の高さと全高の比 (頭身)。
"""

from __future__ import annotations

import argparse
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description="生成した .blend を検査する")
    parser.add_argument("--blend", default="build/avatar.blend")
    return parser.parse_args(argv)


def main() -> None:
    args = parse_args()
    import bpy

    from avatar import spec
    from avatar.build import OBJECT_BODY, OBJECT_CLOTHES, OBJECT_FACE, OBJECT_HAIR

    bpy.ops.wm.open_mainfile(filepath=os.path.abspath(args.blend))
    failures: list[str] = []

    def expect(condition: bool, message: str) -> None:
        if not condition:
            failures.append(message)

    armature = bpy.data.objects.get("Armature")
    expect(armature is not None and armature.type == "ARMATURE", "Armature がない")
    if armature is not None:
        names = {b.name for b in armature.data.bones}
        for bone in spec.BONES:
            expect(bone.name in names, f"bone がない: {bone.name}")
        for bone in spec.BONES:
            if bone.parent is not None and bone.name in names:
                parent = armature.data.bones[bone.name].parent
                expect(
                    parent is not None and parent.name == bone.parent,
                    f"bone の親が違う: {bone.name}",
                )

    total_triangles = 0
    bone_names = {b.name for b in spec.BONES}
    for name in (OBJECT_BODY, OBJECT_FACE, OBJECT_HAIR, OBJECT_CLOTHES):
        obj = bpy.data.objects.get(name)
        expect(obj is not None, f"object がない: {name}")
        if obj is None:
            continue
        expect(obj.parent is armature, f"{name} が Armature の子でない")
        expect(
            any(m.type == "ARMATURE" for m in obj.modifiers), f"{name} に Armature modifier がない"
        )
        mesh = obj.data
        mesh.calc_loop_triangles()
        triangles = len(mesh.loop_triangles)
        total_triangles += triangles
        group_names = {g.index: g.name for g in obj.vertex_groups}
        unweighted = 0
        unnormalized = 0
        for vertex in mesh.vertices:
            total = sum(e.weight for e in vertex.groups if group_names[e.group] in bone_names)
            if total == 0.0:
                unweighted += 1
            elif abs(total - 1.0) > 1e-3:
                unnormalized += 1
        expect(unweighted == 0, f"{name}: weight のない頂点 {unweighted}")
        expect(unnormalized == 0, f"{name}: weight の合計が 1 でない頂点 {unnormalized}")
        expect(len(mesh.uv_layers) >= 1, f"{name}: UV がない")
        print(
            f"  {name}: 頂点 {len(mesh.vertices)}, 三角面 {triangles}, 材質 {len(mesh.materials)}"
        )

    face = bpy.data.objects.get(OBJECT_FACE)
    if face is not None:
        keys = face.data.shape_keys
        expect(keys is not None, "Face に shape key がない")
        if keys is not None:
            present = {k.name for k in keys.key_blocks}
            for name in spec.SHAPE_KEYS:
                expect(name in present, f"shape key がない: {name}")

    body = bpy.data.objects.get(OBJECT_BODY)
    if body is not None:
        zs = [v.co.z for v in body.data.vertices]
        height = max(zs) - min(zs)
        ratio = height / spec.HEAD_H
        print(f"  全高 {height:.3f} m, 頭身 {ratio:.2f}")
        expect(2.35 <= ratio <= 2.55, f"頭身が範囲外: {ratio:.2f}")

    print(f"  三角面の合計 {total_triangles} (上限 {spec.MAX_TRIANGLES})")
    expect(total_triangles <= spec.MAX_TRIANGLES, "三角面数が上限を超えている")

    if failures:
        for message in failures:
            print(f"NG: {message}")
        sys.exit(1)
    print("検査に合格した")


if __name__ == "__main__":
    main()
