#!/usr/bin/env bash
#
# 固定した参照を更新する。
#
# 更新は意図的な操作であるため、上流の最新版を自動で取得して書き換えることはしない。
# 値は呼び出し側が明示的に与える。取得方法は各サブコマンドのヘルプに示す。
#
# 本スクリプトはファイルの書き換えのみを行う。flake.lock の再生成は Makefile 側で
# 行う (make bump / make bump-hm)。書き換え後は make check を実行すること。
#
#   使用方法: scripts/update-pins.sh <対象> <値...>
set -euo pipefail

usage() {
  cat <<'USAGE'
使用方法: scripts/update-pins.sh <対象> <値...>

対象:
  nixpkgs <rev>                    flake.nix の nixpkgs を更新する
  home-manager <rev>               flake.nix の home-manager を更新する
  image <バージョン> <ダイジェスト>  Dockerfile のベースイメージを更新する
  action <owner/repo> <sha>        ワークフローの action を更新する
  nix-installer <バージョン> <sha256> README の Nix 導入手順を更新する

値の取得:
  nixpkgs        curl -sL https://channels.nixos.org/nixos-26.05/git-revision
  home-manager   https://github.com/nix-community/home-manager の release-26.05 の HEAD
  image          docker buildx imagetools inspect nixos/nix:<バージョン>
  action         https://github.com/<owner>/<repo> の対象タグが指すコミット SHA
  nix-installer  https://releases.nixos.org/nix/nix-<バージョン>/ の .sha256

いずれも更新後は make check を実行する。nixpkgs と home-manager は
flake.lock の再生成が必要であり、make bump / make bump-hm から呼ぶこと。
USAGE
}

if [ "$#" -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  usage
  exit 0
fi

target=$1
shift

# 与えられた値が期待する形式であることを確認する。誤った値でファイルを壊さないため。
require_format() {
  local value=$1 pattern=$2 description=$3
  if [[ ! $value =~ $pattern ]]; then
    echo "エラー: $description の形式ではありません: $value" >&2
    exit 1
  fi
}

require_args() {
  local expected=$1 actual=$2
  if [ "$actual" -ne "$expected" ]; then
    echo "エラー: 引数の個数が異なります (必要: $expected, 与えられた数: $actual)" >&2
    echo >&2
    usage >&2
    exit 1
  fi
}

# ファイルを書き換える。置換が 1 件も発生しなかった場合は失敗させる。対象の記述が
# 変わっていた場合に、変更されていないことに気付かないまま進むのを防ぐ。
replace_in_file() {
  local path=$1 expression=$2 label=$3
  local before after

  before=$(cat "$path")
  after=$(printf '%s\n' "$before" | sed -E "$expression")

  if [ "$before" = "$after" ]; then
    echo "エラー: $path に $label の変更対象が見つからないか、既に同じ値です。" >&2
    exit 1
  fi

  printf '%s\n' "$after" >"$path"
  echo "  更新    $path ($label)"
}

case "$target" in
  nixpkgs)
    require_args 1 "$#"
    require_format "$1" '^[0-9a-f]{40}$' "40 桁のリビジョン"
    replace_in_file flake.nix \
      "s|github:NixOS/nixpkgs/[0-9a-f]{40}|github:NixOS/nixpkgs/$1|" \
      "nixpkgs のリビジョン"
    echo "flake.lock の再生成が必要です (make bump が続けて実行します)。"
    ;;

  home-manager)
    require_args 1 "$#"
    require_format "$1" '^[0-9a-f]{40}$' "40 桁のリビジョン"
    replace_in_file flake.nix \
      "s|github:nix-community/home-manager/[0-9a-f]{40}|github:nix-community/home-manager/$1|" \
      "home-manager のリビジョン"
    echo "flake.lock の再生成が必要です (make bump-hm が続けて実行します)。"
    ;;

  image)
    require_args 2 "$#"
    require_format "$1" '^[0-9][0-9A-Za-z._-]*$' "バージョン"
    require_format "$2" '^sha256:[0-9a-f]{64}$' "sha256: から始まるダイジェスト"
    replace_in_file Dockerfile \
      "s|^ARG NIX_VERSION=.*|ARG NIX_VERSION=$1|" \
      "ベースイメージのバージョン"
    replace_in_file Dockerfile \
      "s|^ARG NIX_IMAGE_DIGEST=.*|ARG NIX_IMAGE_DIGEST=$2|" \
      "ベースイメージのダイジェスト"
    echo "README の NIX_VERSION も一致させること (scripts/check-pins.sh が検査します)。"
    ;;

  action)
    require_args 2 "$#"
    require_format "$1" '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$' "owner/repo"
    require_format "$2" '^[0-9a-f]{40}$' "40 桁のコミット SHA"
    updated=0
    while IFS= read -r workflow; do
      if grep -qE "uses:[[:space:]]*$1@" "$workflow"; then
        replace_in_file "$workflow" \
          "s|(uses:[[:space:]]*$1)@[^[:space:]]+|\\1@$2|" \
          "$1 のコミット SHA"
        updated=$((updated + 1))
      fi
    done < <(find .github/workflows -type f \( -name '*.yml' -o -name '*.yaml' \) | sort)

    if [ "$updated" -eq 0 ]; then
      echo "エラー: $1 を使用しているワークフローがありません。" >&2
      exit 1
    fi
    echo "action のバージョンを示すコメントも併せて更新すること。"
    ;;

  nix-installer)
    require_args 2 "$#"
    require_format "$1" '^[0-9][0-9A-Za-z._-]*$' "バージョン"
    require_format "$2" '^[0-9a-f]{64}$' "64 桁の sha256"
    replace_in_file README.md \
      "s|^NIX_VERSION=.*|NIX_VERSION=$1|" \
      "Nix インストーラのバージョン"
    replace_in_file README.md \
      "s|^NIX_SHA256=.*|NIX_SHA256=$2|" \
      "Nix インストーラの sha256"
    echo "Dockerfile の ARG NIX_VERSION も一致させること。"
    ;;

  *)
    echo "エラー: 対象が不明です: $target" >&2
    echo >&2
    usage >&2
    exit 1
    ;;
esac
