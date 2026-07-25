#!/usr/bin/env bash
#
# 開発環境が期待どおりに揃っているかを確認するスモークテスト。
# ホストの `nix develop` の中でも、Docker コンテナの中でも同じ結果になるはず。
#
#   使い方: scripts/check-env.sh
set -euo pipefail

# nix/packages.nix に入れたツールのうち、実際にコマンドとして使うもの。
# ここを増やしたら nix/packages.nix 側にも同じものを足すこと。
required_commands=(
  bash
  deadnix
  direnv
  fd
  git
  jq
  make
  nil
  nixfmt
  rg
  shellcheck
  shfmt
  statix
  stow
  tree
  yq
)

missing=()

for cmd in "${required_commands[@]}"; do
  if command -v "$cmd" >/dev/null 2>&1; then
    printf '  ok      %-12s %s\n' "$cmd" "$(command -v "$cmd")"
  else
    printf '  MISSING %-12s\n' "$cmd"
    missing+=("$cmd")
  fi
done

echo

if [ "${#missing[@]}" -ne 0 ]; then
  echo "不足しているコマンド: ${missing[*]}" >&2
  echo "開発環境の外にいる可能性があります。'nix develop' か 'direnv allow' を実行してください。" >&2
  exit 1
fi

if [ "${DOTFILES_ENV:-}" != "nix-develop" ]; then
  echo "警告: DOTFILES_ENV が設定されていません。" >&2
  echo "コマンドは揃っていますが、開発シェルの外で動いている可能性があります。" >&2
  exit 1
fi

echo "開発環境は正常です (DOTFILES_ENV=${DOTFILES_ENV})。"
