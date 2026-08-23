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
  nixos-wsl <rev>                  flake.nix の NixOS-WSL を更新する
  image <バージョン> <ダイジェスト>  Dockerfile のベースイメージを更新する
  action <owner/repo> <sha>        ワークフローの action を更新する
  nix-installer <バージョン> <sha256> README の Nix 導入手順を更新する
  wsl-image <distro> <バージョン> <url> <sha256>
                                   WSL の配布イメージを更新する (distro: nixos | ubuntu)

値の取得:
  nixpkgs        curl -sL https://channels.nixos.org/nixos-26.05/git-revision
  home-manager   https://github.com/nix-community/home-manager の release-26.05 の HEAD
  nixos-wsl      https://github.com/nix-community/NixOS-WSL の release-26.05 上の
                 タグが指すコミット SHA。nixpkgs のリリースと系列を揃える
  image          docker buildx imagetools inspect nixos/nix:<バージョン>
  action         https://github.com/<owner>/<repo> の対象タグが指すコミット SHA
  nix-installer  https://releases.nixos.org/nix/nix-<バージョン>/ の .sha256
  wsl-image      nixos:  https://github.com/nix-community/NixOS-WSL/releases の
                         nixos.wsl と、GitHub API が返すアセットのダイジェスト
                 ubuntu: https://raw.githubusercontent.com/microsoft/WSL/master/
                         distributions/DistributionInfo.json の Amd64Url (Url と Sha256)

いずれも更新後は make check を実行する。flake の入力 (nixpkgs / home-manager /
nixos-wsl) は flake.lock の再生成が必要であり、make bump / make bump-hm /
make bump-wsl から呼ぶこと。
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

# PowerShell のハッシュテーブルのうち、指定した distro のブロック内のみを書き換える。
# 行単位の置換では他の distro の同名のキーにも当たるため、ブロックの範囲を見る。
#
# 前置部分 (インデントとキーと =) はそのまま残し、引用符の内側だけを組み立て直す。
# キーの位置揃えを保つため。
#
# awk を使用しない。nix/packages.nix に含めていないため、開発シェルの外 (Docker の
# profile 等) では解決できないため。
replace_ps_image() {
  local path=$1 block=$2 version=$3 url=$4 sha256=$5
  local in_block=0 replaced=0
  local line prefix value
  local output=()

  while IFS= read -r line; do
    if [[ $line =~ ^[[:space:]]*${block}[[:space:]]*=[[:space:]]*@\{ ]]; then
      in_block=1
    elif [ "$in_block" -eq 1 ] && [[ $line =~ ^[[:space:]]*\} ]]; then
      in_block=0
    fi

    value=""
    if [ "$in_block" -eq 1 ]; then
      if [[ $line =~ ^([[:space:]]*Version[[:space:]]*=[[:space:]]*) ]]; then
        prefix=${BASH_REMATCH[1]}
        value=$version
      elif [[ $line =~ ^([[:space:]]*Url[[:space:]]*=[[:space:]]*) ]]; then
        prefix=${BASH_REMATCH[1]}
        value=$url
      elif [[ $line =~ ^([[:space:]]*Sha256[[:space:]]*=[[:space:]]*) ]]; then
        prefix=${BASH_REMATCH[1]}
        value=$sha256
      fi
    fi

    if [ -n "$value" ]; then
      output+=("${prefix}'${value}'")
      replaced=$((replaced + 1))
    else
      output+=("$line")
    fi
  done <"$path"

  if [ "$replaced" -ne 3 ]; then
    echo "エラー: $path に $block の Version / Url / Sha256 が揃って見つかりません。" >&2
    echo "  見つかった数: $replaced (3 件必要)" >&2
    exit 1
  fi

  printf '%s\n' "${output[@]}" >"$path"
  echo "  更新    $path ($block の配布イメージ)"
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

  nixos-wsl)
    require_args 1 "$#"
    require_format "$1" '^[0-9a-f]{40}$' "40 桁のリビジョン"
    replace_in_file flake.nix \
      "s|github:nix-community/NixOS-WSL/[0-9a-f]{40}|github:nix-community/NixOS-WSL/$1|" \
      "NixOS-WSL のリビジョン"
    echo "リビジョンに対応するタグを示すコメントも併せて更新すること。"
    echo "flake.lock の再生成が必要です (make bump-wsl が続けて実行します)。"
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
    # Ubuntu 経路の provision も同じ配布物を導入する。README と食い違うと経路に
    # よって異なる版が入るため、同時に書き換える (一致は check-pins.sh が検査する)。
    replace_in_file scripts/wsl-provision.sh \
      "s|^readonly NIX_VERSION=.*|readonly NIX_VERSION=$1|" \
      "provision の Nix のバージョン"
    replace_in_file scripts/wsl-provision.sh \
      "s|^readonly NIX_SHA256=.*|readonly NIX_SHA256=$2|" \
      "provision の Nix の sha256"
    echo "Dockerfile の ARG NIX_VERSION も一致させること。"
    ;;

  wsl-image)
    require_args 4 "$#"
    require_format "$1" '^(nixos|ubuntu)$' "distro (nixos または ubuntu)"
    require_format "$2" '^[0-9][0-9A-Za-z._-]*$' "バージョン"
    require_format "$3" "^https://[^']+$" "https で始まる URL"
    require_format "$4" '^[0-9a-f]{64}$' "64 桁の sha256"
    replace_ps_image scripts/wsl-bootstrap.ps1 "$1" "$2" "$3" "$4"
    echo "配布元の隣にあるチェックサムファイルではなく、上記の値が検証の基準となる。"
    ;;

  *)
    echo "エラー: 対象が不明です: $target" >&2
    echo >&2
    usage >&2
    exit 1
    ;;
esac
