# 再現性

外部の成果物はすべて一意に固定する。タグやブランチ名のみによる参照は固定とみなさない。

| 対象 | 固定方法 | 定義箇所 |
| --- | --- | --- |
| nixpkgs | 40 桁の rev + `flake.lock` の narHash | `flake.nix` |
| home-manager | 40 桁の rev + `flake.lock` の narHash | `flake.nix` |
| NixOS-WSL | 40 桁の rev + `flake.lock` の narHash | `flake.nix` |
| WSL の配布イメージ | バージョン + URL + sha256 | `scripts/wsl-bootstrap.ps1` |
| ツール一式 | 上記 nixpkgs から解決 | `nix/packages.nix` |
| ベースイメージ | タグ + ダイジェスト (`@sha256:...`) | `Dockerfile` |
| GitHub Actions | コミット SHA | `.github/workflows/` |
| CI ランナー | バージョン付きラベル (`ubuntu-24.04`) | `.github/workflows/` |
| Nix インストーラ | バージョン + sha256 | `scripts/nix-pin.sh` |
| ロケール | `LC_ALL=C.UTF-8` | `nix/devshell.nix` |

`flake.lock` は再現性の要件であるため必ずコミットする。存在しない場合は `make lock` で生成する。

クラウド環境の Setup script が参照する本リポジトリ自身も、40桁の commit SHAで固定する ([セットアップ](setup.md#他のリポジトリで使う))。設定欄はリポジトリの外にあり本リポジトリの CI では値を検査できないため、Setup script は形式と取得後の commit を実行時に検査する。`scripts/cloud-setup.sh` も使用したリビジョンを出力する。

Nix インストーラの固定値は `scripts/nix-pin.sh` を単一の定義箇所とする。`docs/setup.md`、`scripts/wsl-provision.sh`、`scripts/cloud-setup.sh` はこの値を参照し、Docker ベースイメージの Nix バージョンとの一致を `scripts/check-pins.sh` が検査する。

固定対象には次の例外がある。

- GitHub Pages の Jekyll 実行環境。ワークフローで呼び出す Actions はコミット SHA に固定する一方、Jekyll とその依存は GitHub Pages が提供する環境を使用し、リポジトリ内には重複して固定しない。公開文書の生成にだけ使用し、開発環境や配布する構成の入力にはしない。

固定されているかは 2 つのスクリプトが検査する。どちらもネットワークを使わず、working tree の内容だけを見る。いずれも「上流に新しい版があるか」は見ない。それは更新の判断であって検査の対象ではないため ([開発](development.md#固定を更新する) を参照)。

## flake の入力 — `scripts/check-lock.sh`

`flake.nix` と `flake.lock` の整合を検査する。

- `flake.nix` の入力がすべて 40 桁の rev で指定されていること
- その rev が `flake.lock` に同一の値で記録されていること
- `flake.lock` の各ノードが narHash を持ち、一意に固定されていること
- `flake.nix` から削除された入力が `flake.lock` に取り残されていないこと

nix 自身が検出するのは、lock の再生成が必要になる乖離 (rev の不一致等) に限られる。その場合 nix は入力の再取得を試みるため、失敗はネットワークのエラーとして現れ、原因が lock の古さであることが分からない。

さらに、**入力がブランチ名で参照されている場合、nix はこれを正常として扱う**。lock には rev が記録されるため評価自体は再現するが、`flake.nix` の記述は固定になっておらず、lock を再生成した時点で追従先が変わる。本検査はこの双方を、オフラインかつ原因の分かる形で検出する。

## flake 以外 — `scripts/check-pins.sh`

- `Dockerfile` の `FROM` がダイジェストで固定されていること。`ARG` 経由の参照も展開して判定する (既定値を持たない `ARG` はビルド時に差し替え可能なため固定とみなさない)
- ワークフローの `uses` がコミット SHA で固定されていること
- ワークフローの `runs-on` が `-latest` でないこと
- `scripts/nix-pin.sh` と `docs/setup.md` の `NIX_VERSION` および `NIX_SHA256` が一致し、前者の `NIX_VERSION` が `Dockerfile` の `ARG NIX_VERSION` とも一致すること
- `docs/setup.md` の導入例が固定した `NIX_SHA256` を使用し、配布元から実行時に取得した値との照合になっていないこと
- `scripts/wsl-provision.sh` と `scripts/cloud-setup.sh` が Nix の固定値を複製せず、`scripts/nix-pin.sh` を参照すること。経路によって異なる版の Nix が入るのを防ぐため
- `scripts/wsl-bootstrap.ps1` の配布イメージが https の URL と 64 桁の sha256 で固定されており、こちらも配布元から取得した値との照合になっていないこと
- `scripts/wsl-bootstrap.ps1` に UTF-8 の BOM があること。Windows PowerShell 5.1 は BOM の無い `.ps1` を ANSI コードページとして読むため、日本語環境では構文エラーになる

---

[目次に戻る](index.md)
