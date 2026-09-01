#!/bin/sh

# WSL bootstrap で使用する checkout を検証し、指定 ref の commit に固定する。
# PowerShell 側はこのファイルを読み込み、対象 distro の sh に渡す。
set -eu

if [ "$#" -ne 5 ]; then
  printf '使用方法: %s REPO_PATH REPO_PARENT REPO_URL REF ALLOW_ADOPTION\n' "$0" >&2
  exit 2
fi

repo_path=$1
repo_parent=$2
repo_url=$3
requested_ref=$4
allow_adoption=$5

die() {
  printf 'エラー: %s\n' "$1" >&2
  exit 1
}

if [ -e "$repo_path" ] && [ ! -d "$repo_path/.git" ]; then
  die "$repo_path は Git リポジトリではありません。退避するか別の -RepoUrl を指定してください。"
fi

mkdir -p "$repo_parent"

if [ ! -d "$repo_path/.git" ]; then
  git init --quiet "$repo_path"
  git -C "$repo_path" remote add origin "$repo_url"
  git -C "$repo_path" config --local dotfiles.bootstrapSchema 1
  git -C "$repo_path" config --local dotfiles.bootstrapRef "$requested_ref"
fi

inside=$(git -C "$repo_path" rev-parse --is-inside-work-tree 2>/dev/null || :)
[ "$inside" = true ] || die "$repo_path は利用可能な Git worktree ではありません。"

actual_origin=$(git -C "$repo_path" remote get-url --all origin 2>/dev/null || :)
[ "$actual_origin" = "$repo_url" ] ||
  die "$repo_path の origin が指定値と一致しません (実際: ${actual_origin:-なし})。"

dirty=$(git -C "$repo_path" status --porcelain --untracked-files=all)
[ -z "$dirty" ] || die "$repo_path に未コミットまたは未追跡の変更があります。"

schema=$(git -C "$repo_path" config --local --get dotfiles.bootstrapSchema || :)
stored_ref=$(git -C "$repo_path" config --local --get dotfiles.bootstrapRef || :)
stored_commit=$(git -C "$repo_path" config --local --get dotfiles.bootstrapCommit || :)

if [ -n "$schema" ]; then
  [ "$schema" = 1 ] || die "$repo_path の bootstrap schema は未対応です ($schema)。"
  [ -n "$stored_ref" ] || die "$repo_path に前回解決した ref の記録がありません。"
  if [ -n "$stored_commit" ]; then
    current_commit=$(git -C "$repo_path" rev-parse --verify 'HEAD^{commit}' 2>/dev/null || :)
    [ "$current_commit" = "$stored_commit" ] ||
      die "$repo_path の HEAD が前回解決した commit ($stored_commit) と一致しません。"
  fi
fi

git -C "$repo_path" fetch --force --no-tags origin "$requested_ref"
resolved_commit=$(git -C "$repo_path" rev-parse --verify 'FETCH_HEAD^{commit}')

case "$resolved_commit" in
  *[!0-9a-f]* | '') die "$requested_ref を完全な commit SHA に解決できませんでした。" ;;
esac
[ "${#resolved_commit}" -eq 40 ] ||
  die "$requested_ref を 40 桁の commit SHA に解決できませんでした ($resolved_commit)。"

if [ -z "$schema" ]; then
  current_commit=$(git -C "$repo_path" rev-parse --verify 'HEAD^{commit}' 2>/dev/null || :)
  if [ -n "$current_commit" ] && [ "$current_commit" != "$resolved_commit" ] &&
    [ "$allow_adoption" != 1 ]; then
    die "$repo_path の HEAD ($current_commit) は $requested_ref ($resolved_commit) と異なります。引き継ぐ場合は -AdoptExisting を指定してください。"
  fi
  git -C "$repo_path" config --local dotfiles.bootstrapSchema 1
fi

git -C "$repo_path" config --local dotfiles.bootstrapRef "$requested_ref"
git -C "$repo_path" checkout --quiet --detach "$resolved_commit"
git -C "$repo_path" config --local dotfiles.bootstrapCommit "$resolved_commit"

head_commit=$(git -C "$repo_path" rev-parse --verify HEAD)
[ "$head_commit" = "$resolved_commit" ] || die "$repo_path の checkout 後の HEAD が一致しません。"
if git -C "$repo_path" symbolic-ref --quiet HEAD >/dev/null 2>&1; then
  die "$repo_path の HEAD が detached 状態ではありません。"
fi

dirty=$(git -C "$repo_path" status --porcelain --untracked-files=all)
[ -z "$dirty" ] || die "$repo_path の checkout 後に変更が残っています。"

printf '  ok      ref %s を commit %s に解決した (detached HEAD)\n' \
  "$requested_ref" "$resolved_commit"
