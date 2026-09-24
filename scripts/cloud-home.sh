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

  # yq は TOML の日時を文字列として読み、書き戻すと型が変わる。型を区別する手段が
  # 無いため、日時の値らしい記述があれば書き換えずに止める。文字列の中身に一致した
  # 場合も止まるが、誤って型を変えるよりよい。
  if grep -Eq '[=,[][[:space:]]*([0-9]{4}-[0-9]{2}-[0-9]{2}|[0-9]{2}:[0-9]{2}:[0-9]{2})' "$target"; then
    echo "エラー: $target に日時の値があるため overlay できません。" >&2
    echo "       手作業で ${source#"$base/"} の値を反映してください。" >&2
    return 1
  fi

  tmp=$(mktemp -d "$target.dotfiles-tmp.XXXXXX")
  if ! dotfiles_merge_toml "$target" "$source" "$tmp"; then
    rm -rf "$tmp"
    echo "エラー: $target の overlay に失敗しました。既存のファイルは変更していません。" >&2
    return 1
  fi
  cp -f "$tmp/merged.toml" "$target"
  rm -rf "$tmp"
  note "overlay した ${target#"$base/"}"
}

# TOML の table 見出しより後の key はその table に属する。yq の TOML 出力は key の
# 順序を保つだけで並べ替えないため、既存ファイルが dotted key や inline table を
# 通常の key より前に置いていると、後続の key が別の table に移る。各階層で値を
# table より前に並べてから出力する。
readonly DOTFILES_TOML_ORDER='
def is_table: type == "object" or (type == "array" and length > 0 and all(.[]; type == "object"));
def toml_order:
  if type == "object" then
    to_entries
    | (map(select(.value | is_table | not)) + map(select(.value | is_table)))
    | map(.value |= toml_order)
    | from_entries
  elif type == "array" then map(toml_order)
  else . end;
'

# base と overlay を merge した TOML を $work/merged.toml に書く。書いたものを読み直し、
# merge の結果と意味が一致しない場合は失敗する。コメントは保持しない (元の内容は
# 呼び出し側が .dotfiles-backup に退避している)。
dotfiles_merge_toml() {
  local base=$1
  local overlay=$2
  local work=$3

  yq -p toml -o json "$base" >"$work/base.json" &&
    yq -p toml -o json "$overlay" >"$work/overlay.json" &&
    jq -s "$DOTFILES_TOML_ORDER"' .[0] * .[1] | toml_order' \
      "$work/base.json" "$work/overlay.json" >"$work/expected.json" &&
    yq -p json -o toml "$work/expected.json" >"$work/merged.toml" &&
    yq -p toml -o json "$work/merged.toml" | jq -S . >"$work/actual.json" &&
    jq -S . "$work/expected.json" | cmp -s - "$work/actual.json"
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
