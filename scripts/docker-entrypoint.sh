#!/bin/sh
#
# コンテナの ENTRYPOINT。
#
# イメージのビルド時に `nix develop --profile "$DOTFILES_PROFILE"` で開発シェルを
# profile として実体化してあるので、ここでは flake を評価し直さずにその profile へ
# 入るだけでよい。結果としてコンテナの起動はオフラインでも一瞬で終わり、
# 中身はホストの `nix develop` とまったく同じ閉包になる。
#
# ベースイメージ (nixos/nix) に bash がある保証を置きたくないので POSIX sh で書く。
set -eu

profile="${DOTFILES_PROFILE:-/nix/var/nix/profiles/dotfiles-dev}"

if [ ! -e "$profile" ]; then
  echo "開発 profile が見つかりません: $profile" >&2
  echo "イメージのビルドが途中で失敗している可能性があります。" >&2
  exit 1
fi

if [ "$#" -eq 0 ]; then
  # 引数なしなら対話シェルに入る。
  exec nix develop "$profile" --command bash
fi

exec nix develop "$profile" --command "$@"
