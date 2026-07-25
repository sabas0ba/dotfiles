# CLAUDE.md

Claude Code がこのリポジトリで作業するときの指示。

## このリポジトリについて

個人の dotfiles と、それを扱うための開発環境を管理する。中心にあるのは
「**環境の定義が 1 か所にしかない**」という性質で、ホストでも CI でも
コンテナでも、同じ `flake.nix` から同じツール群が再現される。

- 環境の定義: `flake.nix` + `nix/`
- ホストでの入り口: direnv (`.envrc`) → `nix develop`
- コンテナでの入り口: `Dockerfile` → 上と同じ flake を使う

## 環境の前提 (最も重要)

作業は**必ず開発シェルの中**で行う。判定は `$DOTFILES_ENV` を見るか
`scripts/check-env.sh` を実行する。

```bash
scripts/check-env.sh   # DOTFILES_ENV=nix-develop なら中にいる
```

シェルの外にいる場合は `nix develop` (direnv 導入済みなら `direnv allow`) で入る。

**ツールを環境の外から入れないこと。** `apt install` / `brew install` /
`npm install -g` / `pip install --user` などは、この環境の再現性を壊すので使わない。
必要なツールは `nix/packages.nix` に追記して取得する。

## ディレクトリ構成

```
flake.nix              入力 (nixpkgs の rev 固定) と出力の定義
nix/packages.nix       ツールの一覧。★ ツール追加はここだけを編集する
nix/devshell.nix       開発シェルの形 (環境変数・shellHook)
nix/checks.nix         `nix flake check` が走らせる検査
.envrc                 direnv の設定。cd したら自動で環境に入る
Dockerfile             上の flake をそのまま使ってコンテナを作る
Makefile               操作の入り口。`make help` で一覧
scripts/check-env.sh   環境が揃っているかのスモークテスト
```

`nix/packages.nix` は開発シェル・`nix build` の profile・Docker イメージの
3 つすべてから参照される単一情報源。ここを直せば 3 つとも同時に変わる。
**Dockerfile にツール名を直接書き足してはいけない** (定義が二重化して必ずズレる)。

## よく使うコマンド

```bash
make help          # 一覧
make check         # 検査ぜんぶ (nix flake check + 環境のスモークテスト)
make fmt           # Nix とシェルスクリプトの整形
make lint          # 静的解析だけ
make shell         # 開発シェルに入る
make docker-build  # コンテナイメージをビルド
make docker-check  # コンテナの中でスモークテスト
```

## 変更のルール

### ツールを追加する

1. `nix/packages.nix` にパッケージ名を追記する (グループのコメントに従って置く)
2. コマンドとして使うものなら `scripts/check-env.sh` の `required_commands` にも足す
3. `make check` が通ることを確認する

### nixpkgs を更新する

`flake.nix` の `nixpkgs.url` はブランチ名ではなく 40 桁の rev で固定してある。
更新は次の 1 コマンドで行い、`flake.nix` と `flake.lock` を**同じコミット**に含める。

```bash
make bump REV=$(curl -sL https://channels.nixos.org/nixos-26.05/git-revision)
make check
```

nixpkgs の更新は独立したコミットにする (他の変更と混ぜない)。

### flake.lock について

`flake.lock` は再現性の要なので**必ずコミットする**。まだ存在しない場合は
`make lock` で生成する。`.gitignore` に入れてはいけない。

### Dockerfile を変更する

コンテナはホストと同じ環境でなければ意味がない。イメージの中身を変えたい場合、
ほぼ必ず正しい変更先は `nix/packages.nix` の側。Dockerfile を直接触ってよいのは
レイヤ構成・ベースイメージの固定・entrypoint の挙動を変えるときだけ。

## コーディング規約

- **Nix**: `nixfmt` (RFC 166 スタイル) で整形。`statix` / `deadnix` の指摘は残さない
- **シェル**: bash か POSIX sh。先頭に `set -euo pipefail` (sh では `set -eu`)。
  `shellcheck` を通し、`shfmt --indent 2 --case-indent` で整形する
- **コメント**: 「何をしているか」ではなく「なぜそうしているか」を書く。
  既存ファイルのコメントは日本語なので、それに合わせる
- 生成・整形は手作業ではなく `make fmt` で行う

## コミット

- Conventional Commits (`feat:` / `fix:` / `chore:` / `docs:` / `refactor:`)
- 1 コミット 1 目的。環境の更新と dotfiles の変更を混ぜない
- コミット前に `make check` を通す

## やってはいけないこと

- 秘密情報 (トークン・鍵・社内ホスト名) をコミットする。
  マシン固有の設定は `.envrc.local` (git 管理外) に置く
- ユーザーのホームディレクトリの既存ファイルを、確認なしに上書き・削除する。
  `stow` を使った symlink の配置は、対象を提示して確認を取ってから行う
- `flake.lock` を消す、`.gitignore` に足す、検査を素通りさせるために検査自体を消す
- 環境の外でツールをインストールして「動いた」ことにする

## 変更後の検証

最低限これが通ること。

```bash
make check
```

Dockerfile または `nix/` を触った場合は、コンテナ側も確認する。

```bash
make docker-check
```
