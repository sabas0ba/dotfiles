#!/usr/bin/env bash
#
# etc/ 以下を /etc へ配置する。home-manager は /etc を扱えないため、WSL 上の NixOS 以外の
# ホストで Codex の system config (etc/codex/config.toml) を置くために使う。
#
# 配置は cloud-setup.sh の setup-script 経路と同じ関数で行う。既存の
# /etc/codex/config.toml は初回だけ .dotfiles-backup へ退避したうえで TOML として
# overlay し、管理外の key を保持する。
#
# /etc を書き換えるため root で実行する。yq と jq を要するため、開発シェルの PATH を
# 引き継いで起動する。
#
#   使用方法: sudo env "PATH=$PATH" scripts/install-etc.sh
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "エラー: root で実行してください。" >&2
  echo "  sudo env \"PATH=\$PATH\" scripts/install-etc.sh" >&2
  exit 1
fi

for command in yq jq; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "エラー: $command が見つかりません。開発シェルの PATH を引き継いで実行してください。" >&2
    exit 1
  fi
done

script_dir=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$script_dir/.." && pwd)

# shellcheck source=scripts/cloud-home.sh
. "$script_dir/cloud-home.sh"

note() {
  printf '   %s\n' "$1"
}

dotfiles_install_etc "$repo" /etc
