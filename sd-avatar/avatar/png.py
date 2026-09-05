"""依存なしの PNG 書き出しと gradient texture の生成。

Blender の image API は byte / float buffer で色空間の扱いが異なるため、sRGB の値を
そのまま書き込める自前の encoder を使い、出力を決定的にする。
"""

from __future__ import annotations

import struct
import zlib

from avatar import spec


def srgb_hex_to_rgb8(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16)


def srgb_to_linear(c: float) -> float:
    if c <= 0.04045:
        return c / 12.92
    return ((c + 0.055) / 1.055) ** 2.4


def hex_to_linear_rgba(value: str) -> tuple[float, float, float, float]:
    r, g, b = srgb_hex_to_rgb8(value)
    return srgb_to_linear(r / 255.0), srgb_to_linear(g / 255.0), srgb_to_linear(b / 255.0), 1.0


def write_png(path: str, width: int, height: int, rows: list[bytes]) -> None:
    """RGB 8bit の PNG を書く。rows は上から順に width*3 byte の行。"""
    if len(rows) != height or any(len(r) != width * 3 for r in rows):
        raise ValueError("行データの寸法が不正")

    def chunk(kind: bytes, data: bytes) -> bytes:
        body = kind + data
        return (
            struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)
        )

    raw = b"".join(b"\x00" + r for r in rows)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def gradient_rgb8(v: float, stops: list[tuple[float, str]]) -> tuple[int, int, int]:
    """位置 v (0..1) の色を stops (位置, sRGB hex) から線形補間する。"""
    v = min(1.0, max(0.0, v))
    prev_pos, prev_hex = stops[0]
    for pos, value in stops[1:]:
        if v <= pos:
            t = 0.0 if pos == prev_pos else (v - prev_pos) / (pos - prev_pos)
            a = srgb_hex_to_rgb8(spec.PALETTE[prev_hex])
            b = srgb_hex_to_rgb8(spec.PALETTE[value])
            return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))  # type: ignore[return-value]
        prev_pos, prev_hex = pos, value
    return srgb_hex_to_rgb8(spec.PALETTE[stops[-1][1]])


def write_hair_gradient(path: str, width: int = 8, height: int = 256) -> None:
    """V=1 (上端の行) が頭頂側、V=0 (下端の行) が毛先になる gradient texture。"""
    rows = []
    for row in range(height):
        v = 1.0 - row / (height - 1)
        r, g, b = gradient_rgb8(v, spec.HAIR_GRADIENT_STOPS)
        rows.append(bytes((r, g, b)) * width)
    write_png(path, width, height, rows)
