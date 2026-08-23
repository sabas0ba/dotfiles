#!/usr/bin/env bash
#
# WSL 上で動作している場合に、Windows 側から隔離されていることを検査する。
#
# 隔離の目的は、当環境で動作するエージェントやスクリプトが、ホスト側のシステム
# ファイルや、認証済みの CLI (gh / az / aws / gcloud 等) へ到達しないようにすること
# である。規約ではなく到達経路の遮断によって担保する。
#
# 設定の実体は 2 か所にある。NixOS では nix/wsl.nix (宣言的)、それ以外の
# ディストリビューションでは /etc/wsl.conf (scripts/wsl-bootstrap.ps1 が配置)。
# 本スクリプトは、いずれの経路であっても満たすべき結果を定義する検査である。
#
# WSL 上でない場合は何も検査せずに成功する。Docker コンテナおよび CI で
# scripts/check-env.sh から呼ばれるため。
#
#   使用方法: scripts/check-wsl-isolation.sh
set -euo pipefail

# WSL の判定。WSL2 のカーネルは osrelease に microsoft を含む。環境変数
# WSL_DISTRO_NAME は WSL が設定するが、systemd 配下のサービス等では継承されない
# ことがあるため、osrelease を主たる判定に用いる。
is_wsl() {
  if [ -n "${WSL_DISTRO_NAME:-}" ]; then
    return 0
  fi
  if [ -r /proc/sys/kernel/osrelease ] && grep -qi microsoft /proc/sys/kernel/osrelease; then
    return 0
  fi
  return 1
}

if ! is_wsl; then
  echo "  skip    WSL 上ではないため隔離の検査を省略する"
  exit 0
fi

errors=0

fail() {
  printf '  NG      %s\n' "$1"
  errors=$((errors + 1))
}

ok() {
  printf '  ok      %s\n' "$1"
}

# --- Windows のファイルシステムがマウントされていないこと --------------------
#
# 2 つの観点で見る。
#
#   ドライブ文字  automount が有効な場合、/mnt/c のようにドライブ文字のマウント
#                 ポイントが現れる
#   filesystem    automount.root を変更した場合、ドライブ文字だけでは漏れる。WSL が
#                 Windows 側を見せる際の filesystem は 9p (WSL2) または drvfs (WSL1)
#
# /mnt/wsl と /usr/lib/wsl は WSL 自身が使用する領域であり、automount とは独立に
# 現れる。前者は distro 間で共有される領域、後者はホストのドライバとライブラリで
# あって Windows のユーザーデータではないため、対象から除く。
#
# awk を使用しない。nix/packages.nix に含めていないため、開発シェルの外 (Docker の
# profile 等) では解決できないため。

drive_mounts=()
foreign_mounts=()

while read -r _device mountpoint fstype _options; do
  case "$mountpoint" in
    /mnt/wsl | /mnt/wsl/* | /usr/lib/wsl | /usr/lib/wsl/*) continue ;;
    /mnt/[a-zA-Z]) drive_mounts+=("$mountpoint") ;;
  esac

  case "$fstype" in
    9p | drvfs | v9fs) foreign_mounts+=("$mountpoint") ;;
  esac
done </proc/mounts

if [ "${#drive_mounts[@]}" -ne 0 ]; then
  for mountpoint in "${drive_mounts[@]}"; do
    fail "Windows のドライブがマウントされている: $mountpoint"
  done
else
  ok "Windows のドライブがマウントされていない"
fi

if [ "${#foreign_mounts[@]}" -ne 0 ]; then
  for mountpoint in "${foreign_mounts[@]}"; do
    fail "Windows 側のファイルシステムがマウントされている: $mountpoint"
  done
else
  ok "Windows 側のファイルシステムが露出していない"
fi

# --- Windows の実行ファイルを起動できないこと --------------------------------
#
# interop が有効な場合、binfmt_misc に PE 形式のハンドラが登録され、Linux 側から
# Windows の実行ファイルをそのまま起動できる。

interop_handlers=()
for handler in /proc/sys/fs/binfmt_misc/WSLInterop /proc/sys/fs/binfmt_misc/WSLInterop-late; do
  if [ -e "$handler" ]; then
    interop_handlers+=("$handler")
  fi
done

if [ "${#interop_handlers[@]}" -ne 0 ]; then
  for handler in "${interop_handlers[@]}"; do
    fail "Windows の実行ファイルのハンドラが登録されている: $handler"
  done
else
  ok "Windows の実行ファイルのハンドラが登録されていない"
fi

# --- Windows の PATH が流入していないこと ------------------------------------
#
# appendWindowsPath が有効な場合、Windows 側の PATH が追記される。ここに認証済みの
# CLI が含まれうる。

windows_path_entries=()
IFS=':' read -r -a path_entries <<<"$PATH"

for entry in "${path_entries[@]}"; do
  case "$entry" in
    /mnt/wsl | /mnt/wsl/*) continue ;;
    /mnt/*) windows_path_entries+=("$entry") ;;
  esac
done

if [ "${#windows_path_entries[@]}" -ne 0 ]; then
  for entry in "${windows_path_entries[@]}"; do
    fail "PATH に Windows 側の要素が含まれている: $entry"
  done
else
  ok "PATH に Windows 側の要素が含まれていない"
fi

# --- 代表的な Windows のコマンドが解決できないこと ---------------------------
#
# 上記 3 点の結果として成り立つ性質であるが、想定していない経路 (別名の配置、
# ラッパの設置等) が残っていないことを直接確認する。

resolved_commands=0
for cmd in cmd.exe powershell.exe pwsh.exe wsl.exe explorer.exe; do
  if command -v "$cmd" >/dev/null 2>&1; then
    fail "Windows のコマンドが解決できる: $cmd ($(command -v "$cmd"))"
    resolved_commands=$((resolved_commands + 1))
  fi
done

if [ "$resolved_commands" -eq 0 ]; then
  ok "Windows のコマンドが解決できない"
fi

echo

if [ "$errors" -ne 0 ]; then
  echo "WSL の隔離が成立していません ($errors 件)。" >&2
  echo "NixOS では nix/wsl.nix の wsl.wslConf / wsl.interop を確認し、" >&2
  echo "make wsl-switch を実行してください。他のディストリビューションでは" >&2
  echo "/etc/wsl.conf を確認してください。" >&2
  echo "いずれも Windows 側で wsl.exe --terminate ${WSL_DISTRO_NAME:-<名前>} を" >&2
  echo "実行して再起動するまで反映されません。" >&2
  exit 1
fi

echo "WSL は Windows 側から隔離されています。"
