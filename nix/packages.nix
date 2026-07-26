# 開発環境に導入するツールの単一情報源。
#
# 本ファイルの内容が
#   - `nix develop` および direnv のシェル (nix/devshell.nix 経由)
#   - `nix build .#default` の profile      (flake.nix 経由)
#   - Docker イメージ                       (Dockerfile が上記 profile を使用)
# の 3 つすべてに反映される。ツールを追加する場合は本ファイルのみを編集する。
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

  # --- 環境そのものを扱うツール -------------------------------------------
  direnv
  nix-direnv

  # --- Nix の開発支援 -----------------------------------------------------
  nixfmt # フォーマッタ (`nix fmt`)。26.05 以降は RFC 166 スタイル
  statix # 静的解析
  deadnix # 未使用コードの検出
  nil # language server

  # --- シェルスクリプトの開発支援 -----------------------------------------
  bashInteractive
  shellcheck
  shfmt
]
