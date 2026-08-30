#!/usr/bin/env bash
#
# Nix release の固定が一括で更新され、失敗時に一部だけ変更されないことを検査する。
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fixture="$root/tests/fixtures/update-pins/nix-release"
work_base=${UPDATE_PINS_TEST_TMPDIR:-"$root/.work"}
test_dir=""
tests=0

cleanup() {
  if [ -z "$test_dir" ] || [ ! -d "$test_dir" ]; then
    return
  fi

  case $(basename -- "$test_dir") in
    test-nix-release-update.*) rm -rf -- "$test_dir" ;;
  esac
}

trap cleanup EXIT

fail() {
  echo "エラー: $1" >&2
  exit 1
}

new_fixture() {
  local name=$1 destination
  destination="$test_dir/$name"
  mkdir -p "$destination"
  # Nix store 内の fixture は読み取り専用であるため、mode は引き継がない。
  cp -R --no-preserve=mode -- "$fixture/." "$destination"
  mkdir -p "$destination/.work"
  printf '%s\n' "$destination"
}

run_update() {
  local destination=$1
  shift
  (
    cd "$destination"
    # Nix sandbox には /usr/bin/env が無いため、store 内の shebang へ直接依存しない。
    bash "$root/scripts/update-pins.sh" "$@"
  )
}

assert_line() {
  local path=$1 expected=$2
  if ! grep -qFx -- "$expected" "$path"; then
    fail "$path に次の行がありません: $expected"
  fi
}

assert_unchanged() {
  local before=$1 after=$2
  if ! diff -ru -- "$before" "$after" >/dev/null; then
    diff -ru -- "$before" "$after" >&2 || true
    fail "失敗した更新が fixture を変更しました: $after"
  fi
}

mkdir -p "$work_base"
test_dir=$(mktemp -d "$work_base/test-nix-release-update.XXXXXX")

same_version=$(new_fixture same-version)
same_digest=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
same_sha=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
run_update "$same_version" nix-release 1.2.3 "$same_digest" "$same_sha" >/dev/null
assert_line "$same_version/Dockerfile" 'ARG NIX_VERSION=1.2.3'
assert_line "$same_version/Dockerfile" "ARG NIX_IMAGE_DIGEST=$same_digest"
assert_line "$same_version/docs/setup.md" "NIX_SHA256=$same_sha"
assert_line "$same_version/scripts/nix-pin.sh" "NIX_SHA256=$same_sha"
tests=$((tests + 1))

new_version=$(new_fixture new-version)
new_digest=sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
new_sha=dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
run_update "$new_version" nix-release 2.0.0 "$new_digest" "$new_sha" >/dev/null
assert_line "$new_version/Dockerfile" 'ARG NIX_VERSION=2.0.0'
assert_line "$new_version/docs/setup.md" 'NIX_VERSION=2.0.0'
assert_line "$new_version/scripts/nix-pin.sh" 'NIX_VERSION=2.0.0'
assert_line "$new_version/Dockerfile" "ARG NIX_IMAGE_DIGEST=$new_digest"
assert_line "$new_version/docs/setup.md" "NIX_SHA256=$new_sha"
assert_line "$new_version/scripts/nix-pin.sh" "NIX_SHA256=$new_sha"
tests=$((tests + 1))

missing_target=$(new_fixture missing-target)
sed -i '/^NIX_SHA256=/d' "$missing_target/scripts/nix-pin.sh"
missing_before="$test_dir/missing-target-before"
cp -R -- "$missing_target" "$missing_before"
if run_update "$missing_target" nix-release 2.0.0 "$new_digest" "$new_sha" \
  >"$test_dir/missing-target.log" 2>&1; then
  fail "置換対象が不足している更新が成功しました"
fi
assert_unchanged "$missing_before" "$missing_target"
if ! grep -qF '一意に見つかりません' "$test_dir/missing-target.log"; then
  fail "置換対象不足のエラー理由が表示されませんでした"
fi
tests=$((tests + 1))

no_change=$(new_fixture no-change)
no_change_before="$test_dir/no-change-before"
cp -R -- "$no_change" "$no_change_before"
if run_update "$no_change" nix-release 1.2.3 \
  sha256:1111111111111111111111111111111111111111111111111111111111111111 \
  2222222222222222222222222222222222222222222222222222222222222222 \
  >"$test_dir/no-change.log" 2>&1; then
  fail "差分のない更新が成功しました"
fi
assert_unchanged "$no_change_before" "$no_change"
if ! grep -qF '変更はありません' "$test_dir/no-change.log"; then
  fail "差分なしのエラー理由が表示されませんでした"
fi
tests=$((tests + 1))

crlf_no_change=$(new_fixture crlf-no-change)
for path in Dockerfile docs/setup.md scripts/nix-pin.sh; do
  sed 's/$/\r/' "$crlf_no_change/$path" >"$crlf_no_change/$path.crlf"
  mv -- "$crlf_no_change/$path.crlf" "$crlf_no_change/$path"
done
crlf_before="$test_dir/crlf-no-change-before"
cp -R -- "$crlf_no_change" "$crlf_before"
if run_update "$crlf_no_change" nix-release 1.2.3 \
  sha256:1111111111111111111111111111111111111111111111111111111111111111 \
  2222222222222222222222222222222222222222222222222222222222222222 \
  >"$test_dir/crlf-no-change.log" 2>&1; then
  fail "CRLF fixture の差分がない更新が成功しました"
fi
assert_unchanged "$crlf_before" "$crlf_no_change"
if ! grep -qF '変更はありません' "$test_dir/crlf-no-change.log"; then
  fail "CRLF fixture で差分なしのエラー理由が表示されませんでした"
fi
tests=$((tests + 1))

legacy_target=$(new_fixture legacy-target)
legacy_before="$test_dir/legacy-target-before"
cp -R -- "$legacy_target" "$legacy_before"
if run_update "$legacy_target" image 1.2.3 "$same_digest" \
  >"$test_dir/legacy-target.log" 2>&1; then
  fail "廃止した個別更新が成功しました"
fi
assert_unchanged "$legacy_before" "$legacy_target"
if ! grep -qF 'nix-release' "$test_dir/legacy-target.log"; then
  fail "個別更新から nix-release への移行方法が表示されませんでした"
fi
tests=$((tests + 1))

echo "update-pins の回帰テストが成功しました ($tests 件)。"
