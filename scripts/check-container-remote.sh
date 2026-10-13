#!/usr/bin/env bash
# Dev Containers の追加プロセスが ENTRYPOINT を経由せず起動する条件を検査する。
set -euo pipefail

if [[ $(command -v git) != /opt/dotfiles/bin/git ]]; then
  echo "ENTRYPOINT の外から toolchain の git を解決できません。" >&2
  exit 1
fi

case "$(uname -m)" in
  x86_64) loader=/lib64/ld-linux-x86-64.so.2 ;;
  aarch64) loader=/lib/ld-linux-aarch64.so.1 ;;
  *)
    echo "未対応の architecture です。" >&2
    exit 1
    ;;
esac

# shim から固定済み glibc の loader を起動できることを確認する。
"$loader" --version
test -r /usr/lib/libc.so.6
test -r /usr/lib/libstdc++.so.6
test -r "$NIX_LD_LIBRARY_PATH/libz.so.1"
"$loader" --list /usr/lib/libstdc++.so.6

# Server の環境取得に使われる login shell でも profile が維持されることを確認する。
/bin/bash -lc 'test "$(command -v git)" = /opt/dotfiles/bin/git && test -r "$DOTFILES_COMMAND_MANIFEST"'
scripts/check-env.sh
