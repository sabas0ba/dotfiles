#!/usr/bin/env bash
#
# 固定した参照を更新する。
#
# 更新は意図的な操作であるため、上流の最新版を自動で取得して書き換えることはしない。
# 値は呼び出し側が明示的に与える。取得方法は各サブコマンドのヘルプに示す。
#
# 本スクリプトはファイルの書き換えのみを行う。flake.lock の再生成は Makefile 側で
# 行う (make bump / make bump-hm)。書き換え後は make check を実行すること。
# Nix 本体に関する固定は複数ファイルにまたがるため、nix-release で一括更新する。
#
#   使用方法: scripts/update-pins.sh <対象> <値...>
set -euo pipefail

usage() {
  cat <<'USAGE'
使用方法: scripts/update-pins.sh <対象> <値...>

対象:
  nixpkgs <rev>                    flake.nix の nixpkgs を更新する
  home-manager <rev>               flake.nix の home-manager を更新する
  nixos-wsl <rev> <tag>            flake.nix の NixOS-WSL を更新する
  nix-release <バージョン> <ダイジェスト> <sha256>
                                    Nix の版、ベースイメージ、導入用 tarball を一括更新する
  action <owner/repo> <sha>        ワークフローの action を更新する
  wsl-image <distro> <バージョン> <url> <sha256>
                                   WSL の配布イメージを更新する (distro: nixos | ubuntu)

値の取得:
  nixpkgs        curl -sL https://channels.nixos.org/nixos-26.05/git-revision
  home-manager   https://github.com/nix-community/home-manager の release-26.05 の HEAD
  nixos-wsl      https://github.com/nix-community/NixOS-WSL の release-26.05 上の
                 タグ名と、そのタグが指すコミット SHA。nixpkgs の系列と揃える
  nix-release    image digest: docker buildx imagetools inspect nixos/nix:<バージョン>
                  installer sha256: https://releases.nixos.org/nix/nix-<バージョン>/
                  の x86_64-linux 用 .sha256
  action         https://github.com/<owner>/<repo> の対象タグが指すコミット SHA
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

# Nix release の固定は Dockerfile、導入手順、導入スクリプトに分散している。元ファイルを
# 逐次書き換えると、後続の置換に失敗した時点で不整合な working tree が残る。そのため
# 全ファイルを .work 以下へ複製し、対象と結果を検証してから反映する。
transaction_dir=""
transaction_committing=0
transaction_files=()
transaction_applied_files=()

cleanup_transaction() {
  local status=$?
  local path

  if [ "$transaction_committing" -eq 1 ] && [ "$status" -ne 0 ]; then
    echo "エラー: 更新の反映に失敗したため、変更済みのファイルを元に戻します。" >&2
    for path in "${transaction_applied_files[@]}"; do
      if ! cp -p -- "$transaction_dir/original/$path" "$path"; then
        echo "エラー: $path を元に戻せませんでした。" >&2
      fi
    done
  fi

  if [[ $transaction_dir == .work/update-pins.* ]] && [ -d "$transaction_dir" ]; then
    rm -rf -- "$transaction_dir"
  fi

  return "$status"
}

trap cleanup_transaction EXIT

begin_transaction() {
  local path

  mkdir -p .work
  transaction_dir=$(mktemp -d .work/update-pins.XXXXXX)

  for path in "$@"; do
    if [ ! -f "$path" ]; then
      echo "エラー: 更新対象のファイルがありません: $path" >&2
      exit 1
    fi

    mkdir -p \
      "$transaction_dir/original/$(dirname "$path")" \
      "$transaction_dir/staged/$(dirname "$path")"
    cp -p -- "$path" "$transaction_dir/original/$path"
    cp -p -- "$path" "$transaction_dir/staged/$path"
    transaction_files+=("$path")
  done
}

replace_in_transaction() {
  local path=$1 pattern=$2 expression=$3 desired=$4 label=$5
  local staged matches current temporary

  staged="$transaction_dir/staged/$path"
  matches=$(grep -cE -- "$pattern" "$staged" || true)
  if [ "$matches" -ne 1 ]; then
    echo "エラー: $path に $label が一意に見つかりません (見つかった数: $matches)。" >&2
    exit 1
  fi

  current=$(grep -E -- "$pattern" "$staged")
  current=${current%$'\r'}
  if [ "$current" = "$desired" ]; then
    return
  fi

  temporary="$staged.new"
  sed -E "$expression" "$staged" >"$temporary"
  mv -- "$temporary" "$staged"
}

commit_transaction() {
  local path prepared
  local changed=()

  for path in "${transaction_files[@]}"; do
    if ! cmp -s -- "$transaction_dir/original/$path" "$transaction_dir/staged/$path"; then
      changed+=("$path")
    fi
  done

  if [ "${#changed[@]}" -eq 0 ]; then
    echo "エラー: 指定された固定はすべて既に同じ値です。変更はありません。" >&2
    exit 1
  fi

  # 反映前に全ファイルの一時ファイルを準備する。反映中に失敗した場合は EXIT trap が
  # original の複製から復元する。
  for path in "${changed[@]}"; do
    prepared="$transaction_dir/prepared/$path"
    mkdir -p "$(dirname "$prepared")"
    cp -p -- "$transaction_dir/staged/$path" "$prepared"
  done

  transaction_committing=1
  for path in "${changed[@]}"; do
    mv -- "$transaction_dir/prepared/$path" "$path"
    transaction_applied_files+=("$path")
  done
  transaction_committing=0

  for path in "${changed[@]}"; do
    echo "  更新    $path"
  done
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
    require_args 2 "$#"
    require_format "$1" '^[0-9a-f]{40}$' "40 桁のリビジョン"
    require_format "$2" '^[0-9][0-9A-Za-z._-]*$' "タグ"
    # URL と同一行のタグコメントを 1 回の置換で更新する。一方だけを先に書き換えると、
    # 後続の置換に失敗した際に rev とタグが食い違った状態を残すため。
    replace_in_file flake.nix \
      "s|github:nix-community/NixOS-WSL/[0-9a-f]{40}\";[[:space:]]*#[[:space:]]*[0-9][0-9A-Za-z._-]*$|github:nix-community/NixOS-WSL/$1\"; # $2|" \
      "NixOS-WSL のリビジョンとタグ"
    echo "flake.lock の再生成が必要です (make bump-wsl が続けて実行します)。"
    ;;

  nix-release)
    require_args 3 "$#"
    require_format "$1" '^[0-9][0-9A-Za-z._-]*$' "バージョン"
    require_format "$2" '^sha256:[0-9a-f]{64}$' "sha256: から始まるダイジェスト"
    require_format "$3" '^[0-9a-f]{64}$' "64 桁の sha256"

    begin_transaction Dockerfile docs/setup.md scripts/nix-pin.sh
    replace_in_transaction Dockerfile \
      '^ARG NIX_VERSION=[^[:space:]]+[[:space:]]*$' \
      "s|^(ARG NIX_VERSION=)[^[:space:]]+|\\1$1|" \
      "ARG NIX_VERSION=$1" \
      "ベースイメージのバージョン"
    replace_in_transaction Dockerfile \
      '^ARG NIX_IMAGE_DIGEST=sha256:[0-9a-f]{64}[[:space:]]*$' \
      "s|^(ARG NIX_IMAGE_DIGEST=)[^[:space:]]+|\\1$2|" \
      "ARG NIX_IMAGE_DIGEST=$2" \
      "ベースイメージのダイジェスト"
    replace_in_transaction docs/setup.md \
      '^NIX_VERSION=[^[:space:]]+[[:space:]]*$' \
      "s|^(NIX_VERSION=)[^[:space:]]+|\\1$1|" \
      "NIX_VERSION=$1" \
      "Nix インストーラのバージョン"
    replace_in_transaction docs/setup.md \
      '^NIX_SHA256=[0-9a-f]{64}[[:space:]]*$' \
      "s|^(NIX_SHA256=)[^[:space:]]+|\\1$3|" \
      "NIX_SHA256=$3" \
      "Nix インストーラの sha256"
    replace_in_transaction scripts/nix-pin.sh \
      '^NIX_VERSION=[^[:space:]]+[[:space:]]*$' \
      "s|^(NIX_VERSION=)[^[:space:]]+|\\1$1|" \
      "NIX_VERSION=$1" \
      "導入する Nix のバージョン"
    replace_in_transaction scripts/nix-pin.sh \
      '^NIX_SHA256=[0-9a-f]{64}[[:space:]]*$' \
      "s|^(NIX_SHA256=)[^[:space:]]+|\\1$3|" \
      "NIX_SHA256=$3" \
      "導入する Nix の sha256"
    commit_transaction
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

  image | nix-installer)
    echo "エラー: $target は個別更新で固定が不整合になるため廃止しました。" >&2
    echo "nix-release <バージョン> <イメージのダイジェスト> <インストーラの sha256> を使用してください。" >&2
    exit 1
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
