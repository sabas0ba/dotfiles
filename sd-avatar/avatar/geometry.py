"""bpy に依存しない mesh 生成の基本操作。

頂点は (x, y, z) の tuple、面は頂点 index の tuple (三角形または四角形) で表す。
loft (断面の列を面で繋ぐ) と tube (経路に沿った断面の列) の 2 つを基本とし、
体、髪、衣装のすべてをこれらで構成する。
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

Vec = tuple[float, float, float]


def add(a: Vec, b: Vec) -> Vec:
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def sub(a: Vec, b: Vec) -> Vec:
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def scale(a: Vec, s: float) -> Vec:
    return (a[0] * s, a[1] * s, a[2] * s)


def dot(a: Vec, b: Vec) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def cross(a: Vec, b: Vec) -> Vec:
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def length(a: Vec) -> float:
    return math.sqrt(dot(a, a))


def normalize(a: Vec) -> Vec:
    n = length(a)
    if n == 0.0:
        return (0.0, 0.0, 0.0)
    return scale(a, 1.0 / n)


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def lerp_vec(a: Vec, b: Vec, t: float) -> Vec:
    return (lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t))


def smoothstep(edge0: float, edge1: float, x: float) -> float:
    if edge0 == edge1:
        return 0.0 if x < edge0 else 1.0
    t = min(1.0, max(0.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def catmull_rom(points: list[Vec], samples: int) -> list[Vec]:
    """制御点列を通る Catmull-Rom spline を samples 個の点で標本化する。"""
    if len(points) < 2:
        raise ValueError("2 点以上が必要")
    if samples < 2:
        raise ValueError("samples は 2 以上")
    pts = [points[0], *points, points[-1]]
    segments = len(points) - 1
    result: list[Vec] = []
    for i in range(samples):
        u = i / (samples - 1) * segments
        seg = min(int(u), segments - 1)
        t = u - seg
        p0, p1, p2, p3 = pts[seg], pts[seg + 1], pts[seg + 2], pts[seg + 3]
        t2 = t * t
        t3 = t2 * t
        out = []
        for k in range(3):
            v = 0.5 * (
                2.0 * p1[k]
                + (-p0[k] + p2[k]) * t
                + (2.0 * p0[k] - 5.0 * p1[k] + 4.0 * p2[k] - p3[k]) * t2
                + (-p0[k] + 3.0 * p1[k] - 3.0 * p2[k] + p3[k]) * t3
            )
            out.append(v)
        result.append((out[0], out[1], out[2]))
    return result


def superellipse(t: float, rx: float, ry: float, n: float) -> tuple[float, float]:
    """媒介変数 t (0..2π) の超楕円上の点。n=2 で楕円、大きいほど角丸長方形に近づく。"""
    c = math.cos(t)
    s = math.sin(t)
    x = math.copysign(abs(c) ** (2.0 / n), c) * rx
    y = math.copysign(abs(s) ** (2.0 / n), s) * ry
    return x, y


@dataclass
class Mesh:
    """頂点、面、頂点 tag を持つ単純な mesh。tag は weight や shape key の対象選択に使う。"""

    verts: list[Vec] = field(default_factory=list)
    faces: list[tuple[int, ...]] = field(default_factory=list)
    tags: list[str] = field(default_factory=list)
    face_materials: list[str] = field(default_factory=list)

    def append(self, other: Mesh) -> None:
        offset = len(self.verts)
        self.verts.extend(other.verts)
        self.tags.extend(other.tags)
        self.faces.extend(tuple(i + offset for i in f) for f in other.faces)
        self.face_materials.extend(other.face_materials)

    def triangle_count(self) -> int:
        return sum(len(f) - 2 for f in self.faces)

    def mirrored_x(self, tag_map: dict[str, str] | None = None) -> Mesh:
        """X 軸で鏡映した複製。面の向きを保つため頂点順を反転する。"""
        tags = list(self.tags)
        if tag_map:
            tags = [tag_map.get(t, t) for t in tags]
        return Mesh(
            verts=[(-v[0], v[1], v[2]) for v in self.verts],
            faces=[tuple(reversed(f)) for f in self.faces],
            tags=tags,
            face_materials=list(self.face_materials),
        )

    def translated(self, d: Vec) -> Mesh:
        return Mesh(
            verts=[add(v, d) for v in self.verts],
            faces=list(self.faces),
            tags=list(self.tags),
            face_materials=list(self.face_materials),
        )


def ring(
    center: Vec, u: Vec, v: Vec, rx: float, ry: float, segments: int, n: float = 2.0
) -> list[Vec]:
    """center を中心に u, v 方向へ半径 rx, ry の閉曲線を segments 点で返す。"""
    pts = []
    for i in range(segments):
        t = 2.0 * math.pi * i / segments
        a, b = superellipse(t, rx, ry, n)
        pts.append(add(center, add(scale(u, a), scale(v, b))))
    return pts


def loft(
    rings: list[list[Vec]],
    material: str,
    tag: str,
    cap_start: bool = True,
    cap_end: bool = True,
) -> Mesh:
    """断面の列を四角面で繋ぐ。端は中心頂点への扇で閉じる。"""
    if len(rings) < 2:
        raise ValueError("断面は 2 つ以上")
    n = len(rings[0])
    if any(len(r) != n for r in rings):
        raise ValueError("断面の頂点数が一致しない")
    mesh = Mesh()
    for r in rings:
        mesh.verts.extend(r)
        mesh.tags.extend([tag] * n)
    for k in range(len(rings) - 1):
        base = k * n
        for i in range(n):
            j = (i + 1) % n
            mesh.faces.append((base + i, base + j, base + n + j, base + n + i))
            mesh.face_materials.append(material)
    if cap_start:
        _cap(mesh, 0, n, material, tag, reverse=True)
    if cap_end:
        _cap(mesh, (len(rings) - 1) * n, n, material, tag, reverse=False)
    return mesh


def _cap(mesh: Mesh, base: int, n: int, material: str, tag: str, reverse: bool) -> None:
    ring_pts = mesh.verts[base : base + n]
    cx = sum(p[0] for p in ring_pts) / n
    cy = sum(p[1] for p in ring_pts) / n
    cz = sum(p[2] for p in ring_pts) / n
    center = len(mesh.verts)
    mesh.verts.append((cx, cy, cz))
    mesh.tags.append(tag)
    for i in range(n):
        j = (i + 1) % n
        face = (center, base + j, base + i) if reverse else (center, base + i, base + j)
        mesh.faces.append(face)
        mesh.face_materials.append(material)


def axis_frame(direction: Vec, reference: Vec = (0.0, -1.0, 0.0)) -> tuple[Vec, Vec]:
    """direction に直交する 2 つの単位ベクトル (u, v) を返す。u は reference に近い向き。"""
    d = normalize(direction)
    ref = reference
    if abs(dot(d, normalize(ref))) > 0.99:
        ref = (1.0, 0.0, 0.0)
    u = normalize(sub(ref, scale(d, dot(ref, d))))
    v = cross(d, u)
    return u, v


def loft_along_axis(
    start: Vec,
    direction: Vec,
    profile: list[tuple[float, float, float]],
    segments: int,
    material: str,
    tag: str,
    reference: Vec = (0.0, -1.0, 0.0),
    n: float = 2.0,
    cap_start: bool = True,
    cap_end: bool = True,
) -> Mesh:
    """start から direction に沿って (距離, 半径 u, 半径 v) の断面を並べる。"""
    d = normalize(direction)
    u, v = axis_frame(d, reference)
    rings = []
    for dist, ru, rv in profile:
        c = add(start, scale(d, dist))
        rings.append(ring(c, u, v, ru, rv, segments, n))
    return loft(rings, material, tag, cap_start, cap_end)


def tube(
    path: list[Vec],
    radii: list[tuple[float, float]],
    normal_of: object,
    segments: int,
    material: str,
    tag: str,
    cap_start: bool = True,
    cap_end: bool = True,
) -> Mesh:
    """経路に沿った断面を繋ぐ。normal_of(point) が各点での法線 (断面の v 方向) を与える。

    断面の u 方向は経路の接線と法線の外積で、法線が滑らかなら捩れない。
    """
    if len(path) != len(radii):
        raise ValueError("path と radii の長さが一致しない")
    rings = []
    count = len(path)
    for i, p in enumerate(path):
        prev_p = path[max(i - 1, 0)]
        next_p = path[min(i + 1, count - 1)]
        t = normalize(sub(next_p, prev_p))
        nrm = normalize(normal_of(p))
        nrm = normalize(sub(nrm, scale(t, dot(nrm, t))))
        u = normalize(cross(t, nrm))
        ru, rv = radii[i]
        rings.append(ring(p, u, nrm, ru, rv, segments))
    return loft(rings, material, tag, cap_start, cap_end)


def disk(
    center: Vec,
    u: Vec,
    v: Vec,
    rx: float,
    ry: float,
    rings: int,
    segments: int,
    material: str,
    tag: str,
    n: float = 2.0,
    project: object = None,
) -> Mesh:
    """同心の閉曲線で埋めた円板。project(point) が与えられれば各頂点を投影する。"""
    mesh = Mesh()

    def place(p: Vec) -> Vec:
        return project(p) if project else p

    mesh.verts.append(place(center))
    mesh.tags.append(tag)
    for k in range(1, rings + 1):
        f = k / rings
        for p in ring(center, u, v, rx * f, ry * f, segments, n):
            mesh.verts.append(place(p))
            mesh.tags.append(tag)
    for i in range(segments):
        j = (i + 1) % segments
        mesh.faces.append((0, 1 + i, 1 + j))
        mesh.face_materials.append(material)
    for k in range(1, rings):
        inner = 1 + (k - 1) * segments
        outer = 1 + k * segments
        for i in range(segments):
            j = (i + 1) % segments
            mesh.faces.append((inner + i, outer + i, outer + j, inner + j))
            mesh.face_materials.append(material)
    return mesh


def octahedron(center: Vec, rx: float, ry: float, rz: float, material: str, tag: str) -> Mesh:
    """宝石状の八面体。"""
    cx, cy, cz = center
    verts: list[Vec] = [
        (cx, cy, cz + rz),
        (cx + rx, cy, cz),
        (cx, cy + ry, cz),
        (cx - rx, cy, cz),
        (cx, cy - ry, cz),
        (cx, cy, cz - rz),
    ]
    faces = [
        (0, 1, 2),
        (0, 2, 3),
        (0, 3, 4),
        (0, 4, 1),
        (5, 2, 1),
        (5, 3, 2),
        (5, 4, 3),
        (5, 1, 4),
    ]
    return Mesh(verts, faces, [tag] * 6, [material] * 8)
