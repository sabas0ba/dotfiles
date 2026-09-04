# 開発

本ページが本リポジトリの開発規約の原本であり、人間と coding agent の双方に適用する。agent 向けの入口は `AGENTS.md`、Claude Code の互換入口は `CLAUDE.md` とする。

## 構成

```
flake.nix                入力 (rev 固定) と出力の定義
flake.lock               入力の解決結果
nix/packages.nix         ツール、コマンド契約、用途別 profile (単一情報源)
nix/devshell.nix         開発シェルの定義
nix/checks.nix           nix flake check が実行する検査
nix/home.nix             home-manager によるホームディレクトリの構成
nix/wsl.nix              WSL 上の NixOS の system 構成 (Windows 側からの隔離を含む)
.envrc                   direnv の設定
Dockerfile               同一の flake からコンテナを構築する
Makefile                 操作の入り口
scripts/                 ヘルパースクリプト
home/                    ホームディレクトリへ配置する生ファイル
docs/                    本ドキュメント (GitHub Pages で公開する)
.github/workflows/       CI と Pages の定義
.claude/settings.json    Claude Code のフック定義 (クラウド環境の構成)
AGENTS.md                coding agent 向けのリポジトリ固有指示
CLAUDE.md                AGENTS.md を参照する Claude Code 互換入口
.work/                   作業用の一時ファイル置き場 (git ignore 対象)
```

## CI

`ci.yml` は `make docker-check` を実行する。この target は現在の checkout からイメージを構築し、source を mount で上書きせず、`--network none` のコンテナ内で `make check` を実行する。CI とローカルで同じ target を使い、CI 環境をホストおよびコンテナと別の環境にしない。push (main) と pull request で自動実行する。

`nix flake check` は通常の lint に加え、各 `homeConfigurations` の activation package と `nixosConfigurations.wsl` の system derivation を評価する。構成の derivation path までを契約とし、activation package や NixOS system closure 自体は構築しない。

`pages.yml` は `docs/` を GitHub Pages へ公開する。push (main) と手動実行で配置し、`docs/` を変更する pull request では生成のみを行う (配置はしない)。サイトの生成は GitHub が提供する Jekyll をそのまま使い、リポジトリ側に生成器の依存を持たない。

見た目は外部のテーマに依存せず、`docs/_layouts/default.html` と `docs/assets/css/style.css` で完結させる。テーマは版を固定できず、上流の変更がそのまま公開物に及ぶためである。配色は CSS の変数で定義し、OS の設定 (`prefers-color-scheme`) と利用者の選択 (`data-theme`) の双方で切り替える。

ページを追加した場合は、ヘッダの導線となる `docs/_config.yml` の `nav` にも追記する。

公開を開始するには、リポジトリの Settings → Pages で Source を「GitHub Actions」にする操作が一度だけ必要である。`actions/configure-pages` の `enablement` でワークフローから有効化することもできるが、CI がリポジトリの設定を変更することになるため採っていない。

`update-pins.yml` は固定の更新と PR の作成を行う。手動実行のみで、定期実行はしない。

## ツールを追加する

1. `nix/packages.nix` の用途別 group に `mkTool` を追記する
2. package が提供する必須コマンドを同じ `mkTool` の `commands` に記述する
3. 必要な profile の `groups` に追加する
4. `make check` が成功することを確認する

`scripts/check-env.sh` にコマンド名を追記しない。profile ごとのコマンド契約は `nix/packages.nix` から manifest として生成される。Linux 固有の package には `systems = linuxSystems;` を指定し、4 platform の flake 評価を壊さないようにする。package 自体の `meta.platforms` も `lib.meta.availableOn` で検査される。

容量の大きい tool を `base` に追加しない。通常の dotfiles 保守で必要なものだけを `default` に置き、言語、コンテナ、HDL、browser は用途別 profile へ置く。profile 名は `devShells` と `packages` で共通であり、次の両方を確認する。

