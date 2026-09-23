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

# Codex の system config は既存の管理外 key を保持し、dotfiles 側の key を優先する。
# 最初の既存内容は再実行しても backup として保持する。
etc_root=$work/etc
mkdir -p "$repo/etc/codex" "$etc_root/codex"
cat >"$repo/etc/codex/config.toml" <<'EOF'
[analytics]
enabled = false

[shell_environment_policy.set]
GH_TELEMETRY = "false"
EOF
cat >"$etc_root/codex/config.toml" <<'EOF'
custom = "preserve"

[analytics]
enabled = true

[otel]
trace_exporter = "otlp-http"

[shell_environment_policy.set]
GH_TELEMETRY = "true"
EXISTING = "keep"
EOF
cp "$etc_root/codex/config.toml" "$work/original-codex-system.toml"

dotfiles_install_etc "$repo" "$etc_root"
cmp -s "$work/original-codex-system.toml" "$etc_root/codex/config.toml.dotfiles-backup"
yq -p toml -e '
  .custom == "preserve" and
  .analytics.enabled == false and
  .otel.trace_exporter == "otlp-http" and
  .shell_environment_policy.set.GH_TELEMETRY == "false" and
  .shell_environment_policy.set.EXISTING == "keep"
' "$etc_root/codex/config.toml" >/dev/null

cat >"$repo/etc/codex/config.toml" <<'EOF'
[analytics]
enabled = false

[feedback]
enabled = false

[shell_environment_policy.set]
GH_TELEMETRY = "disabled"
EOF
dotfiles_install_etc "$repo" "$etc_root"
cmp -s "$work/original-codex-system.toml" "$etc_root/codex/config.toml.dotfiles-backup"
yq -p toml -e '
  .custom == "preserve" and
  .analytics.enabled == false and
  .feedback.enabled == false and
  .otel.trace_exporter == "otlp-http" and
  .shell_environment_policy.set.GH_TELEMETRY == "disabled" and
  .shell_environment_policy.set.EXISTING == "keep"
' "$etc_root/codex/config.toml" >/dev/null

echo "Cloud home 配置の検査に成功しました。"
