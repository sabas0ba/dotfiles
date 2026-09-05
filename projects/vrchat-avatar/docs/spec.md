# キャラクター仕様と VRChat 向け要件

## 参考資料の読み取り

`reference/body-sheet.png` (モデリングとリギング用のパートリファレンス) と `reference/head-hair-sheet.png` (ヘッドとヘアーのリファレンス) から、次の項目を数値化した。数値は `avatar/params.py` の `Proportions` にある。

| 項目 | 資料の記述 | 採用値 |
| --- | --- | --- |
| 身長 | 高め | 1.68 m (`head_top`。`height` は同値を返す property) |
| 頭身 | プロポーション図から約 7 頭身 | 頭部高さ 0.235 m |
| 体型 | スレンダー、健康的でしなやかな筋肉量 | ウエスト半径 x 0.098 / y 0.082 m |
| バスト | やや大きめ | 胸部前方への膨らみ 0.060 m (gaussian 2 中心) |
| 肩幅 | 狭め、腕の付け根はやや内側 | 肩関節 x = ±0.175 m |
| 首 | 細め、長め | 半径 x 0.042 / y 0.048 m、首の付け根 1.38 m |
| 脚 | 長め | 股下 0.775 m、膝 0.44 m |
| 骨盤 | やや前傾 | 骨盤 ring の中心を +Y へ 5 mm |
| 目 | 大きめ、瞳は桃色 | 半径 0.030 m の楕円体 (奥行は 0.5 倍)、中心 x = ±0.044 m、y = -0.066 m、高さ 1.545 m |
| 髪 | ミディアムボブ、フルバング、外ハネ、インナーハイライト | 毛先 1.40 m、前髪下端 1.572 m、外ハネ 0.045 m |

配色は資料のカラーパレットに従い、`avatar/params.py` の `Palette` に置く。

| material | 用途 | 色 (sRGB 近似) |
| --- | --- | --- |
| Skin | 肌 | #F6E3DB |
| Underwear | スポーツブラとショーツ | #C7C7CC |
| HairMain | 髪のメインカラー | #F6ECF0 |
| HairShadow | 髪のシャドウ | #DAC6D5 |
| HairInner | インナーハイライト (ラベンダーブルー) | #A8B3E6 |
| EyeLine | アイライン、瞳孔 | #29292B |
| Iris | 瞳 | #C96B87 |
| Sclera | 白目 | #FBFBFC |

## 座標系と姿勢

- Blender の右手系 (Z 上、-Y 前方)。キャラクターは -Y を向き、キャラクターの左が +X
- 単位は m。FBX は `FBX_SCALE_ALL` で書き出し、Unity で scale factor 1 として読む
- 姿勢は T-pose。手のひらは下 (-Z) を向き、親指は前方やや外側を向く

## Armature

bone 名は Unity の HumanBodyBones と同一にし、Avatar 設定の自動 mapping に依存しない。

| 区分 | bone |
| --- | --- |
| 必須 | Hips, Spine, Chest, Neck, Head, Left/Right UpperArm, LowerArm, Hand, UpperLeg, LowerLeg, Foot |
| 推奨 | Left/Right Eye, Shoulder, Toes, 各指の Proximal / Intermediate / Distal (Thumb, Index, Middle, Ring, Little) |

UpperChest は設定しない。Hips が armature の唯一の root である。bone の位置は `avatar/rig.py` が `Proportions` から導出し、`avatar/body.py` の bone weight と同じ数値を参照する。

## Shape key

Body mesh に次の shape key を置く。VRChat SDK3 の Avatar Descriptor が名前で自動検出する。

- Viseme: `vrc.v_sil`, `vrc.v_pp`, `vrc.v_ff`, `vrc.v_th`, `vrc.v_dd`, `vrc.v_kk`, `vrc.v_ch`, `vrc.v_ss`, `vrc.v_nn`, `vrc.v_rr`, `vrc.v_aa`, `vrc.v_e`, `vrc.v_ih`, `vrc.v_oh`, `vrc.v_ou`
- Eyelids (Blendshapes): `Blink`, `Blink_L`, `Blink_R`, `LookingUp`, `LookingDown`

素体には口と瞼の形状が無いため、viseme は口周辺の頂点を「開く、横に広げる、すぼめる、前に出す」の 4 成分で変位させた近似、まばたきは眼球を上下方向に潰した近似である。`LookingUp` と `LookingDown` は変位を持たない placeholder である。GUI で顔を作り込む際は同名の shape key を作り直す。

## Performance rank の目安

`scripts/validate_fbx.py` は三角形数を次の閾値と比較する。値は VRChat の [Avatar Performance Ranking System](https://creators.vrchat.com/avatars/avatar-performance-ranking-system/) に基づくが、本 project の作成時点で再確認していない。上限は同ページの現行値で確認すること。bone 数、material 数、skinned mesh 数などの他の指標は検査しない。

| 対象 | Excellent | Good | Medium | Poor |
| --- | --- | --- | --- | --- |
| PC | 32,000 | 70,000 | - | - |
| Quest (Android) | 7,500 | 10,000 | 15,000 | 20,000 |

## VRChat 側の設定で必要な作業

生成物には含まれず、Unity 上で行う。

- Avatar Descriptor の View Position: 両目の中間 (x 0, y 約 1.545, z 約 -0.06 を Unity の座標系に変換した位置)
- Eye Look: `LeftEye` / `RightEye` を割り当て、回転範囲を調整する
- Lip Sync: Viseme Blend Shape を選択し、Body mesh を指定する
- Physbone (髪、胸部): 必要に応じて設定する。生成物には含まない
