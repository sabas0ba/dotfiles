#!/usr/bin/env bash
#
# flake.nix の入力と flake.lock の整合を検査する。
#
# 本リポジトリは入力を 40 桁のリビジョンで固定する方針を採るが、flake.nix の記述と
# flake.lock の内容が一致していることは、これまでどの検査でも確認していなかった。
#
# nix 自身が検出するのは lock の再生成が必要になる乖離に限られ、その場合も失敗は入力の
# 再取得の失敗として現れるため、原因が lock の古さであることが分からない。加えて、入力が
# ブランチ名で参照されている場合、nix はこれを正常として扱う。lock には rev が記録される
# ため評価は再現するが、flake.nix の記述は固定になっていない。本スクリプトはこの双方を、
# オフラインかつ原因の分かる形で検出する。
#
# ネットワークを使用しない。flake.nix と flake.lock の内容のみを照合する。
#
#   使用方法: scripts/check-lock.sh [flake.nix のパス] [flake.lock のパス]
set -euo pipefail

flake_nix=${1:-flake.nix}
flake_lock=${2:-flake.lock}

for path in "$flake_nix" "$flake_lock"; do
  if [ ! -f "$path" ]; then
    echo "エラー: $path が存在しません。" >&2
    exit 1
  fi
done

# flake.lock が JSON として解釈でき、ノードの一覧を持つことを先に確認する。
# 以降の jq がエラーを出す前に、原因の分かる形で止めるため。
if ! jq -e 'has("nodes") and (.nodes | type == "object")' "$flake_lock" >/dev/null 2>&1; then
  echo "エラー: $flake_lock を flake.lock として解釈できません。" >&2
  echo "'make lock' で再生成してください。" >&2
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

# --- flake.lock 単体の妥当性 ------------------------------------------------
#
# 各ノードが narHash を持つこと。リビジョンを持つ形式 (github / git / gitlab /
# sourcehut) については、40 桁のリビジョンで固定されており、かつ flake.nix 側の指定
# (original.rev) が実際の解決結果 (locked.rev) と一致すること。
#
# tarball や path のようにリビジョンを持たない形式は narHash のみで一意に定まるため、
# リビジョンの検査対象から除く。

lock_problems=$(
  jq -r '
    .nodes
    | to_entries[]
    | select(.key != "root")
    | .key as $name
    | (.value.locked // {}) as $locked
    | (.value.original // {}) as $original
    | (
        (if ($locked.narHash // "") == "" then
           "\($name): locked.narHash が記録されていません"
         else empty end),
        (if (["github", "git", "gitlab", "sourcehut"] | index($locked.type // "")) then
           (
             (if (($locked.rev // "") | test("^[0-9a-f]{40}$")) then empty else
                "\($name): locked.rev が 40 桁のリビジョンではありません"
              end),
             (if ($original.rev // "") == ($locked.rev // "") then empty else
                "\($name): original.rev と locked.rev が一致しません"
              end)
           )
         else empty end)
      )
  ' "$flake_lock"
)

if [ -n "$lock_problems" ]; then
  while IFS= read -r problem; do
    fail "flake.lock: $problem"
  done <<<"$lock_problems"
else
  ok "flake.lock の全ノードが一意に固定されている"
fi

# --- flake.nix の入力がすべて固定されていること -----------------------------
#
# 行末コメントを除去してから URL を列挙する。本リポジトリの flake.nix は文字列中に
# '#' を含まないため、この除去で URL が壊れることはない。

mapfile -t urls < <(
  sed -e 's/#.*$//' "$flake_nix" |
    grep -oE 'github:[A-Za-z0-9._-]+/[A-Za-z0-9._-]+(/[A-Za-z0-9._/-]+)?' |
    sort -u
)

if [ "${#urls[@]}" -eq 0 ]; then
  fail "flake.nix に github: 形式の入力が見つかりません"
fi

# --- flake.nix の各入力が flake.lock に同一のリビジョンで記録されていること ---

for url in "${urls[@]}"; do
  if [[ ! $url =~ ^github:([A-Za-z0-9._-]+)/([A-Za-z0-9._-]+)/([0-9a-f]{40})$ ]]; then
    fail "flake.nix の入力がリビジョンで固定されていません: $url"
    continue
  fi

  owner=${BASH_REMATCH[1]}
  repo=${BASH_REMATCH[2]}
  rev=${BASH_REMATCH[3]}

  locked_rev=$(
    jq -r --arg owner "$owner" --arg repo "$repo" '
      [ .nodes[]
        | select((.locked.owner // "") == $owner and (.locked.repo // "") == $repo)
        | .locked.rev // ""
      ]
      | first // ""
    ' "$flake_lock"
  )

  if [ -z "$locked_rev" ]; then
    fail "flake.lock に $owner/$repo の記録がありません (flake.nix は ${rev:0:8} を指定)"
  elif [ "$locked_rev" != "$rev" ]; then
    fail "$owner/$repo のリビジョンが不一致: flake.nix=${rev:0:8} flake.lock=${locked_rev:0:8}"
  else
    ok "$owner/$repo は ${rev:0:8} で一致している"
  fi
done

# --- flake.lock に取り残された入力が無いこと ---------------------------------
#
# flake.nix から入力を削除したまま flake.lock を再生成しなかった場合を検出する。
# 照合対象は github 形式のノードに限る。他の形式の入力を追加した際に、本検査が
# 誤って失敗しないようにするため。

mapfile -t locked_repos < <(
  jq -r '
    (.nodes.root.inputs // {})
    | to_entries[]
    | select(.value | type == "string")
    | .value
  ' "$flake_lock" |
    while IFS= read -r node; do
      jq -r --arg node "$node" '
        .nodes[$node].locked
        | select((.type // "") == "github")
        | "\(.owner)/\(.repo)"
      ' "$flake_lock"
    done
)

stale_errors=$errors

for repo_path in "${locked_repos[@]}"; do
  matched=0
  for url in "${urls[@]}"; do
    if [[ $url == "github:$repo_path/"* ]]; then
      matched=1
      break
    fi
  done

  if [ "$matched" -eq 0 ]; then
    fail "flake.lock の入力 $repo_path が flake.nix に存在しません"
  fi
done

if [ "$errors" -eq "$stale_errors" ] && [ "${#locked_repos[@]}" -ne 0 ]; then
  ok "flake.lock に取り残された入力は無い (${#locked_repos[@]} 件を照合)"
fi

echo

if [ "$errors" -ne 0 ]; then
  echo "flake.nix と flake.lock が整合していません ($errors 件)。" >&2
  echo "'make update' を実行し、生成された flake.lock を同一のコミットに含めてください。" >&2
  exit 1
fi

echo "flake.nix と flake.lock は整合しています。"
