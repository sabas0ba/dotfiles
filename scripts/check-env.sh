#!/usr/bin/env bash
#
# 開発環境が構成されているかを確認するスモークテスト。
#
# 検査するのは次の 2 点である。
#
#   1. nix/packages.nix のツールがコマンドとして揃っていること
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

# nix/packages.nix に含まれるツールのうち、コマンドとして使用するもの。
# 本リストを変更した場合は nix/packages.nix 側にも同じものを追加する。
required_commands=(
  bash
  deadnix
  direnv
  fd
  git
  jq
  make
  nil
  nixfmt
  rg
  shellcheck
  shfmt
  statix
  tree
  yq
)

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
if [ "${DOTFILES_ENV:-}" = nix-develop ]; then
  state="開発シェル内、DOTFILES_ENV=nix-develop"
else
  state="開発シェル外、PATH 上のツールが store を指している"
fi

# WSL 上では Windows 側からの隔離が成立していることも環境の要件とする。
# WSL 以外では当該スクリプトが何も検査せずに成功する。
"$(dirname "$0")/check-wsl-isolation.sh"

echo "開発環境は正常です ($state)。"
