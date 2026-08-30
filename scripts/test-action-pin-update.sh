#!/usr/bin/env bash
#
# action 名の正規表現メタ文字が literal として扱われることを検査する。
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
updater="$script_dir/update-pins.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/.github/workflows"

cat >"$work/.github/workflows/near-match.yml" <<'YAML'
jobs:
  test:
    steps:
      - uses: acme/exampleXaction@1111111111111111111111111111111111111111
YAML

cat >"$work/.github/workflows/exact-match.yml" <<'YAML'
jobs:
  test:
    steps:
      - uses: acme/example.action@2222222222222222222222222222222222222222
YAML

(
  cd "$work"
  bash "$updater" action acme/example.action 3333333333333333333333333333333333333333
)

grep -qF 'acme/exampleXaction@1111111111111111111111111111111111111111' \
  "$work/.github/workflows/near-match.yml"
grep -qF 'acme/example.action@3333333333333333333333333333333333333333' \
  "$work/.github/workflows/exact-match.yml"

echo 'action 固定更新の検査に成功しました。'
