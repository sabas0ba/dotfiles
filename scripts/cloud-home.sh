#!/usr/bin/env bash
#
# cloud-setup.sh が setup-script 経路で home/ を配置するための補助関数。
# 配置先を引数で受け取り、Nix や root 権限を使わず回帰検査できるようにする。
set -euo pipefail

dotfiles_home_target() {
  local repo=$1
  local home=$2
  local codex_home=$3
  local source=$4

  case "$source" in
    "$repo/home/.codex/"*)
      printf '%s/%s\n' "$codex_home" "${source#"$repo/home/.codex/"}"
      ;;
    "$repo/home/"*)
      printf '%s/%s\n' "$home" "${source#"$repo/home/"}"
      ;;
    *)
      echo "エラー: home/ 配下でないファイルです: $source" >&2
      return 1
      ;;
  esac
}

dotfiles_install_home() {
  local repo=$1
  local home=$2
  local codex_home=$3
  local source target backup shown

  while IFS= read -r source; do
    target=$(dotfiles_home_target "$repo" "$home" "$codex_home" "$source")
    backup=$target.dotfiles-backup
    mkdir -p "$(dirname "$target")"

    if [ -e "$target" ] && [ ! -e "$backup" ] && ! cmp -s "$source" "$target"; then
      cp -p "$target" "$backup"
      shown=${backup#"$home/"}
      note "退避した $shown"
    fi

    cp -f "$source" "$target"
    shown=${target#"$home/"}
    note "配置した $shown"
  done < <(find "$repo/home" -type f)
}
