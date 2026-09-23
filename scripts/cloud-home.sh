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

# 1 ファイルを配置する。内容が異なる既存ファイルは初回だけ .dotfiles-backup へ退避する。
# 表示では base の接頭辞を省く。
dotfiles_install_file() {
  local source=$1
  local target=$2
  local base=$3
  local backup=$target.dotfiles-backup

  mkdir -p "$(dirname "$target")"

  if [ -e "$target" ] && [ ! -e "$backup" ] && ! cmp -s "$source" "$target"; then
    cp -p "$target" "$backup"
    note "退避した ${backup#"$base/"}"
  fi

  cp -f "$source" "$target"
  note "配置した ${target#"$base/"}"
}

dotfiles_install_home() {
  local repo=$1
  local home=$2
  local codex_home=$3
  local source target

  while IFS= read -r source; do
    target=$(dotfiles_home_target "$repo" "$home" "$codex_home" "$source")
    dotfiles_install_file "$source" "$target" "$home"
  done < <(find "$repo/home" -type f)
}

# TOML の管理値を既存ファイルへ重ねる。既存の管理外 key は保持し、source 側を優先する。
# 内容が異なる既存ファイルは generic な配置と同様に初回だけ退避する。
dotfiles_overlay_toml() {
  local source=$1
  local target=$2
  local base=$3
  local backup=$target.dotfiles-backup
  local tmp

  mkdir -p "$(dirname "$target")"

  if [ ! -e "$target" ]; then
    cp -f "$source" "$target"
    note "配置した ${target#"$base/"}"
    return
  fi

  if [ ! -e "$backup" ] && ! cmp -s "$source" "$target"; then
    cp -p "$target" "$backup"
    note "退避した ${backup#"$base/"}"
  fi

  tmp=$(mktemp "$target.dotfiles-tmp.XXXXXX")
  if ! yq eval-all -p toml -o toml \
    'select(fileIndex == 0) * select(fileIndex == 1)' \
    "$target" "$source" >"$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  cp -f "$tmp" "$target"
  rm -f "$tmp"
  note "overlay した ${target#"$base/"}"
}

# etc/ 以下を system の /etc (引数 etc_root) の構造に対応させて配置する。
# Codex の system config は環境側の設定を消さないよう TOML として overlay する。
dotfiles_install_etc() {
  local repo=$1
  local etc_root=$2
  local source relative target

  while IFS= read -r source; do
    relative=${source#"$repo/etc/"}
    target=$etc_root/$relative

    case "$relative" in
      codex/config.toml)
        dotfiles_overlay_toml "$source" "$target" "$(dirname "$etc_root")"
        ;;
      *)
        dotfiles_install_file "$source" "$target" "$(dirname "$etc_root")"
        ;;
    esac
  done < <(find "$repo/etc" -type f)
}
