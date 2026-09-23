#!/usr/bin/env bash
# Cloud Setup による home/ と etc/ の配置先と backup の再実行時動作を検査する。
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/cloud-home.sh
. "$script_dir/cloud-home.sh"

# 一時ファイルはリポジトリ内の .work に置く (リポジトリの規約)。Nix の check では
# source が読み取り専用の store にあるため、check 側が書き込み先を明示的に渡す。
root=$(cd "$script_dir/.." && pwd)
work_base=${CLOUD_HOME_TEST_TMPDIR:-"$root/.work"}
work=""

cleanup() {
  if [ -z "$work" ] || [ ! -d "$work" ]; then
    return
  fi

  case $(basename -- "$work") in
    test-cloud-home.*) rm -rf -- "$work" ;;
  esac
}

trap cleanup EXIT

mkdir -p "$work_base"
work=$(mktemp -d "$work_base/test-cloud-home.XXXXXX")
repo=$work/repo
home=$work/home
codex_home=$work/codex

note() {
  :
}
mkdir -p "$repo/home/.claude" "$repo/home/.codex" "$home/.claude" "$codex_home"
printf 'managed-claude\n' >"$repo/home/.claude/settings.json"
printf 'managed-codex-v1\n' >"$repo/home/.codex/AGENTS.md"
printf 'original-codex\n' >"$codex_home/AGENTS.md"

dotfiles_install_home "$repo" "$home" "$codex_home"

cmp -s "$repo/home/.claude/settings.json" "$home/.claude/settings.json"
cmp -s "$repo/home/.codex/AGENTS.md" "$codex_home/AGENTS.md"
grep -qxF 'original-codex' "$codex_home/AGENTS.md.dotfiles-backup"
if [ -e "$home/.codex/AGENTS.md" ]; then
  echo "CODEX_HOME 指定時に HOME/.codex へ配置されました。" >&2
  exit 1
fi

# 再実行時に、最初の利用者ファイルを退避した内容を上書きしない。
printf 'managed-codex-v2\n' >"$repo/home/.codex/AGENTS.md"
dotfiles_install_home "$repo" "$home" "$codex_home"
grep -qxF 'original-codex' "$codex_home/AGENTS.md.dotfiles-backup"
grep -qxF 'managed-codex-v2' "$codex_home/AGENTS.md"

# CODEX_HOME が無い場合の呼び出し側は HOME/.codex を渡す。
fallback_home=$work/fallback-home
mkdir -p "$fallback_home"
dotfiles_install_home "$repo" "$fallback_home" "$fallback_home/.codex"
cmp -s "$repo/home/.codex/AGENTS.md" "$fallback_home/.codex/AGENTS.md"

# etc/ は引数の etc_root 直下へ置き、内容が異なる既存ファイルを初回だけ退避する。
etc_root=$work/etc
mkdir -p "$repo/etc/codex" "$etc_root/codex"
printf 'managed-etc-v1\n' >"$repo/etc/codex/config.toml"
printf 'original-etc\n' >"$etc_root/codex/config.toml"

dotfiles_install_etc "$repo" "$etc_root"
cmp -s "$repo/etc/codex/config.toml" "$etc_root/codex/config.toml"
grep -qxF 'original-etc' "$etc_root/codex/config.toml.dotfiles-backup"

printf 'managed-etc-v2\n' >"$repo/etc/codex/config.toml"
dotfiles_install_etc "$repo" "$etc_root"
grep -qxF 'original-etc' "$etc_root/codex/config.toml.dotfiles-backup"
grep -qxF 'managed-etc-v2' "$etc_root/codex/config.toml"

echo "Cloud home 配置の検査に成功しました。"
