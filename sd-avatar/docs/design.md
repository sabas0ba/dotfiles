# 設計

設定資料 (SD 素体アウトライン資料、SD キャラクター設定資料) を script で再現するための設計判断を記す。数値の実体は `avatar/spec.py` にある。

## 座標系と単位

- meter 単位。正面は -Y、上は +Z、キャラクターの左手側は +X (Blender の慣例)
- 頭部の高さ `HEAD_H` = 0.40 m を基準とし、各寸法は資料の比率に `h()` を掛けて求める
- 全高は約 2.42 `HEAD_H` = 0.97 m

## 素体

資料 1 の項目 4 (プロポーションガイド) と項目 5 (関節位置) を頭身比で写した。

| 部位 | 高さ (HEAD_H 単位) |
| --- | --- |
| 頭頂 | 2.43 |
| 顎 | 1.43 |
| 首の付け根 | 1.36 |
| 肩関節 | 1.30 |
| 腰 | 1.10 |
| 股関節 | 0.86 |
| 膝 | 0.45 |
| 足首 | 0.12 |
| 足底 | 0.00 |

各部位は断面の列を面で繋ぐ loft で作り、関節の内部で重ねる。頭部は横にやや広い楕円体を顎へ向けて絞る。手はミトン、足は丸みのあるブロックで、資料 1 の項目 6 に従う。素体と衣装には Catmull-Clark subdivision を 1 段適用し、髪と顔には適用しない。

腕は垂直から 20 度開いた A ポーズにする。Unity の Humanoid は T ポーズを基準に筋肉設定を補正するため、Unity 側で Pose > Enforce T-Pose を実行する。

## Armature

Unity Humanoid の必須 bone に Shoulder、Toes、Eye を加えた 25 本。名前は Unity の自動割り当てが認識する語 (UpperArm、LowerLeg など) に Blender の左右接尾辞 `.L` / `.R` を付けたものにする。Blender の X 軸 mirror 編集を使えるようにするためで、Unity は `.L` / `.R` を左右の識別子として扱う。

## Weight

heat weighting は重なり合う shell (衣装、髪) で失敗しやすいため使わず、`avatar/weights.py` で解析的に計算する。各部位の tag に weight 規則を対応付け、頂点を bone chain の折れ線へ射影し、弧長位置から関節の前後 `JOINT_BLEND` (0.02 m) で隣接 bone に滑らかに配分する。合計は 1 に正規化する。

| 規則 | 対象 |
| --- | --- |
| `bone:Head` | 頭部、顔、髪、ピアス |
| `chain:torso` | 胴、セーター、パンツの腰 |
| `chain:arm.L` など | 腕、手、袖 |
| `chain:leg.L` など | 脚、足、パンツの脚、ブーツ |

subdivision 後の頂点に規則を適用するため、tag は vertex group として持ち越し、最終形状の頂点位置から weight を計算する。

## 顔と shape key

顔パーツは頭部前面の表面に投影した板で構成し、重なり順を表面からの浮かせ量で決める。各パーツの「設計形状」を `avatar/face.py` が返し、`avatar/shapekeys.py` が rest 状態 (Basis) と各 key の形状を導出する。

- 口は全開の楕円を設計形状とし、Basis では高さを 8 % に潰す。viseme は横幅と開口の倍率 (`spec.VISEMES`) で表す
- ドット目は Basis で表面の内側 (+Y 側) へ平行移動して隠し、`DotEyes` で表面に出す。アニメ目は逆に `DotEyes` で隠す。隠す操作が平行移動なので、`DotEyes` と `Blink` を同時に使っても差分が相殺されない
- 表情は目の潰し (Blink)、弧 (Smile)、拡大 (Surprised)、眉の傾き (Angry, Sad)、口の口角 (bend) の組み合わせで定義する

shape key の一覧は `spec.SHAPE_KEYS` にあり、`scripts/check_model.py` が存在を検査する。

## 髪

資料 2 の項目 4 のパーツ分解に対応させる。

- 後ろ髪: 頭部楕円体の 1.07〜1.13 倍の殻。前面は生え際で止め、側面から後ろは顎の高さまで下げる。下端に 9 周期の波を与えて毛先の房を表す。solidify で厚みを付ける
- 前髪 5 房 (片側)、サイド髪 2 房 (片側)、アホ毛 1 房: 頭部表面に沿う Catmull-Rom spline に沿った tube。頭部中心からの放射方向を断面の法線に使い、捩れを防ぐ
- 毛先の gradient: 高さを UV の V に写し、`textures/hair_gradient.png` (上端が髪の基本色、下端が青) を貼る。V はちょうど 0 や 1 にせず、texture の wrap で反対側へ回り込まないようにする。Unity 側でも Wrap Mode を Clamp にする

## 衣装

素体の各部位を外側へ offset した shell。セーターは肩を張らせた箱型で襟を顎の下まで立てる。袖はふくらみを持たせ手首で絞る。ブーツは足を覆う部分と折り返しのある筒で構成する。ピアスは八面体。

## 材質と配色

資料 2 の項目 7 の palette を `spec.PALETTE` に置き、材質は Principled BSDF の base color だけを持つ。Unity 側で lilToon などの toon shader に差し替える前提のため、Blender 側で陰影表現を作り込まない。

## 面数

三角面数は VRChat PC の Excellent 帯 (32,000 以下) を上限とし、`spec.MAX_TRIANGLES` で検査する。FBX では Body、Hair、Clothes を 1 つの skinned mesh に結合するため、skinned mesh は 2 つになる。材質数 (11) は Excellent の条件 (4 以下) を超えるため、Excellent を狙う場合は palette texture への統合が必要になる。

## 既知の制約

- 手続き的生成による block-out であり、髪の面構成、目の描き込み、衣装の皺は手作業で仕上げる
- 目は平面の板で Head bone に追従する。Eye bone は存在するが目の mesh を動かさないため、VRChat の Eye Look は bone ではなく shape key で構成するか、無効にする
- 素体は衣装の下にも残る。貫通が問題になる場合は Blender で隠れる面を削除する
