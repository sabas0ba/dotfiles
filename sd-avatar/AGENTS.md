# AGENTS.md

本リポジトリで作業する coding agent 向けの指示。利用者共通規約 ([sabas0ba/dotfiles](https://github.com/sabas0ba/dotfiles) の `home/.codex/AGENTS.md`) と併用し、競合時は利用者の明示的な指示、本ファイル、共通規約の順に優先する。

## 環境

Nix 開発シェル (`nix develop`) 内で作業する。Blender、Python、ruff は flake が固定する版を使い、開発シェルの外へツールを導入しない。生成 script に Blender 同梱以外の Python package を追加しない。

## 変更の原則

- 寸法、bone、配色、shape key の一覧は `avatar/spec.py` だけに置く。他の module に数値を直接書かない
- mesh 生成と weight 計算は bpy 非依存に保ち、`tests/` で unit test する。Blender 依存の処理は `bl_*.py`、`build.py`、`export.py`、`render.py` に限定する
- 生成物 (`build/`) は commit しない。文書に載せる画像は `make render` の結果を `docs/images/` に置く
- 三角面数の上限 (`spec.MAX_TRIANGLES`) を超える変更を入れない。`make verify` が検査する

## 検証

変更後は次を実行する。

```bash
make check
```

形状に関わる変更は `make render` で画像を確認し、変更前後の差を PR に記載する。

## 承認が必要な操作

- flake input の更新 (Blender の版が変わる)
- 依存の追加
