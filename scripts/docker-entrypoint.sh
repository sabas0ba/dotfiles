#!/bin/sh
#
# コンテナの ENTRYPOINT。
#
# イメージのビルド時に `nix develop --profile "$DOTFILES_PROFILE"` で開発シェルを
# profile として実体化しているため、本スクリプトでは flake を再評価せずその profile に
# 入る。実行時のネットワークを必要とせず、起動が速い。
#
# ベースイメージ (nixos/nix) における bash の存在を前提としないため POSIX sh で記述する。
set -eu

profile="${DOTFILES_PROFILE:-/nix/var/nix/profiles/dotfiles-dev}"

if [ ! -e "$profile" ]; then
  echo "開発 profile が見つかりません: $profile" >&2
  echo "イメージのビルドが失敗している可能性があります。" >&2
  exit 1
fi

if [ "$#" -eq 0 ]; then
  # 引数が無い場合は対話シェルに入る。
  exec nix develop "$profile" --command bash
fi

exec nix develop "$profile" --command "$@"
