"""断面 (ring) の列から閉じた筒状 mesh を生成する loft。

すべての body part は本 module の loft で表現する。頂点座標、面、UV、bone weight、
material を ring の定義から決定論的に導出するため、生成結果は入力に対して再現性を
持つ。bpy には依存せず、純粋な Python の数値計算だけで完結する。
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Callable, Optional

Vec3 = tuple[float, float, float]
Weights = dict[str, float]

TWO_PI = 2.0 * math.pi


def normalize(v: Vec3) -> Vec3:
    length = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
    if length == 0.0:
        raise ValueError("零ベクトルは正規化できない")
    return (v[0] / length, v[1] / length, v[2] / length)


def cross(a: Vec3, b: Vec3) -> Vec3:
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def add(a: Vec3, b: Vec3) -> Vec3:
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def scale(a: Vec3, s: float) -> Vec3:
    return (a[0] * s, a[1] * s, a[2] * s)


def basis_for_direction(direction: Vec3) -> tuple[Vec3, Vec3]:
    """loft の進行方向 d に対し、u × v = d を満たす ring 平面の基底 (u, v) を返す。

    外向き法線を保つには面の巻き方向と進行方向の関係が固定されている必要があり、
    基底の手性をここで保証する。
    """
    d = normalize(direction)
    helper: Vec3 = (0.0, 0.0, 1.0) if abs(d[2]) < 0.9 else (1.0, 0.0, 0.0)
    u = normalize(cross(helper, d))
    v = cross(d, u)
    return u, v


AXIS_Z_BASIS: tuple[Vec3, Vec3] = ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0))


@dataclass
class Ring:
    """loft の 1 断面。

    center を中心に、u 方向に rx、v 方向に ry の楕円を置く。ry_front を与えると
    v が負の側 (顔の前面など) だけ別の半径にし、前後非対称な断面を作る。
    bulge は角度 (rad) を受け取り、(u 方向, v 方向) の追加変位を返す関数である。
    weights は当該 ring の頂点に与える bone weight で、None の場合は前後の ring から
    線形補間する。material は当該 ring と次の ring の間の面に適用する。
    """

    center: Vec3
    rx: float
    ry: float
    ry_front: Optional[float] = None
    u: Vec3 = AXIS_Z_BASIS[0]
    v: Vec3 = AXIS_Z_BASIS[1]
    bulge: Optional[Callable[[float], tuple[float, float]]] = None
    weights: Optional[Weights] = None
    material: Optional[str] = None

    def point(self, angle: float) -> Vec3:
        cos_a = math.cos(angle)
        sin_a = math.sin(angle)
        ry = self.ry_front if (self.ry_front is not None and sin_a < 0.0) else self.ry
        du = self.rx * cos_a
        dv = ry * sin_a
        if self.bulge is not None:
            bu, bv = self.bulge(angle)
            du += bu
            dv += bv
        return add(self.center, add(scale(self.u, du), scale(self.v, dv)))


@dataclass
class LoftResult:
    """MeshBuilder が取り込む中間表現。頂点 index は本 loft 内で 0 始まり。"""

    vertices: list[Vec3] = field(default_factory=list)
    faces: list[tuple[int, ...]] = field(default_factory=list)
    face_materials: list[str] = field(default_factory=list)
    face_uvs: list[list[tuple[float, float]]] = field(default_factory=list)
    vertex_weights: list[Weights] = field(default_factory=list)


def blend_weights(a: Weights, b: Weights, t: float) -> Weights:
    names = set(a) | set(b)
    result = {}
    for name in names:
        w = a.get(name, 0.0) * (1.0 - t) + b.get(name, 0.0) * t
        if w > 1e-6:
            result[name] = w
    return result


def interpolate_ring_weights(rings: list[Ring]) -> list[Weights]:
    """weights 未指定の ring を、前後の指定済み ring から index に対して線形補間する。"""
    keyed = [i for i, ring in enumerate(rings) if ring.weights is not None]
    if not keyed:
        raise ValueError("少なくとも 1 つの ring に weights が必要")
    result: list[Weights] = []
    for i in range(len(rings)):
        if rings[i].weights is not None:
            result.append(dict(rings[i].weights))
            continue
        before = max((k for k in keyed if k < i), default=None)
        after = min((k for k in keyed if k > i), default=None)
        if before is None:
            result.append(dict(rings[after].weights))
        elif after is None:
            result.append(dict(rings[before].weights))
        else:
            t = (i - before) / (after - before)
            result.append(blend_weights(rings[before].weights, rings[after].weights, t))
    return result


FaceFilter = Callable[[int, float], bool]
FaceMaterial = Callable[[int, float, str], str]


def build_loft(
    rings: list[Ring],
    segments: int,
    material: str,
    cap_start: bool = True,
    cap_end: bool = True,
    skip_face: Optional[FaceFilter] = None,
    face_material: Optional[FaceMaterial] = None,
    uv_tile: tuple[int, int] = (0, 0),
    uv_grid: int = 4,
) -> LoftResult:
    """ring 列から筒状 mesh を作る。

    skip_face(band, angle) が True を返す側面は生成しない (髪の顔部分の開口など)。
    face_material(band, angle, default) で面ごとの material を上書きできる。
    UV は周方向を u、進行方向を v として、uv_grid 分割の tile 内に収める。
    """
    if len(rings) < 2:
        raise ValueError("loft には 2 つ以上の ring が必要")
    if segments < 3:
        raise ValueError("segments は 3 以上")

    result = LoftResult()
    weights = interpolate_ring_weights(rings)
    ring_count = len(rings)

    for ring_index, ring in enumerate(rings):
        for i in range(segments):
            angle = TWO_PI * i / segments
            result.vertices.append(ring.point(angle))
            result.vertex_weights.append(dict(weights[ring_index]))

    def vid(ring_index: int, i: int) -> int:
        return ring_index * segments + (i % segments)

    tile_x, tile_y = uv_tile
    tile_size = 1.0 / uv_grid

    def uv(i: float, ring_index: float) -> tuple[float, float]:
        return (
            (tile_x + i / segments) * tile_size,
            (tile_y + ring_index / (ring_count - 1)) * tile_size,
        )

    for band in range(ring_count - 1):
        band_material = rings[band].material or material
        for i in range(segments):
            angle = TWO_PI * (i + 0.5) / segments
            if skip_face is not None and skip_face(band, angle):
                continue
            face_mat = band_material
            if face_material is not None:
                face_mat = face_material(band, angle, band_material)
            result.faces.append((vid(band, i), vid(band, i + 1), vid(band + 1, i + 1), vid(band + 1, i)))
            result.face_materials.append(face_mat)
            result.face_uvs.append([uv(i, band), uv(i + 1, band), uv(i + 1, band + 1), uv(i, band + 1)])

    def add_cap(ring_index: int, reverse: bool) -> None:
        ring = rings[ring_index]
        center_id = len(result.vertices)
        result.vertices.append(ring.center)
        result.vertex_weights.append(dict(weights[ring_index]))
        cap_material = rings[ring_index].material or material
        for i in range(segments):
            a, b = vid(ring_index, i), vid(ring_index, i + 1)
            if reverse:
                a, b = b, a
            result.faces.append((center_id, a, b))
            result.face_materials.append(cap_material)
            uv_center = uv(segments / 2.0, ring_index)
            result.face_uvs.append([uv_center, uv(i, ring_index), uv(i + 1, ring_index)])

    # 始端は進行方向の逆を向く。巻き方向を反転して外向き法線にする。
    if cap_start:
        add_cap(0, reverse=True)
    if cap_end:
        add_cap(ring_count - 1, reverse=False)

    return result


def angular_distance(a: float, b: float) -> float:
    """2 つの角度 (rad) の差の絶対値を [0, pi] で返す。"""
    d = (a - b) % TWO_PI
    return min(d, TWO_PI - d)


FRONT_ANGLE = 1.5 * math.pi  # -v 方向 (キャラクターの前方 -Y) に対応する角度


def gaussian_bulge(amplitude: float, centers: list[float], sigma: float) -> Callable[[float], tuple[float, float]]:
    """前方 (-v) へ膨らむ gaussian を複数中心で重ねる bulge 関数を返す。胸部に用いる。"""

    def bulge(angle: float) -> tuple[float, float]:
        total = 0.0
        for c in centers:
            d = angular_distance(angle, c)
            total += math.exp(-(d * d) / (2.0 * sigma * sigma))
        return (0.0, -amplitude * total)

    return bulge


def wave_bulge(amplitude: float, lobes: int, phase: float = 0.0) -> Callable[[float], tuple[float, float]]:
    """周方向に波打つ半径変位。髪の毛先の外ハネに用いる。"""

    def bulge(angle: float) -> tuple[float, float]:
        r = amplitude * math.cos(lobes * angle + phase)
        return (r * math.cos(angle), r * math.sin(angle))

    return bulge
