# 開発環境に入れるツールの単一情報源 (single source of truth)。
#
# ここに書いたものが
#   - `nix develop` / direnv のシェル       (nix/devshell.nix 経由)
#   - `nix build .#default` の profile      (flake.nix 経由)
#   - Docker イメージの中身                 (Dockerfile が上の profile を使う)
# の 3 つすべてに反映される。ツールを足すときはこのファイルだけを編集すること。
{ pkgs }:

with pkgs;
[
  # --- 基本ユーティリティ -------------------------------------------------
  coreutils
  findutils
  gnugrep
  gnused
  gnutar
  gzip
  less
  which

  # --- 検索・テキスト処理 -------------------------------------------------
  ripgrep
  fd
  jq
  yq-go
  tree

  # --- タスクランナー -----------------------------------------------------
  gnumake

  # --- バージョン管理 -----------------------------------------------------
  git

  # --- dotfiles 管理 ------------------------------------------------------
  # ホームディレクトリへの symlink 配置に使う。
  stow

  # --- 環境そのものを扱うツール -------------------------------------------
  direnv
  nix-direnv

  # --- Nix の開発支援 -----------------------------------------------------
  nixfmt # フォーマッタ (`nix fmt`)。26.05 以降は RFC 166 スタイル
  statix # lint
  deadnix # 未使用コードの検出
  nil # language server

  # --- シェルスクリプトの開発支援 -----------------------------------------
  bashInteractive
  shellcheck
  shfmt
]
