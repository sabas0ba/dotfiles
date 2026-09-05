"""素体を生成する。使い方: blender -b --python scripts/build_avatar.py -- --out build"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from avatar.build import main  # noqa: E402

if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    main(argv)
