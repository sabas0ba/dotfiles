# CLAUDE.md

Claude Code が本リポジトリで作業する際の指示。

利用者全体の共通規約は `home/.claude/CLAUDE.md` (配置先 `~/.claude/CLAUDE.md`) に
定義してある。本ファイルはそれを前提に、本リポジトリ固有の事項のみを記述する。

## リポジトリの目的

個人の dotfiles と、それを扱うための開発環境を管理する。環境の定義が 1 か所にのみ
存在し、ホスト・CI・コンテナのいずれでも同一の `flake.nix` から同一のツール群が
再現されることを要件とする。

- 環境の定義: `flake.nix` + `nix/`
- ホストでの入り口: direnv (`.envrc`) から `nix develop`
- コンテナでの入り口: `Dockerfile`。同一の flake を評価する

## 環境の前提

作業は開発シェルの内部で行う。判定は環境変数 `DOTFILES_ENV` を参照するか、
`scripts/check-env.sh` を実行する。

```bash
scripts/check-env.sh   # DOTFILES_ENV=nix-develop であれば開発シェル内
```

開発シェルの外にいる場合は `nix develop` (direnv 導入済みであれば `direnv allow`)
で入る。

ツールを開発シェルの外から導入しない。`apt install` / `brew install` /
`npm install -g` / `pip install --user` 等は再現性を損なうため使用しない。必要な
ツールは `nix/packages.nix` に追記して取得する。

## ディレクトリ構成

```
flake.nix                入力 (nixpkgs の rev 固定) と出力の定義
flake.lock               入力の解決結果。narHash を含む
nix/packages.nix         ツールの一覧。ツール追加時はこのファイルのみを編集する
nix/devshell.nix         開発シェルの定義 (環境変数・shellHook)
nix/checks.nix           `nix flake check` が実行する検査
.envrc                   direnv の設定
Dockerfile               同一の flake からコンテナイメージを構築する
Makefile                 操作の入り口。`make help` で一覧を表示する
scripts/check-env.sh     環境が構成されているかのスモークテスト
home/                    ホームディレクトリへ配置する dotfiles (stow パッケージ)
.github/workflows/ci.yml CI。コンテナ内で `make check` を実行する
.work/                   作業用の一時ファイル置き場 (git ignore 対象)
```

`nix/packages.nix` は開発シェル、`nix build` の profile、Docker イメージの 3 つから
参照される単一情報源である。このファイルを変更すれば 3 つすべてに反映される。
Dockerfile にツール名を追記しない。定義が重複し、不整合が生じるため。

## コマンド

```bash
make help          # 一覧
make check         # すべての検査 (nix flake check + 環境のスモークテスト)
make fmt           # Nix およびシェルスクリプトの整形
make lint          # 静的解析のみ
make shell         # 開発シェルに入る
make docker-build  # コンテナイメージの構築
make docker-check  # コンテナ内でのスモークテスト
make stow-dry      # dotfiles の配置内容を確認する (実際には配置しない)
```

## 変更手順

### ツールを追加する

1. `nix/packages.nix` にパッケージ名を追記する (グループのコメントに従って配置する)
2. コマンドとして使用するものは `scripts/check-env.sh` の `required_commands` にも
   追記する
3. `make check` が成功することを確認する

### nixpkgs を更新する

`flake.nix` の `nixpkgs.url` はブランチ名ではなく 40 桁の rev で固定してある。更新は
以下のコマンドで行い、`flake.nix` と `flake.lock` を同一のコミットに含める。

```bash
make bump REV=$(curl -sL https://channels.nixos.org/nixos-26.05/git-revision)
make check
```

nixpkgs の更新は独立したコミットとし、他の変更と混在させない。

### バージョンの固定

本リポジトリで参照する外部の成果物は、すべて一意に固定する。固定されていない参照を
追加しない。

| 対象 | 固定方法 | 定義箇所 |
| --- | --- | --- |
| nixpkgs | 40 桁の rev + `flake.lock` の narHash | `flake.nix` |
| ベースイメージ | タグ + ダイジェスト (`@sha256:...`) | `Dockerfile` |
| GitHub Actions | コミット SHA | `.github/workflows/ci.yml` |

タグやブランチ名のみによる参照は固定とみなさない。

### flake.lock

`flake.lock` は再現性の要件であるため必ずコミットする。`.gitignore` に追加しない。
存在しない場合は `make lock` で生成する。

### Dockerfile を変更する

コンテナはホストと同一の環境である必要がある。イメージの内容を変更する場合、変更先は
`nix/packages.nix` である。Dockerfile を直接変更してよいのは、レイヤ構成、ベース
イメージの固定、entrypoint の挙動を変更する場合に限る。

### dotfiles を追加する

`home/` 以下に、ホームディレクトリからの相対パスで配置する (例:
`home/.claude/CLAUDE.md` は `~/.claude/CLAUDE.md` に対応する)。配置は GNU stow で
行うが、既存ファイルを上書きする可能性があるため、`make stow-dry` の結果を利用者に
提示し、確認を得てから `make stow` を実行する。

## コーディング規約

- Nix: `nixfmt` (RFC 166 スタイル) で整形する。`statix` および `deadnix` の指摘を
  残さない
- シェル: bash または POSIX sh。先頭に `set -euo pipefail` (sh では `set -eu`) を
  記述する。`shellcheck` を通し、`shfmt --indent 2 --case-indent` で整形する
- コメント: 実装内容ではなく、その選択の理由を記述する。既存ファイルに合わせて
  日本語で記述する
- 整形は手作業ではなく `make fmt` で行う

## コミット

- Conventional Commits (`feat:` / `fix:` / `chore:` / `docs:` / `refactor:` / `ci:`)
- 1 コミット 1 目的とする。環境の更新と dotfiles の変更を混在させない
- コミット前に `make check` を実行する

## 禁止事項

- 秘密情報 (トークン、鍵、社内ホスト名) のコミット。マシン固有の設定は `.envrc.local`
  (git 管理外) に置く
- 利用者のホームディレクトリにある既存ファイルの、確認を経ない上書きおよび削除
- `flake.lock` の削除、`.gitignore` への追加、および検査を通過させるための検査自体の
  削除
- 開発シェルの外部でのツール導入
- 一時ファイルをリポジトリ外部 (`/tmp` 等) に作成すること。`.work/` を使用する

## 変更後の検証

以下が成功することを必須とする。

```bash
make check
```

`Dockerfile` または `nix/` を変更した場合は、コンテナ側も検証する。

```bash
make docker-check
```
