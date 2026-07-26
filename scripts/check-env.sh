#!/usr/bin/env bash
#
# 開発環境が構成されているかを確認するスモークテスト。
# ホストの `nix develop` 内でも Docker コンテナ内でも同一の結果となる。
#
#   使用方法: scripts/check-env.sh
set -euo pipefail

# nix/packages.nix に含まれるツールのうち、コマンドとして使用するもの。
# 本リストを変更した場合は nix/packages.nix 側にも同じものを追加する。
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
  echo "開発環境の外で実行されている可能性があります。'nix develop' または 'direnv allow' を実行してください。" >&2
  exit 1
fi

if [ "${DOTFILES_ENV:-}" != "nix-develop" ]; then
  echo "エラー: DOTFILES_ENV が設定されていません。" >&2
  echo "コマンドは揃っていますが、開発シェルの外で実行されている可能性があります。" >&2
  exit 1
fi

echo "開発環境は正常です (DOTFILES_ENV=${DOTFILES_ENV})。"
