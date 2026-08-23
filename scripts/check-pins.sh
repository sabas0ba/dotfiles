#!/usr/bin/env bash
#
# 外部の成果物が一意に固定されているかを検査する。
#
# 本リポジトリは、タグやブランチ名のみによる参照を固定とみなさない。タグは再割り当てが
# 可能であり、同じ参照が別の内容を指しうるため。固定の方針は README の「再現性」にある。
#
# flake の入力 (nixpkgs / home-manager) は scripts/check-lock.sh が担当する。本
# スクリプトはそれ以外を対象とする。
#
# ネットワークを使用しない。作業木の内容のみを検査する。
#
#   使用方法: scripts/check-pins.sh [リポジトリのルート]
set -euo pipefail

root=${1:-.}

if [ ! -f "$root/Dockerfile" ]; then
  echo "エラー: $root にリポジトリのルートが見つかりません。" >&2
  exit 1
fi

errors=0

fail() {
  printf '  NG      %s\n' "$1"
  errors=$((errors + 1))
}

ok() {
  printf '  ok      %s\n' "$1"
}

# --- ベースイメージ ----------------------------------------------------------
#
# FROM はタグだけでなくダイジェストでも固定する。タグは再割り当てが可能である。

from_total=0
from_pinned=0

# FROM がダイジェストを ARG 経由で参照する場合があるため、ARG の既定値に展開してから
# 判定する。既定値を持たない ARG はビルド時に差し替え可能であり、固定とみなさない。
resolve_dockerfile_args() {
  local text=$1 name value
  while IFS= read -r definition; do
    name=${definition%%=*}
    value=${definition#*=}
    text=${text//\$\{$name\}/$value}
    text=${text//\$$name/$value}
  done < <(grep -oE '^ARG[[:space:]]+[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]+' "$root/Dockerfile" |
    sed -E 's/^ARG[[:space:]]+//')
  printf '%s' "$text"
}

while IFS= read -r line; do
  from_total=$((from_total + 1))
  resolved=$(resolve_dockerfile_args "$line")
  if [[ $resolved =~ @sha256:[0-9a-f]{64} ]]; then
    from_pinned=$((from_pinned + 1))
  else
    fail "Dockerfile の FROM がダイジェストで固定されていません: $line"
  fi
done < <(grep -E '^\s*FROM\s' "$root/Dockerfile" || true)

if [ "$from_total" -eq 0 ]; then
  fail "Dockerfile に FROM が見つかりません"
elif [ "$from_pinned" -eq "$from_total" ]; then
  ok "Dockerfile の FROM がダイジェストで固定されている ($from_total 件)"
fi

# --- GitHub Actions ----------------------------------------------------------
#
# uses はコミット SHA で固定する。タグは再割り当てが可能である。
# ランナーは -latest を使用しない。更新時期を制御できないため。

workflows=()
while IFS= read -r path; do
  workflows+=("$path")
done < <(find "$root/.github/workflows" -type f \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null | sort)

if [ "${#workflows[@]}" -eq 0 ]; then
  fail ".github/workflows にワークフローが見つかりません"
fi

uses_total=0
uses_pinned=0
runner_total=0
runner_pinned=0

for workflow in "${workflows[@]}"; do
  name=${workflow#"$root/"}

  # 行末コメントを除去してから検査する。
  while IFS= read -r ref; do
    # ローカルの action (./ 始まり) は外部の成果物ではないため対象外とする。
    case "$ref" in
      ./*) continue ;;
    esac

    uses_total=$((uses_total + 1))
    if [[ $ref =~ @[0-9a-f]{40}$ ]]; then
      uses_pinned=$((uses_pinned + 1))
    else
      fail "$name の uses がコミット SHA で固定されていません: $ref"
    fi
  done < <(sed -e 's/#.*$//' "$workflow" | grep -oE 'uses:[[:space:]]*[^[:space:]]+' | sed -E 's/uses:[[:space:]]*//')

  while IFS= read -r runner; do
    runner_total=$((runner_total + 1))
    if [[ $runner == *-latest ]]; then
      fail "$name の runs-on が可変です: $runner"
    else
      runner_pinned=$((runner_pinned + 1))
    fi
  done < <(sed -e 's/#.*$//' "$workflow" | grep -oE 'runs-on:[[:space:]]*[^[:space:]]+' | sed -E 's/runs-on:[[:space:]]*//')
done

if [ "$uses_total" -ne 0 ] && [ "$uses_pinned" -eq "$uses_total" ]; then
  ok "GitHub Actions の uses がコミット SHA で固定されている ($uses_total 件)"
fi

if [ "$runner_total" -eq 0 ]; then
  fail "ワークフローに runs-on が見つかりません"
elif [ "$runner_pinned" -eq "$runner_total" ]; then
  ok "GitHub Actions のランナーがバージョンで固定されている ($runner_total 件)"
fi

# --- Nix インストーラ --------------------------------------------------------
#
# README の導入手順は、バージョンを固定し、固定した sha256 で検証する。
# バージョンは Dockerfile のベースイメージと一致させる。

readme="$root/README.md"

dockerfile_nix_version=$(
  grep -oE '^ARG NIX_VERSION=[^[:space:]]+' "$root/Dockerfile" |
    head -1 | cut -d= -f2
)

readme_nix_version=$(
  grep -oE '^NIX_VERSION=[^[:space:]]+' "$readme" |
    head -1 | cut -d= -f2
)

if [ -z "$dockerfile_nix_version" ] || [ -z "$readme_nix_version" ]; then
  fail "NIX_VERSION を Dockerfile または README から読み取れません"
elif [ "$dockerfile_nix_version" != "$readme_nix_version" ]; then
  fail "NIX_VERSION が不一致: Dockerfile=$dockerfile_nix_version README=$readme_nix_version"
else
  ok "NIX_VERSION が Dockerfile と README で一致している ($dockerfile_nix_version)"
fi

readme_nix_sha256=$(
  grep -oE '^NIX_SHA256=[0-9a-f]{64}$' "$readme" |
    head -1 | cut -d= -f2
)

if [ -n "$readme_nix_sha256" ]; then
  ok "Nix インストーラの sha256 が README に固定されている"
else
  fail "README に固定した NIX_SHA256 (64 桁) がありません"
fi

# Ubuntu 経路の provision も同じ配布物を導入する。README と値が食い違うと、経路に
# よって異なる版が入る。同一であることを検査する。
provision="$root/scripts/wsl-provision.sh"

if [ ! -f "$provision" ]; then
  fail "scripts/wsl-provision.sh が存在しません"
else
  provision_nix_version=$(
    grep -oE '^readonly NIX_VERSION=[^[:space:]]+' "$provision" |
      head -1 | cut -d= -f2
  )
  provision_nix_sha256=$(
    grep -oE '^readonly NIX_SHA256=[0-9a-f]{64}$' "$provision" |
      head -1 | cut -d= -f2
  )

  if [ -z "$provision_nix_version" ] || [ -z "$provision_nix_sha256" ]; then
    fail "scripts/wsl-provision.sh から NIX_VERSION / NIX_SHA256 を読み取れません"
  elif [ "$provision_nix_version" != "$readme_nix_version" ]; then
    fail "NIX_VERSION が不一致: wsl-provision.sh=$provision_nix_version README=$readme_nix_version"
  elif [ "$provision_nix_sha256" != "$readme_nix_sha256" ]; then
    fail "NIX_SHA256 が wsl-provision.sh と README で一致しません"
  else
    ok "Nix インストーラの固定が wsl-provision.sh と README で一致している"
  fi
fi

# 配布元から取得したチェックサムとの照合は検証にならないため、手順に含めない。
if grep -qE 'curl[^|]*\.sha256' "$readme"; then
  fail "README が配布元から取得した sha256 と照合しています (検証になりません)"
fi

# --- WSL の配布イメージ --------------------------------------------------------
#
# scripts/wsl-bootstrap.ps1 が取得するイメージは、URL と sha256 を本文に固定する。
# 配布元の隣に置かれたチェックサムファイルは配布物と同時に差し替えられるため、
# 実行時に取得して照合する方式は検証にならない。

bootstrap="$root/scripts/wsl-bootstrap.ps1"

if [ ! -f "$bootstrap" ]; then
  fail "scripts/wsl-bootstrap.ps1 が存在しません"
else
  wsl_urls=$(grep -cE "^\s*Url\s*=\s*'https://[^']+'\s*$" "$bootstrap" || true)
  wsl_urls_all=$(grep -cE "^\s*Url\s*=" "$bootstrap" || true)
  wsl_hashes=$(grep -cE "^\s*Sha256\s*=\s*'[0-9a-f]{64}'\s*$" "$bootstrap" || true)
  wsl_hashes_all=$(grep -cE "^\s*Sha256\s*=" "$bootstrap" || true)

  if [ "$wsl_urls_all" -eq 0 ]; then
    fail "scripts/wsl-bootstrap.ps1 に配布イメージの Url がありません"
  elif [ "$wsl_urls" -ne "$wsl_urls_all" ]; then
    fail "scripts/wsl-bootstrap.ps1 に https でない Url があります"
  elif [ "$wsl_hashes" -ne "$wsl_hashes_all" ]; then
    fail "scripts/wsl-bootstrap.ps1 に 64 桁でない Sha256 があります"
  elif [ "$wsl_hashes" -ne "$wsl_urls" ]; then
    fail "scripts/wsl-bootstrap.ps1 の Url と Sha256 の数が一致しません ($wsl_urls / $wsl_hashes)"
  else
    ok "WSL の配布イメージが URL と sha256 で固定されている ($wsl_urls 件)"
  fi

  # 配布元から取得したチェックサムとの照合になっていないこと。
  if grep -qiE 'Invoke-WebRequest[^\n]*(\.sha256|SHA256SUMS)' "$bootstrap"; then
    fail "scripts/wsl-bootstrap.ps1 が配布元から取得した sha256 と照合しています"
  fi

  # BOM があること。
  #
  # Windows PowerShell 5.1 は BOM の無い .ps1 をシステムの ANSI コードページとして
  # 読む。日本語環境では Shift_JIS と解釈され、UTF-8 の多バイト文字が壊れて構文
  # エラーになる。BOM は見えないため、失われたことに気付けるよう検査する。
  if [ "$(od -An -tx1 -N3 "$bootstrap" | tr -d ' \n')" = "efbbbf" ]; then
    ok "scripts/wsl-bootstrap.ps1 に UTF-8 の BOM がある"
  else
    fail "scripts/wsl-bootstrap.ps1 に UTF-8 の BOM がありません (PowerShell 5.1 が Shift_JIS として読みます)"
  fi
fi

echo

if [ "$errors" -ne 0 ]; then
  echo "固定されていない参照があります ($errors 件)。" >&2
  echo "README の「再現性」を参照し、ダイジェストまたはコミット SHA で固定してください。" >&2
  exit 1
fi

echo "外部の成果物はすべて固定されています。"
