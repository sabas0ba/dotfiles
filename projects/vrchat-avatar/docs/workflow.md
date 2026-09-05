# 制作手順

## 1. 素体の生成 (headless)

dotfiles の `vrchat` profile に入り、本 project で生成と検証を行う。

```bash
nix develop /path/to/dotfiles#vrchat
cd /path/to/vrchat-avatar
make check
make preview
```

`make check` は構文検査、生成、FBX の再読込による検査を順に実行する。検査項目は `scripts/validate_fbx.py` の docstring にある。`make preview` は `build/preview/` に正面、3/4、側面、背面、顔の近接の 5 枚を描画する。GPU と OpenGL context を持たない環境でも動くよう、Cycles の CPU 描画を使う。

寸法や配色を変える場合は `avatar/params.py` だけを編集し、`make check` で再生成する。断面の追加や部品の変更は `avatar/body.py` と `avatar/hair.py` の ring 定義で行う。

## 2. Blender GUI での作り込み

`build/avatar.blend` を開く。生成物は次の状態にある。

- `Body` と `Hair` の 2 つの mesh object。いずれも `Armature` の子で、Armature modifier と bone 名の vertex group を持つ
- subdivision は適用済み。shape key は `Body` に設定済み
- material は base color だけを持つ

GUI で行う作業と留意点:

- 顔: 鼻、口、瞼、まつ毛を造形する。参考資料 `reference/head-hair-sheet.png` の 05 (素体) と 06 (耳の位置) を基準にする。shape key を持つ mesh は頂点数を変える編集が制限されるため、顔の造形を先に済ませてから shape key を作り直す。既存の shape key は同名で作り直すと Unity 側の設定を変えずに置き換えられる
- 髪: 生成物は 1 つの殻である。参考資料の 02 (前髪)、03 (サイドロック)、04 (後ろ髪) に従い、房ごとの mesh に分けて作り直す。Physbone を使う場合は房ごとに bone を追加する
- 体: 各部品は重なり合う殻であり、関節部で交差している。retopology を行う場合は bone weight を保つため Data Transfer modifier で weight を転写する
- 衣服: 生成物は material の割り当てだけである。衣服 mesh を別 object として作り、`Body` と同じ armature に bind する

生成し直すと `build/` は上書きされる。GUI での編集結果は `build/` の外 (例: `work/avatar-edit.blend`) に保存し、必要なら git 管理に含める。

## 3. Unity への取り込み

VRChat Creator Companion で Avatar project を作り、`build/avatar.fbx` を Assets に置く。

1. Model の Import Settings で Rig を Humanoid にし、Configure で bone の mapping を確認する。bone 名は HumanBodyBones と同一のため、自動 mapping で一致するはずである。T-pose の警告が出る場合は Enforce T-Pose を適用する
2. Material を作り、`docs/spec.md` の色を設定する (FBX の base color は初期値として読み込まれる)
3. Avatar Descriptor を追加し、`docs/spec.md` の「VRChat 側の設定で必要な作業」を行う
4. VRChat SDK の Build & Test で確認する

## 4. 独立リポジトリへの移設

本 project は dotfiles の `projects/vrchat-avatar/` に暫定的に置いている。専用リポジトリを作成した後、履歴ごと移設する。

```bash
cd /path/to/dotfiles
git subtree split --prefix=projects/vrchat-avatar -b vrchat-avatar-split
cd /path/to/vrchat-avatar    # 新しい空のリポジトリ
git pull /path/to/dotfiles vrchat-avatar-split
```

移設後は dotfiles 側の `projects/vrchat-avatar/` を削除し、README の dotfiles への参照 (profile の取得方法) を残す。
