"""髪。ミディアムボブ、フルバング、外ハネのサイドロック、内側のインナーハイライト。

前髪の下端 (bangs_bottom) を境に 2 つの loft で構成する。下部は内側の層 (頭部表面
付近から毛先へ下る) と外側の層 (毛先から前髪の下端へ上る) を連続させた中空の殻で、
顔の前面を開口する。上部は前髪の下面 (内側から外側へ向かう lip) と頭頂までの外側の
層である。開口の縁、内側の層、前髪の下面に HairInner を割り当てる。参考資料の
「インナーハイライトは側頭部の内側と下層に配置」に対応する。
"""

from __future__ import annotations

import math

from .loft import FRONT_ANGLE, LoftResult, Ring, angular_distance, build_loft, wave_bulge
from .mesh_builder import MeshBuilder
from .params import AvatarSpec, Proportions

HEAD_WEIGHT = {"Head": 1.0}


INNER_RING_COUNT = 3


def boundary_rings(p: Proportions) -> tuple[Ring, Ring]:
    """前髪の下端の高さにある 2 つの ring (頭部表面に沿う内側、殻の外側) を返す。

    上部と下部の loft はこの 2 つの ring を共有し、境界が一致する。
    """
    t = p.hair_thickness
    inner = Ring((0, 0.003, p.bangs_bottom), 0.152, 0.102, ry_front=0.076, weights=HEAD_WEIGHT)
    outer = Ring((0, 0.000, p.bangs_bottom), 0.184 + t, 0.130 + t, ry_front=0.094, weights=HEAD_WEIGHT)
    return inner, outer


def lower_rings(p: Proportions) -> list[Ring]:
    """前髪の下端から毛先までの殻。内側の層を下り、毛先で折り返して外側の層を上る。"""
    t = p.hair_thickness
    inner_top, outer_top = boundary_rings(p)
    bottom = p.hair_bottom
    wave = wave_bulge(p.hair_wave, 5, phase=0.4)
    wave_inner = wave_bulge(p.hair_wave * 0.6, 5, phase=0.4)
    return [
        inner_top,
        Ring((0, 0.005, 1.470), 0.132, 0.095, ry_front=0.072),
        Ring((0, 0.008, bottom + 0.004), 0.140 + p.hair_flare * 0.6, 0.100, ry_front=0.080, bulge=wave_inner),
        Ring((0, 0.010, bottom), 0.140 + p.hair_flare + t, 0.110 + t, ry_front=0.090, bulge=wave),
        Ring((0, 0.010, 1.440), 0.165 + t, 0.125 + t, ry_front=0.095, bulge=wave_bulge(p.hair_wave * 0.5, 5, phase=0.4)),
        Ring((0, 0.005, 1.490), 0.170 + t, 0.128 + t, ry_front=0.092),
        Ring((0, 0.000, 1.530), 0.178 + t, 0.128 + t, ry_front=0.092),
        outer_top,
    ]


def upper_rings(p: Proportions) -> list[Ring]:
    """前髪の下面 (内側から外側へ向かう lip) と、頭頂までの外側の層。"""
    t = p.hair_thickness
    inner_top, outer_top = boundary_rings(p)
    return [
        inner_top,
        outer_top,
        Ring((0, 0.000, 1.605), 0.184 + t, 0.128 + t, ry_front=0.093),
        Ring((0, 0.005, 1.635), 0.172 + t, 0.118 + t, ry_front=0.086),
        Ring((0, 0.010, 1.662), 0.140 + t, 0.098 + t, ry_front=0.074),
        Ring((0, 0.010, 1.688), 0.090 + t, 0.064 + t, ry_front=0.050),
        Ring((0, 0.010, p.head_top + t), 0.030, 0.022, ry_front=0.018, weights=HEAD_WEIGHT),
    ]


def build_hair(spec: AvatarSpec) -> MeshBuilder:
    p = spec.proportions
    opening = math.radians(p.face_opening_deg)
    segments = spec.resolution.hair

    def in_face_sector(angle: float, margin: float = 0.0) -> bool:
        return angular_distance(angle, FRONT_ANGLE) < opening + margin

    def skip_lower(_band: int, angle: float) -> bool:
        # 前髪の下端より下の前面は開口し、顔を露出させる。
        return in_face_sector(angle)

    def lower_material(band: int, angle: float, default: str) -> str:
        # 内側の層と開口の縁 (サイドロックの内側) に highlight を置き、毛先の外側は shadow にする。
        if band < INNER_RING_COUNT or in_face_sector(angle, margin=0.25):
            return "HairInner"
        if band == INNER_RING_COUNT:
            return "HairShadow"
        return default

    def upper_material(band: int, _angle: float, default: str) -> str:
        # band 0 は前髪の下面。下から見える面であり、インナーハイライトの色にする。
        return "HairInner" if band == 0 else default

    lower: LoftResult = build_loft(
        lower_rings(p),
        segments,
        "HairMain",
        cap_start=False,
        cap_end=False,
        skip_face=skip_lower,
        face_material=lower_material,
        uv_tile=(2, 2),
    )
    upper: LoftResult = build_loft(
        upper_rings(p),
        segments,
        "HairMain",
        cap_start=False,
        cap_end=True,
        face_material=upper_material,
        uv_tile=(3, 2),
    )
    builder = MeshBuilder()
    builder.add(lower)
    builder.add(upper)
    return builder
