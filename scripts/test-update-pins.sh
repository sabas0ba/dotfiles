#!/usr/bin/env bash
#
# scripts/update-pins.sh の複数値を伴う更新を fixture で検査する。
#
# NixOS-WSL の revision とタグコメントは対応する 1 組であり、成功時は両方を更新し、
# 入力または既存行が不完全な場合はどちらも変更しないことを確認する。
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
updater="$script_dir/update-pins.sh"

if [ ! -x "$updater" ]; then
  echo "エラー: $updater が実行できません。" >&2
  exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

old_rev=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
new_rev=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
old_tag=2605.7.2
new_tag=2605.8.0
fixture="$work/flake.nix"
log="$work/update.log"
failures=0

write_fixture() {
  local suffix=$1
  printf '%s\n' \
    '{' \
    '  inputs.nixos-wsl = {' \
    "    url = \"github:nix-community/NixOS-WSL/$old_rev\";$suffix" \
    '  };' \
    '}' >"$fixture"
}

fail() {
  printf '  NG      %s\n' "$1"
  failures=$((failures + 1))
}

write_fixture " # $old_tag"
if (cd "$work" && bash "$updater" nixos-wsl "$new_rev" "$new_tag") >"$log" 2>&1 &&
  grep -qxF "    url = \"github:nix-community/NixOS-WSL/$new_rev\"; # $new_tag" "$fixture"; then
  printf '  ok      revision とタグを同時に更新する\n'
else
  fail 'revision とタグを同時に更新する'
  cat "$log"
  cat "$fixture"
fi

write_fixture " # $old_tag"
before=$(cat "$fixture")
if (cd "$work" && bash "$updater" nixos-wsl "$new_rev" '2605.8.0;invalid') >"$log" 2>&1; then
  fail '不正なタグを拒否する'
elif [ "$(cat "$fixture")" != "$before" ]; then
  fail '不正なタグで fixture を変更しない'
else
  printf '  ok      不正なタグを拒否して変更を残さない\n'
fi

# タグコメントが無い fixture では、逐次置換なら revision だけが変わり得る。更新全体が
# 失敗し、元の内容が保たれることで 1 回の置換になっていることを確認する。
write_fixture ''
before=$(cat "$fixture")
if (cd "$work" && bash "$updater" nixos-wsl "$new_rev" "$new_tag") >"$log" 2>&1; then
  fail 'タグコメントの無い既存行を拒否する'
elif [ "$(cat "$fixture")" != "$before" ]; then
  fail '置換失敗時に revision だけを変更しない'
else
  printf '  ok      置換失敗時に半更新を残さない\n'
fi

echo

if [ "$failures" -ne 0 ]; then
  echo "固定値更新の fixture 検査に失敗しました ($failures 件)。" >&2
  exit 1
fi

echo '固定値更新の fixture 検査は期待どおりです (3 件)。'
