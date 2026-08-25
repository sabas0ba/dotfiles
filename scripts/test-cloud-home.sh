#!/usr/bin/env bash
# Cloud Setup による home/ 配置先と backup の再実行時動作を検査する。
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/cloud-home.sh
. "$script_dir/cloud-home.sh"

work=${TMPDIR:-$script_dir/../.work}/dotfiles-cloud-home-test
repo=$work/repo
home=$work/home
codex_home=$work/codex

note() {
  :
}

rm -rf "$work"
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

echo "Cloud home 配置の検査に成功しました。"
