"""モデルを生成して .blend と FBX を書き出す。Blender から実行する。

blender -b --python-exit-code 1 -P scripts/build.py -- --out build
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
    parser = argparse.ArgumentParser(description="SD avatar を生成する")
    parser.add_argument("--out", default="build", help="出力ディレクトリ")
    parser.add_argument("--no-merge", action="store_true", help="FBX で mesh を結合しない")
    return parser.parse_args(argv)


def main() -> None:
    args = parse_args()
    from avatar import build, export

    out = os.path.abspath(args.out)
    build.build_all(os.path.join(out, "textures"))
    build.save_blend(os.path.join(out, "avatar.blend"))
    export.export_fbx(os.path.join(out, "avatar.fbx"), merge=not args.no_merge)
    print(f"生成完了: {out}")


if __name__ == "__main__":
    main()
