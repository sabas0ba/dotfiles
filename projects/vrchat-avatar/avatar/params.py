"""キャラクターの寸法と配色の単一情報源。

参考資料 (reference/) の記述を数値化したもの。身長を 1.68 m とし、他の寸法は
頭身 (約 7 頭身) とシートの注記 (スレンダー、狭い肩幅、細い首、長い脚、やや大きめの
バスト) から比率で決めている。数値を変える場合は本ファイルだけを編集する。

座標系は Blender の右手系 (Z 上、-Y 前方) で、キャラクターは -Y を向く。
キャラクターの左は +X である。
"""

from dataclasses import dataclass, field


@dataclass(frozen=True)
class Proportions:
    # 頭部。上端 (head_top) が身長であり、顎先が head_bottom。
    head_top: float = 1.68
    head_bottom: float = 1.445
    head_width: float = 0.165  # 最大幅の半径 (x)
    head_depth: float = 0.100  # 最大奥行の半径 (y)
    eye_level: float = 1.545
    eye_spacing: float = 0.044  # 目の中心の x
    eye_center_y: float = -0.066  # 目の中心の y。顔の前面 (約 -0.075) のやや後ろ
    eye_radius: float = 0.030
    eye_depth_scale: float = 0.5  # 奥行 (y) 方向の縮小率
    brow_level: float = 1.575
    mouth_level: float = 1.478

    # 首。細く長め。
    neck_base: float = 1.380
    neck_rx: float = 0.042
    neck_ry: float = 0.048

    # 肩と腕 (T-pose)。肩幅は狭め。
    shoulder_z: float = 1.360
    shoulder_x: float = 0.175
    elbow_x: float = 0.455
    wrist_x: float = 0.700
    knuckle_x: float = 0.785
    finger_tip_x: float = 0.875
    upper_arm_r: float = 0.043
    elbow_r: float = 0.034
    forearm_r: float = 0.037
    wrist_rx: float = 0.026
    wrist_ry: float = 0.020

    # 胴体。くびれを強調し、骨盤はやや前傾。
    chest_top: float = 1.320
    bust_apex: float = 1.205
    under_bust: float = 1.135
    waist: float = 1.030
    hip: float = 0.900
    crotch: float = 0.775
    chest_rx: float = 0.130
    chest_ry: float = 0.095
    bust_bulge: float = 0.060
    bust_half_spacing: float = 0.065
    under_bust_rx: float = 0.118
    under_bust_ry: float = 0.088
    waist_rx: float = 0.098
    waist_ry: float = 0.082
    hip_rx: float = 0.160
    hip_ry: float = 0.112

    # 脚。長め。
    leg_x: float = 0.085
    knee_z: float = 0.440
    ankle_z: float = 0.075
    thigh_r: float = 0.078
    knee_r: float = 0.052
    calf_z: float = 0.330
    calf_r: float = 0.058
    ankle_r: float = 0.032

    # 足。踵からつま先まで。
    foot_length: float = 0.230
    foot_heel: float = 0.050
    foot_height: float = 0.070
    foot_width: float = 0.042

    # 手。手のひらは扁平、指は 3 関節。
    palm_half_width: float = 0.040
    palm_thickness: float = 0.014
    finger_r: float = 0.008
    finger_spread: float = 0.017

    # 髪。ミディアムボブ、フルバング、外ハネのサイドロック。
    hair_thickness: float = 0.022
    hair_bottom: float = 1.400
    hair_flare: float = 0.045
    hair_wave: float = 0.012
    bangs_bottom: float = 1.572
    face_opening_deg: float = 62.0

    @property
    def height(self) -> float:
        """身長。頭頂の高さと同一であり、独立した値を持たせて geometry と食い違わせない。"""
        return self.head_top


@dataclass(frozen=True)
class Palette:
    """参考資料のカラーパレット (RGB 0-1)。"""

    skin: tuple = (0.965, 0.890, 0.860, 1.0)
    underwear: tuple = (0.780, 0.780, 0.800, 1.0)
    hair_main: tuple = (0.965, 0.925, 0.940, 1.0)
    hair_shadow: tuple = (0.855, 0.775, 0.835, 1.0)
    hair_inner: tuple = (0.660, 0.700, 0.900, 1.0)
    eye_line: tuple = (0.160, 0.160, 0.170, 1.0)
    iris: tuple = (0.790, 0.420, 0.530, 1.0)
    sclera: tuple = (0.985, 0.985, 0.990, 1.0)


@dataclass(frozen=True)
class MeshResolution:
    """各 loft の周方向分割数。subdivision 前の値。"""

    torso: int = 32
    head: int = 32
    limb: int = 16
    finger: int = 8
    eye: int = 16
    hair: int = 40
    subdivision_levels: int = 1


@dataclass(frozen=True)
class AvatarSpec:
    proportions: Proportions = field(default_factory=Proportions)
    palette: Palette = field(default_factory=Palette)
    resolution: MeshResolution = field(default_factory=MeshResolution)


DEFAULT_SPEC = AvatarSpec()
