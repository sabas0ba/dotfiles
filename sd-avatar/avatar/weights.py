"""bone chain への射影による解析的な weight 計算。

heat weighting は重なり合う shell (衣装、髪) で失敗しやすいため使わない。各頂点を
指定された chain の折れ線へ射影し、弧長位置から関節付近で隣接 bone に滑らかに配分する。
"""

from __future__ import annotations

from avatar import spec
from avatar.geometry import Vec, dot, length, smoothstep, sub


def _closest_on_segment(p: Vec, a: Vec, b: Vec) -> tuple[float, float]:
    """点 p から線分 ab への最近点の媒介変数 t (0..1) と距離を返す。"""
    ab = sub(b, a)
    ab2 = dot(ab, ab)
    if ab2 == 0.0:
        return 0.0, length(sub(p, a))
    t = min(1.0, max(0.0, dot(sub(p, a), ab) / ab2))
    q = (a[0] + ab[0] * t, a[1] + ab[1] * t, a[2] + ab[2] * t)
    return t, length(sub(p, q))


def chain_arclength_position(p: Vec, chain: list[str]) -> tuple[float, float]:
    """chain の折れ線上で p に最も近い位置の弧長と、そこまでの距離を返す。

    最初の bone より根元側の点は弧長 0 未満、最後の bone より先は総弧長を超える値になる
    ように、端の線分は延長して扱う。
    """
    best_s = 0.0
    best_d = float("inf")
    cumulative = 0.0
    count = len(chain)
    for i, name in enumerate(chain):
        bone = spec.BONE_BY_NAME[name]
        seg_len = length(sub(bone.tail, bone.head))
        t, d = _closest_on_segment(p, bone.head, bone.tail)
        s = cumulative + t * seg_len
        # 端の線分は無限に延長し、外側の点にも順序付けられた弧長を与える。
        if i == 0 and t == 0.0:
            s = cumulative - _overshoot(p, bone.head, bone.tail)
        if i == count - 1 and t == 1.0:
            s = cumulative + seg_len + _overshoot(p, bone.tail, bone.head)
        if d < best_d:
            best_d = d
            best_s = s
        cumulative += seg_len
    return best_s, best_d


def _overshoot(p: Vec, end: Vec, other: Vec) -> float:
    """線分の端 end から外側へ、p を軸方向へ射影した距離 (0 以上)。"""
    axis = sub(end, other)
    n = length(axis)
    if n == 0.0:
        return 0.0
    return max(0.0, dot(sub(p, end), axis) / n)


def chain_weights(p: Vec, chain: list[str], blend: float = spec.JOINT_BLEND) -> dict[str, float]:
    """chain 上の各 bone への weight。合計は 1 になる。"""
    s, _ = chain_arclength_position(p, chain)
    boundaries = [0.0]
    for name in chain:
        bone = spec.BONE_BY_NAME[name]
        boundaries.append(boundaries[-1] + length(sub(bone.tail, bone.head)))
    weights: dict[str, float] = {}
    count = len(chain)
    for i, name in enumerate(chain):
        start = boundaries[i]
        end = boundaries[i + 1]
        w_in = 1.0 if i == 0 else smoothstep(start - blend, start + blend, s)
        w_out = 1.0 if i == count - 1 else 1.0 - smoothstep(end - blend, end + blend, s)
        w = w_in * w_out
        if w > 1e-6:
            weights[name] = w
    total = sum(weights.values())
    if total == 0.0:
        return {chain[0]: 1.0}
    return {k: v / total for k, v in weights.items()}


def nearest_chain(p: Vec, chains: list[str]) -> str:
    """p に最も近い chain の名前。"""
    best = chains[0]
    best_d = float("inf")
    for name in chains:
        _, d = chain_arclength_position(p, spec.CHAINS[name])
        if d < best_d:
            best_d = d
            best = name
    return best


def weights_for(p: Vec, rule: str) -> dict[str, float]:
    """tag に対応する weight 規則 rule を適用する。

    rule は "bone:<name>" (固定)、"chain:<chain>" (単一 chain)、
    "nearest:<chain>,<chain>,..." (最寄りの chain) のいずれか。
    """
    kind, _, arg = rule.partition(":")
    if kind == "bone":
        return {arg: 1.0}
    if kind == "chain":
        return chain_weights(p, spec.CHAINS[arg])
    if kind == "nearest":
        chain = nearest_chain(p, arg.split(","))
        return chain_weights(p, spec.CHAINS[chain])
    raise ValueError(f"未知の weight 規則: {rule}")
