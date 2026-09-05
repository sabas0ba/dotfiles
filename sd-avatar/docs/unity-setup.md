# Unity と VRChat SDK の手順

`make build` で生成した `build/avatar.fbx` と `build/textures/hair_gradient.png` を VRChat アバターとして設定する手順。この手順は本リポジトリの環境では自動化できないため、手作業で行う。

## 前提

- VRChat Creator Companion で作成した Avatar project (VRChat SDK - Avatars 3.0)
- toon shader (lilToon など)。導入する場合は VCC の package として版を固定する

## 1. 取り込み

1. `avatar.fbx` と `avatar.fbm/hair_gradient.png` (または `textures/hair_gradient.png`) を `Assets/SdAvatar/` に置く
2. FBX の Import Settings
   - Model: Scale Factor 1、Convert Units 有効、Read/Write 有効 (Blend Shape を編集する場合)、Legacy Blend Shape Normals 有効
   - Rig: Animation Type を Humanoid、Avatar Definition を Create From This Model
   - Materials: Material Creation Mode を Standard、Location を Use External Materials (Legacy) にして Extract Materials
3. `hair_gradient.png` の Wrap Mode を Clamp、Filter Mode を Bilinear にする

## 2. Humanoid の確認

Rig タブの Configure で次を確認する。

- Hips, Spine, Chest, Neck, Head、四肢の bone が自動で割り当てられている。`.L` / `.R` は左右として認識される
- Eye.L / Eye.R は Head 配下の任意 bone。割り当てても目の mesh は動かないため、未割り当てのままでよい
- Pose > Enforce T-Pose を実行し Apply する。腕は A ポーズで生成しているため補正が入る

## 3. 材質

Extract した材質の shader を toon shader に変更し、`avatar/spec.py` の palette を基準に色を設定する。

| 材質 | 用途 | 備考 |
| --- | --- | --- |
| Skin | 素体 | |
| Hair | 髪 | `hair_gradient.png` を Main Texture に指定する。Cull を Off にすると殻の内側も描画される |
| Eye, EyeLight, EyeDark, Highlight | 目 | Highlight は unlit または emission |
| Brow, Mouth | 眉、口 | |
| Cloth, Boots | 衣装 | |
| Earring | ピアス | 透過や emission で結晶感を出す |

## 4. Avatar Descriptor

Scene に FBX を配置し、root に VRC Avatar Descriptor を追加する。

- View Position: 目の高さ。`spec.VIEW_POSITION` (x 0、y 0.724、z 0.168) を目安にする。Unity の座標では y が高さ、z が前方向
- Lip Sync: Viseme Blend Shape、Face Mesh に `Face` を指定する。`vrc.v_*` の名前で自動割り当てされる
- Eye Look: 目の mesh が bone に追従しないため、Eyelids を Blendshapes にして Blink を指定し、Eyes の bone は未設定にする。または Eye Look 自体を無効にする
- Playable Layers と Expression Menu: 表情 (Wink, Smile, Angry, Sad, Surprised, DotEyes) は Face の Blend Shape として FX layer から制御する。DotEyes は他の表情と同時に有効にできる

## 5. 検証

- VRChat SDK の Build & Test で Performance Rank を確認する。三角面数は約 30k、skinned mesh は 2、材質は 11 で、PC では Good、Quest では Poor 帯になる
- Avatar 3.0 Emulator (Lyuma) などで viseme と表情の動作を確認する

## 6. 調整の反映

Blender で手作業の調整を行う場合は `build/avatar.blend` を複製して編集し、FBX を書き出す際は `avatar/export.py` と同じ設定 (Forward -Z、Up Y、Apply Scalings FBX All、Add Leaf Bones 無効、Only Deform Bones 有効) を使う。script 側の寸法や配色を変えた場合は `make build` で再生成する。
