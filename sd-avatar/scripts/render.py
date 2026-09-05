"""生成した .blend から確認用の画像を書き出す。Blender から実行する。

    blender -b --python-exit-code 1 -P scripts/render.py -- \
        --blend build/avatar.blend --out build/render
"""

from __future__ import annotations

import argparse
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

EXPRESSION_SETS = [
    "Basis",
    "Wink",
    "Smile",
    "Angry",
    "Sad",
    "Surprised",
    "DotEyes",
    "DotEyes+Blink",
]

VISEME_SETS = ["vrc.v_sil", "vrc.v_aa", "vrc.v_e", "vrc.v_ih", "vrc.v_oh", "vrc.v_ou"]


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description="確認用の render を生成する")
    parser.add_argument("--blend", default="build/avatar.blend")
    parser.add_argument("--out", default="build/render")
    parser.add_argument(
        "--only",
        choices=["turnaround", "expressions", "visemes"],
        help="指定した画像だけを生成する",
    )
    return parser.parse_args(argv)


def main() -> None:
    args = parse_args()
    import bpy

    from avatar import render

    out = os.path.abspath(args.out)
    os.makedirs(out, exist_ok=True)
    blend = os.path.abspath(args.blend)

    jobs = {
        "turnaround": lambda: render.render_turnaround(os.path.join(out, "turnaround.png")),
        "expressions": lambda: render.render_expressions(
            os.path.join(out, "expressions.png"), EXPRESSION_SETS
        ),
        "visemes": lambda: render.render_expressions(os.path.join(out, "visemes.png"), VISEME_SETS),
    }
    for name, job in jobs.items():
        if args.only and args.only != name:
            continue
        # 各 render は scene を書き換えるため、毎回 .blend を開き直す。
        bpy.ops.wm.open_mainfile(filepath=blend)
        job()
        print(f"render 完了: {name}")


if __name__ == "__main__":
    main()
