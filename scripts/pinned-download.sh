# shellcheck shell=bash
#
# 固定した sha256 を持つ配布物を、安全にキャッシュへ取得する sourceable helper。
# 呼び出し元が set -euo pipefail を設定するため、本ファイルでは shell option を変更しない。

pinned_download_verify() {
  local expected_sha256=$1 path=$2

  printf '%s  %s\n' "$expected_sha256" "$path" | sha256sum -c - >/dev/null 2>&1
}

pinned_download() {
  local url=$1 expected_sha256=$2 destination=$3
  local partial=${destination}.part

  if [[ ! $expected_sha256 =~ ^[0-9a-f]{64}$ ]]; then
    echo "エラー: 固定した sha256 が 64 桁の小文字16進数ではありません。" >&2
    return 1
  fi

  if [ -f "$destination" ] && pinned_download_verify "$expected_sha256" "$destination"; then
    # 正常な cache があればネットワークを使わない。前回の中断物だけが残っている場合は
    # 以降に誤って使われないよう除く。
    rm -f -- "$partial"
    return
  fi

  if [ -e "$destination" ]; then
    echo "警告: checksum が一致しない cache を再取得します: $destination" >&2
  fi

  # curl は失敗時にも途中までの内容を残す。前回分を再利用せず、毎回空の .part から
  # 始める。最終 cache は検証済みの .part ができるまで変更しない。
  rm -f -- "$partial"
  if ! curl -fsSL -o "$partial" "$url"; then
    rm -f -- "$partial"
    echo "エラー: 配布物を取得できませんでした: $url" >&2
    return 1
  fi

  if ! pinned_download_verify "$expected_sha256" "$partial"; then
    rm -f -- "$partial"
    echo "エラー: 取得した配布物の checksum が一致しません: $url" >&2
    return 1
  fi

  # .part は destination と同じディレクトリにあり、rename は同一 filesystem 内で
  # 完結する。検証済みの内容だけが最終 cache として見える。
  mv -f -- "$partial" "$destination"
}
