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
| Nix インストーラ | バージョン + sha256 | `docs/setup.md` および `scripts/wsl-provision.sh` |
| ロケール | `LC_ALL=C.UTF-8` | `nix/devshell.nix` |

`flake.lock` は再現性の要件であるため必ずコミットする。存在しない場合は `make lock` で生成する。

唯一の例外は、クラウド環境の Setup script が参照する本リポジトリ自身である ([セットアップ](setup.md#他のリポジトリで使う))。ここは常に最新を使う運用とし、固定しない。設定欄はリポジトリの外にあり `scripts/check-pins.sh` の検査が及ばないうえ、他のリポジトリの開発で使う環境を上流の更新に追従させたいためである。固定しない代わりに、`scripts/cloud-setup.sh` が使用したリビジョンを実行時に出力する。戻す必要が生じた場合は、当該の設定欄で対象のリビジョンを明示する。

固定されているかは 2 つのスクリプトが検査する。どちらもネットワークを使わず、作業木の内容だけを見る。いずれも「上流に新しい版があるか」は見ない。それは更新の判断であって検査の対象ではないため ([開発](development.md#固定を更新する) を参照)。

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
- `docs/setup.md` の `NIX_VERSION` が `Dockerfile` の `ARG NIX_VERSION` と一致すること
- `docs/setup.md` に固定した `NIX_SHA256` があり、配布元から取得した値との照合になっていないこと
- `scripts/wsl-provision.sh` の `NIX_VERSION` と `NIX_SHA256` が `docs/setup.md` と一致すること。経路によって異なる版の Nix が入るのを防ぐため
- `scripts/wsl-bootstrap.ps1` の配布イメージが https の URL と 64 桁の sha256 で固定されており、こちらも配布元から取得した値との照合になっていないこと
- `scripts/wsl-bootstrap.ps1` に UTF-8 の BOM があること。Windows PowerShell 5.1 は BOM の無い `.ps1` を ANSI コードページとして読むため、日本語環境では構文エラーになる

---

[目次に戻る](index.md)