```bash
nix develop .#software
nix build --no-link .#software
```

`Dockerfile` にツール名を追記しない。定義が重複し、不整合が生じる。

クラウド環境のセッションに限って足すものは、ここではなく環境の設定で指定する ([追加のパッケージを指定する](setup.md#追加のパッケージを指定する))。作業対象のリポジトリが必要とする言語のツールチェーンのように、本リポジトリの開発環境そのものには入れない依存が対象である。

開発シェルの stdenv が暗黙に載せるコマンド (`awk` 等) に依存しない。`nix build .#software` 等の通常の profile には含まれないため、そこで壊れる。

## ホームディレクトリの構成を変更する

宣言的に書ける設定は `nix/home.nix` に、生ファイルとして配置するものは `home/` 以下にホームディレクトリからの相対パスで置く。手順は [使い方](usage.md#ホームディレクトリの構成) を参照する。

## Dockerfile を変更する

コンテナは同名のホスト profile と同一の環境である必要がある。イメージの内容を変更する場合、変更先は `nix/packages.nix` である。`Dockerfile` を直接変更してよいのは、レイヤ構成、ベースイメージの固定、profile 選択の受け渡し、entrypoint の挙動を変更する場合に限る。

## 固定を更新する

上流の最新版を自動で取得して書き換えることはしない。更新は意図的な操作であり、値は明示的に与える。与えた値は形式を検査したうえで書き込み、変更対象が見つからない場合は失敗する (記述が変わったことに気付かないまま進むのを防ぐため)。

### flake の入力

`flake.lock` の再生成を伴うため `make` 経由で行い、`flake.nix` と `flake.lock` を同一のコミットに含める。更新は独立したコミットとし、他の変更と混在させない。

```bash
make bump REV=$(curl -sL https://channels.nixos.org/nixos-26.05/git-revision)   # nixpkgs
make bump-hm REV=<40 桁の rev>                                                  # home-manager (release-26.05 の HEAD)
make bump-wsl REV=<40 桁の rev> TAG=<tag>                                       # NixOS-WSL (release-26.05 上のタグ)
make check
```

`flake.lock` の再生成を忘れた場合は `make check` が失敗する ([再現性](reproducibility.md) を参照)。NixOS-WSL は URL の revision と同一行コメントのタグを 1 回の置換で更新し、片方だけが変わった状態を残さない。

### その他

`flake.lock` の再生成を伴わないものは `scripts/update-pins.sh` を直接呼ぶ。対象と値の取得方法は `make bump-help` で一覧できる。

```bash
# Nix release。ベースイメージと導入用 tarball の固定を一括更新する
scripts/update-pins.sh nix-release 2.35.1 sha256:377d4887... c3fe2977...

# GitHub Actions (対象タグが指すコミット SHA)
scripts/update-pins.sh action actions/checkout 11bd7190...

# WSL の配布イメージ
scripts/update-pins.sh wsl-image nixos 2605.7.2 https://.../nixos.wsl e7180ad5...
scripts/update-pins.sh wsl-image ubuntu 24.04.4 https://.../ubuntu-...wsl 9b2f7730...
```

Nix release は `Dockerfile` の版と image digest、`docs/setup.md` および
`scripts/nix-pin.sh` の版と installer sha256 を transaction として更新する。version が
同じまま digest または sha256 だけを更新する場合も、この対象を使用する。旧 `image` と
`nix-installer` は、固定の一部だけを変更しないよう廃止している。すべての値が既存の固定と
同じ場合は、ファイルを書き換えずに失敗する。

WSL の配布イメージの値は、配布物と同じ場所に置かれたチェックサムファイル以外から取る。同時に差し替えられるものと照合しても検証にならないため。

- NixOS-WSL: GitHub の releases に置かれた `nixos.wsl` と、GitHub API が返す当該アセットのダイジェスト
- Ubuntu: Microsoft が配布する [`DistributionInfo.json`](https://raw.githubusercontent.com/microsoft/WSL/master/distributions/DistributionInfo.json) の `Amd64Url` (`Url` と `Sha256`)

Nix release の各値の不一致は `make check` が検出する。

### CI から更新して PR を作成する

手元に環境が無い場合は、Actions タブまたは `gh workflow run update-pins.yml` で `Update pins` を手動実行する。対象と値を入力すると、更新、検証、PR の作成までを行う。

1. `scripts/update-pins.sh` で値を書き換える
2. `flake.nix` を変更した場合は `flake.lock` を再生成する。イメージを構築する前に行う (両者が整合していないと nix が暗黙に再ロックするため)。ここで使う nix は `Dockerfile` が固定しているベースイメージから取る。ワークフローに版を書くと二重管理になる
3. イメージを構築し、`--network none` のコンテナ内で `make check` を実行する。CI と同一の経路である
4. ブランチを作成し、PR を開く

PR の作成には外部 action を使わず、ランナー同梱の `gh` と `GITHUB_TOKEN` を用いる。外部 action を増やさないため。

`GITHUB_TOKEN` で作成した PR では他のワークフローが起動しない (GitHub の仕様)。その PR に CI のチェックは付かないため、上記 3 の結果を PR 本文に記載している。CI を回す必要がある場合は、close して reopen するか、ブランチに空でないコミットを push する。

## コーディング規約

- Nix: `nixfmt` (RFC 166 スタイル) で整形する。`statix` および `deadnix` の指摘を残さない
- シェル: bash または POSIX sh。先頭に `set -euo pipefail` (sh では `set -eu`) を記述する。`shellcheck` を通し、`shfmt --indent 2 --case-indent` で整形する
- PowerShell: `scripts/wsl-bootstrap.ps1` のみ。静的解析器 (PSScriptAnalyzer) は依存が増えるため導入していない。したがって判断を伴う処理は原則として `scripts/wsl-provision.sh` (shellcheck と `nix flake check` の対象) に置き、bootstrap には provision がまだ存在しない時点で必要な、配布イメージと管理マーカーの照合、利用者の作成、リポジトリの検証と取得だけを残す。ファイルは UTF-8 の BOM 付きで保存する (`make check` が検査する)
- コメント: 実装内容ではなく、その選択の理由を記述する。既存ファイルに合わせて日本語で記述する
- 整形は手作業ではなく `make fmt` で行う。引数なしの `nix fmt` は `.git`、`.direnv`、
  `.work` を探索対象から除外する

## コミット

- Conventional Commits (`feat:` / `fix:` / `chore:` / `docs:` / `refactor:` / `ci:`)
- 1 コミット 1 目的とする。環境の更新と dotfiles の変更を混在させない
- コミット前に `make check` を実行する

## 検証

以下が成功することを必須とする。

```bash
make check
```

`Dockerfile` または `nix/` を変更した場合は、コンテナ側も検証する。

```bash
make docker-check
```

`make docker-check` は CI と同じオフラインの全検査である。ツールの存在だけを短時間で確認する場合は `make docker-smoke` を使うが、これは `Dockerfile` または `nix/` の変更後に必要な全検査の代わりにはならない。

WSL 関連の変更は、コンテナ内の検査では実行経路を確認できない。実機で `scripts/wsl-bootstrap.ps1` を検証用の名前で通し、確認後に `-Unregister` する。

## 禁止事項

- 秘密情報 (トークン、鍵、社内ホスト名) のコミット。マシン固有の設定は `.envrc.local` (git 管理外) に置く
- `flake.lock` の削除、`.gitignore` への追加、および検査を通過させるための検査自体の削除
- 開発シェルの外部でのツール導入
- 一時ファイルをリポジトリ外部 (`/tmp` 等) に作成すること。`.work/` を使用する

---

[目次に戻る](index.md)
