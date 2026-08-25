#!/usr/bin/env bash
#
# 開発環境が構成されているかを確認するスモークテスト。
#
# 検査するのは次の 2 点である。
#
#   1. 選択した profile のコマンド契約が揃っていること
#   2. その実体が Nix の store にあること
#
# 1 だけではホストに元から入っているツールを拾ってしまうため、2 を併せて見る。
# 実体まで辿るのは、cloud-setup.sh の setup-script 経路が /usr/local/bin へ張った
# symlink 経由でも成立させるためである。
#
# 開発シェルの内部にいるか (DOTFILES_ENV) は判定に用いない。setup-script 経路には
# 環境変数を引き渡す手段が無く (docs/setup.md)、正規の構成でありながら当該変数を
# 持たないためである。どの状態にあるかは最後に表示する。
#
# ホストの `nix develop` 内でも、Docker コンテナ内でも、setup-script 経路が配置した
# 状態でも同一の結果となる。
#
#   使用方法: scripts/check-env.sh
set -euo pipefail

# コマンド契約は nix/packages.nix から生成する。開発シェルでは manifest のパスを
# 環境変数で受け取り、nix build の profile や Cloud Setup の配置では profile に含む
# metadata command から取得する。
required_commands=()
if [ -n "${DOTFILES_COMMAND_MANIFEST:-}" ]; then
  if [ ! -r "$DOTFILES_COMMAND_MANIFEST" ]; then
    echo "コマンド契約を読めません: $DOTFILES_COMMAND_MANIFEST" >&2
    exit 1
  fi

  mapfile -t required_commands <"$DOTFILES_COMMAND_MANIFEST"
elif command -v dotfiles-toolchain-info >/dev/null 2>&1; then
  mapfile -t required_commands < <(dotfiles-toolchain-info commands)
else
  echo "コマンド契約が見つかりません。nix develop .#default 等で実行してください。" >&2
  exit 1
fi

validated_commands=()
for cmd in "${required_commands[@]}"; do
  [ -n "$cmd" ] || continue
  if [[ ! "$cmd" =~ ^[a-zA-Z0-9_.+-]+$ ]]; then
    echo "コマンド契約に不正な名前があります: $cmd" >&2
    exit 1
  fi
  validated_commands+=("$cmd")
done
required_commands=("${validated_commands[@]}")

if [ "${#required_commands[@]}" -eq 0 ]; then
  echo "コマンド契約が空です。" >&2
  exit 1
fi

# Nix の store の位置。既定から変えている環境のために NIX_STORE_DIR を見る。
store_dir=${NIX_STORE_DIR:-/nix/store}

# symlink を辿る手段。coreutils を持たない PATH で実行された場合は空になる。
resolver=
if command -v realpath >/dev/null 2>&1; then
  resolver=realpath
elif command -v readlink >/dev/null 2>&1; then
  resolver=readlink
else
  echo "注意: realpath も readlink も無く、symlink の実体を辿れません。" >&2
  echo "      symlink 経由で解決したコマンドは store の外として扱われます。" >&2
  echo >&2
fi

# symlink を辿って実体のパスを得る。
#
# 解決できない場合は与えられたパスをそのまま返す。呼び出し側では store の外として
# 扱われ、何が解決されたのかが出力に残る。
resolve_path() {
  local path=$1

  case "$resolver" in
    realpath) realpath -e -- "$path" 2>/dev/null || printf '%s' "$path" ;;
    readlink) readlink -f -- "$path" 2>/dev/null || printf '%s' "$path" ;;
    *) printf '%s' "$path" ;;
  esac
}

missing=()
foreign=()

for cmd in "${required_commands[@]}"; do
  if ! path=$(command -v "$cmd" 2>/dev/null); then
    printf '  MISSING %-12s\n' "$cmd"
    missing+=("$cmd")
    continue
  fi

  real=$(resolve_path "$path")

  case "$real" in
    "$store_dir"/*)
      if [ "$real" = "$path" ]; then
        printf '  ok      %-12s %s\n' "$cmd" "$path"
      else
        printf '  ok      %-12s %s -> %s\n' "$cmd" "$path" "$real"
      fi
      ;;
    *)
      printf '  FOREIGN %-12s %s\n' "$cmd" "$real"
      foreign+=("$cmd")
      ;;
  esac
done

echo

if [ "${#missing[@]}" -ne 0 ]; then
  echo "不足しているコマンド: ${missing[*]}" >&2
  echo "開発環境の外で実行されている可能性があります。'nix develop' または 'direnv allow' を実行してください。" >&2
  exit 1
fi

if [ "${#foreign[@]}" -ne 0 ]; then
  echo "Nix の store 由来でないコマンド: ${foreign[*]}" >&2
  echo "ホストのツールが混ざっています。同名のコマンドが PATH の前方にある可能性があります。" >&2
  echo "'nix develop' または 'direnv allow' で開発シェルに入ってください。" >&2
  exit 1
fi

# どの状態で揃っているかを示す。判定には用いない。
profile_name=${DOTFILES_TOOLCHAIN_PROFILE:-}
if [ -z "$profile_name" ] && command -v dotfiles-toolchain-info >/dev/null 2>&1; then
  profile_name=$(dotfiles-toolchain-info name)
fi
profile_name=${profile_name:-unknown}

if [ "${DOTFILES_ENV:-}" = nix-develop ]; then
  state="開発シェル内、profile=$profile_name"
else
  state="開発シェル外、profile=$profile_name、PATH 上のツールが store を指している"
fi

# WSL 上では Windows 側からの隔離が成立していることも環境の要件とする。
# WSL 以外では当該スクリプトが何も検査せずに成功する。
"$(dirname "$0")/check-wsl-isolation.sh"

echo "開発環境は正常です ($state)。"
