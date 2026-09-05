"""複数の loft を 1 つの Blender mesh object にまとめる。

bpy に触れるのは to_object だけである。それ以外は純粋な Python の list 操作であり、
Blender 外でも構造の検証ができる。
"""

from __future__ import annotations

from dataclasses import dataclass, field

from .loft import LoftResult, Vec3, Weights

MIRROR_NAME_MAP = {"Left": "Right", "Right": "Left"}


def mirror_bone_name(name: str) -> str:
    for src, dst in MIRROR_NAME_MAP.items():
        if name.startswith(src):
            return dst + name[len(src) :]
    return name


@dataclass
class MeshBuilder:
    vertices: list[Vec3] = field(default_factory=list)
    faces: list[tuple[int, ...]] = field(default_factory=list)
    face_materials: list[str] = field(default_factory=list)
    face_uvs: list[list[tuple[float, float]]] = field(default_factory=list)
    vertex_weights: list[Weights] = field(default_factory=list)
    material_order: list[str] = field(default_factory=list)

    def add(self, loft: LoftResult, mirror_x: bool = False) -> range:
        """loft を取り込み、追加した頂点の index 範囲を返す。

        mirror_x は x を反転して右側の部品を作る。面の巻き方向を反転して法線を
        外向きに保ち、bone 名の Left/Right を入れ替える。
        """
        offset = len(self.vertices)
        for v in loft.vertices:
            self.vertices.append((-v[0], v[1], v[2]) if mirror_x else v)
        for w in loft.vertex_weights:
            self.vertex_weights.append({mirror_bone_name(k): val for k, val in w.items()} if mirror_x else dict(w))
        for face, mat, uvs in zip(loft.faces, loft.face_materials, loft.face_uvs):
            indices = tuple(i + offset for i in face)
            if mirror_x:
                indices = tuple(reversed(indices))
                uvs = list(reversed(uvs))
            self.faces.append(indices)
            self.face_materials.append(mat)
            self.face_uvs.append(uvs)
            if mat not in self.material_order:
                self.material_order.append(mat)
        return range(offset, len(self.vertices))

    def to_object(self, name: str, materials: dict[str, object]):
        """Blender の mesh object を生成し、scene に link して返す。"""
        import bpy

        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(self.vertices, [], self.faces)
        mesh.validate(verbose=False)
        mesh.update()

        for mat_name in self.material_order:
            mesh.materials.append(materials[mat_name])
        slot = {mat_name: i for i, mat_name in enumerate(self.material_order)}
        mesh.polygons.foreach_set("material_index", [slot[m] for m in self.face_materials])
        mesh.polygons.foreach_set("use_smooth", [True] * len(mesh.polygons))

        uv_layer = mesh.uv_layers.new(name="UVMap")
        for poly, uvs in zip(mesh.polygons, self.face_uvs):
            for j, uv in enumerate(uvs):
                uv_layer.data[poly.loop_start + j].uv = uv

        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)

        groups: dict[str, object] = {}
        for index, weights in enumerate(self.vertex_weights):
            for bone, weight in weights.items():
                group = groups.get(bone)
                if group is None:
                    group = obj.vertex_groups.new(name=bone)
                    groups[bone] = group
                group.add([index], weight, "REPLACE")
        return obj
