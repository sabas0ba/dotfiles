#!/usr/bin/env bash
#
# 固定した配布物の cache が、中断や破損から安全に自己復旧することを検査する。
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
payload="$root/tests/fixtures/pinned-download/payload.txt"
work_base=${PINNED_DOWNLOAD_TEST_TMPDIR:-"$root/.work"}
test_dir=""
tests=0
curl_calls=0
curl_mode=success
curl_url=""

# shellcheck source=scripts/pinned-download.sh
. "$root/scripts/pinned-download.sh"

cleanup() {
  if [ -z "$test_dir" ] || [ ! -d "$test_dir" ]; then
    return
  fi

  case $(basename -- "$test_dir") in
    test-pinned-download.*) rm -rf -- "$test_dir" ;;
  esac
}

trap cleanup EXIT

fail() {
  echo "エラー: $1" >&2
  exit 1
}

# helper が呼ぶ curl を置き換える。取得失敗時は実際の curl と同様に途中ファイルを
# 残して非零を返し、helper 側が除去することを確認できるようにする。
curl() {
  local output=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      -o)
        output=$2
        shift 2
        ;;
      -*) shift ;;
      *)
        curl_url=$1
        shift
        ;;
    esac
  done

  if [ -z "$output" ]; then
    fail "curl mock に出力先が渡されませんでした"
  fi

  curl_calls=$((curl_calls + 1))
  case "$curl_mode" in
    failure)
      printf 'partial response\n' >"$output"
      return 22
      ;;
    mismatch) printf 'unexpected response\n' >"$output" ;;
    success) cp -- "$payload" "$output" ;;
    *) fail "curl mock の mode が不明です: $curl_mode" ;;
  esac
}

assert_payload() {
  local path=$1
  if ! cmp -s -- "$payload" "$path"; then
    fail "$path が検証済みの payload と一致しません"
  fi
}

assert_no_part() {
  local path=$1
  if [ -e "${path}.part" ]; then
    fail "途中ファイルが残っています: ${path}.part"
  fi
}

mkdir -p "$work_base"
test_dir=$(mktemp -d "$work_base/test-pinned-download.XXXXXX")
expected_sha256=$(sha256sum "$payload" | cut -d ' ' -f1)
url=https://example.invalid/nix.tar.xz

# 破損 cache は、取得と検証が成功した後だけ置き換える。
corrupt_cache="$test_dir/corrupt-cache.tar.xz"
printf 'corrupt cache\n' >"$corrupt_cache"
curl_calls=0
pinned_download "$url" "$expected_sha256" "$corrupt_cache" 2>"$test_dir/corrupt.log"
assert_payload "$corrupt_cache"
assert_no_part "$corrupt_cache"
[ "$curl_calls" -eq 1 ] || fail "破損 cache の再取得回数が異なります: $curl_calls"
[ "$curl_url" = "$url" ] || fail "取得 URL が異なります: $curl_url"
tests=$((tests + 1))

# 前回中断した .part は破棄し、先頭から取得する。
interrupted="$test_dir/interrupted.tar.xz"
printf 'interrupted download\n' >"${interrupted}.part"
curl_calls=0
pinned_download "$url" "$expected_sha256" "$interrupted"
assert_payload "$interrupted"
assert_no_part "$interrupted"
[ "$curl_calls" -eq 1 ] || fail "中断後の再取得回数が異なります: $curl_calls"
tests=$((tests + 1))

# 正常 cache はネットワークを使わず、残っている .part だけを除く。
normal_cache="$test_dir/normal-cache.tar.xz"
cp -- "$payload" "$normal_cache"
printf 'stale part\n' >"${normal_cache}.part"
curl_calls=0
curl_mode=failure
pinned_download "$url" "$expected_sha256" "$normal_cache"
assert_payload "$normal_cache"
assert_no_part "$normal_cache"
[ "$curl_calls" -eq 0 ] || fail "正常 cache に対して download が実行されました"
tests=$((tests + 1))

# download が成功しても checksum が異なる内容は最終 cache にしない。
checksum_cache="$test_dir/checksum-failure.tar.xz"
checksum_before="$test_dir/checksum-failure.before"
printf 'existing corrupt cache\n' >"$checksum_cache"
cp -- "$checksum_cache" "$checksum_before"
curl_calls=0
curl_mode=mismatch
if pinned_download "$url" "$expected_sha256" "$checksum_cache" \
  >"$test_dir/checksum-failure.log" 2>&1; then
  fail "checksum 不一致の download が成功として扱われました"
fi
if ! cmp -s -- "$checksum_before" "$checksum_cache"; then
  fail "checksum 不一致時に既存 cache が変更されました"
fi
assert_no_part "$checksum_cache"
[ "$curl_calls" -eq 1 ] || fail "checksum 不一致の download 回数が異なります: $curl_calls"
tests=$((tests + 1))

# download が失敗しても破損 cache を途中ファイルで上書きしない。
failed_cache="$test_dir/download-failure.tar.xz"
failed_before="$test_dir/download-failure.before"
printf 'existing corrupt cache\n' >"$failed_cache"
cp -- "$failed_cache" "$failed_before"
curl_calls=0
curl_mode=failure
if pinned_download "$url" "$expected_sha256" "$failed_cache" \
  >"$test_dir/failure.log" 2>&1; then
  fail "download 失敗が成功として扱われました"
fi
if ! cmp -s -- "$failed_before" "$failed_cache"; then
  fail "download 失敗時に既存 cache が変更されました"
fi
assert_no_part "$failed_cache"
[ "$curl_calls" -eq 1 ] || fail "失敗する download の実行回数が異なります: $curl_calls"
tests=$((tests + 1))

echo "pinned download の回帰テストが成功しました ($tests 件)。"
