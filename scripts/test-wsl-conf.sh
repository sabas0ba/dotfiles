#!/usr/bin/env bash
#
# scripts/wsl-provision.sh の /etc/wsl.conf のマージを検査する。
#
# 対象は本リポジトリで唯一の非自明なテキスト処理である。イメージが出荷時に持つ設定を
# 消さずに、自分が管理するキーだけを差し替えることが要件であり、それを満たすかは
# 読んだだけでは分からないため、入力と期待する出力の組で確かめる。
#
# nix flake check から実行される (nix/checks.nix)。作業ディレクトリは書き込めない
# 場合があるため、一時ディレクトリを使用する。
#
#   使用方法: scripts/test-wsl-conf.sh
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
provision="$script_dir/wsl-provision.sh"

if [ ! -x "$provision" ]; then
  echo "エラー: $provision が実行できません。" >&2
  exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

failures=0
case_number=0

# 入力を与えて実行し、出力が期待と一致することを確かめる。入力に '-' を与えた場合は
# ファイルを作らず、存在しない状態から始める。
check_case() {
  local name=$1 input=$2 expected=$3
  local path actual

  case_number=$((case_number + 1))
  path="$work/case-$case_number.conf"

  if [ "$input" != '-' ]; then
    printf '%s' "$input" >"$path"
  fi

  bash "$provision" wslconf nixos "$path"
  actual=$(cat "$path")

  if [ "$actual" = "$expected" ]; then
    printf '  ok      %s\n' "$name"
    return
  fi

  printf '  NG      %s\n' "$name"
  failures=$((failures + 1))
  printf '--- 期待 ---\n%s\n--- 実際 ---\n%s\n---\n' "$expected" "$actual"
}

# 二度適用しても結果が変わらないこと。provision は再実行できる必要がある。
check_idempotent() {
  local name=$1 input=$2
  local path first second

  case_number=$((case_number + 1))
  path="$work/case-$case_number.conf"
  printf '%s' "$input" >"$path"

  bash "$provision" wslconf nixos "$path"
  first=$(cat "$path")
  bash "$provision" wslconf nixos "$path"
  second=$(cat "$path")

  if [ "$first" = "$second" ]; then
    printf '  ok      %s\n' "$name"
    return
  fi

  printf '  NG      %s\n' "$name"
  failures=$((failures + 1))
  printf '--- 1 回目 ---\n%s\n--- 2 回目 ---\n%s\n---\n' "$first" "$second"
}

check_case '存在しない場合に 3 つのセクションを作る' '-' \
  '# WSL の設定。scripts/wsl-provision.sh が管理するキーを含む。
[automount]
enabled = false
[interop]
enabled = false
appendWindowsPath = false
[user]
default = nixos'

check_case '管理外のセクションを残す' \
  '[boot]
systemd = true
' \
  '[boot]
systemd = true
[automount]
enabled = false
[interop]
enabled = false
appendWindowsPath = false
[user]
default = nixos'

check_case '管理対象のセクション内で、管理外のキーを残す' \
  '[automount]
enabled = true
root = /windows
options = metadata
' \
  '[automount]
root = /windows
options = metadata
enabled = false
[interop]
enabled = false
appendWindowsPath = false
[user]
default = nixos'

check_case '既存の値を差し替える' \
  '[interop]
enabled = true
appendWindowsPath = true
[user]
default = ubuntu
' \
  '[interop]
enabled = false
appendWindowsPath = false
[user]
default = nixos
[automount]
enabled = false'

check_idempotent '二度適用しても変わらない (管理外のセクションあり)' \
  '[boot]
systemd = true
[automount]
enabled = true
root = /windows
'

check_idempotent '二度適用しても変わらない (空のファイル)' ''

echo

if [ "$failures" -ne 0 ]; then
  echo "wsl.conf のマージに誤りがあります ($failures 件)。" >&2
  exit 1
fi

echo "wsl.conf のマージは期待どおりです ($case_number 件)。"
