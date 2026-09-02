#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
repository_script="$script_dir/wsl-repository.sh"
work_base=${WSL_REPOSITORY_TEST_TMPDIR:-"$repo_root/.work"}

mkdir -p "$work_base"
work=$(mktemp -d "$work_base/test-wsl-repository.XXXXXX")
trap 'rm -rf -- "$work"' EXIT

export GIT_AUTHOR_NAME='WSL repository test'
export GIT_AUTHOR_EMAIL='wsl-repository@example.invalid'
export GIT_COMMITTER_NAME=$GIT_AUTHOR_NAME
export GIT_COMMITTER_EMAIL=$GIT_AUTHOR_EMAIL

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_equal() {
  local expected=$1
  local actual=$2
  local description=$3

  if [[ $actual != "$expected" ]]; then
    printf 'FAIL: %s\nexpected: %s\nactual:   %s\n' \
      "$description" "$expected" "$actual" >&2
    exit 1
  fi
}

expect_failure() {
  local expected_message=$1
  local output
  shift

  if output=$("$@" 2>&1); then
    fail "失敗すべきコマンドが成功しました: $*"
  fi
  if [[ $output != *"$expected_message"* ]]; then
    printf 'FAIL: エラーに期待した文言がありません: %s\n%s\n' \
      "$expected_message" "$output" >&2
    exit 1
  fi
}

remote="$work/remote.git"
seed="$work/seed"
target="$work/target"
ref=refs/heads/main

git init --quiet --bare "$remote"
git init --quiet --initial-branch=main "$seed"
git -C "$seed" remote add origin "$remote"
printf 'first\n' >"$seed/value.txt"
git -C "$seed" add value.txt
git -C "$seed" commit --quiet -m first
first_commit=$(git -C "$seed" rev-parse HEAD)
git -C "$seed" push --quiet -u origin main

"$repository_script" "$target" "$work" "$remote" "$ref" 0

assert_equal "$first_commit" "$(git -C "$target" rev-parse HEAD)" \
  '初回実行は指定 ref の commit を checkout する'
assert_equal "$first_commit" \
  "$(git -C "$target" config --local --get dotfiles.bootstrapCommit)" \
  '初回実行は解決した commit を記録する'
if git -C "$target" symbolic-ref --quiet HEAD >/dev/null 2>&1; then
  fail '初回実行後の HEAD が detached ではありません'
fi

# 同じ ref への再実行は安全であること。
"$repository_script" "$target" "$work" "$remote" "$ref" 0

printf 'second\n' >>"$seed/value.txt"
git -C "$seed" commit --quiet -am second
second_commit=$(git -C "$seed" rev-parse HEAD)
git -C "$seed" push --quiet origin main

# 管理済み checkout は、外部で変更されていなければ新しい commit へ進められること。
"$repository_script" "$target" "$work" "$remote" "$ref" 0
assert_equal "$second_commit" "$(git -C "$target" rev-parse HEAD)" \
  '再実行は更新された ref の commit を checkout する'

printf 'dirty\n' >"$target/untracked.txt"
expect_failure '未コミットまたは未追跡の変更があります' \
  "$repository_script" "$target" "$work" "$remote" "$ref" 0
rm "$target/untracked.txt"

# 管理記録と異なる HEAD へ外部から変更された場合は、自動で上書きしないこと。
git -C "$target" checkout --quiet --detach "$first_commit"
expect_failure 'HEAD が前回解決した commit' \
  "$repository_script" "$target" "$work" "$remote" "$ref" 0
git -C "$target" checkout --quiet --detach "$second_commit"

# 既存の管理外 checkout は明示的な adoption が必要であること。
adopt_target="$work/adopt-target"
git init --quiet "$adopt_target"
git -C "$adopt_target" remote add origin "$remote"
git -C "$adopt_target" fetch --quiet origin "$first_commit"
git -C "$adopt_target" checkout --quiet --detach FETCH_HEAD
expect_failure '引き継ぐ場合は -AdoptExisting' \
  "$repository_script" "$adopt_target" "$work" "$remote" "$ref" 0
"$repository_script" "$adopt_target" "$work" "$remote" "$ref" 1
assert_equal "$second_commit" "$(git -C "$adopt_target" rev-parse HEAD)" \
  'adoption を明示した場合は既存 checkout を引き継ぐ'

wrong_origin="$work/wrong-origin"
git init --quiet "$wrong_origin"
git -C "$wrong_origin" remote add origin "$work/other.git"
expect_failure 'origin が指定値と一致しません' \
  "$repository_script" "$wrong_origin" "$work" "$remote" "$ref" 0

printf 'ok: WSL repository bootstrap tests passed\n'
