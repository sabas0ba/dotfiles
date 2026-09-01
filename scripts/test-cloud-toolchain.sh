#!/usr/bin/env bash
# cloud toolchain profile の更新と管理リンクの収束性を検査する。
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/cloud-toolchain.sh
. "$script_dir/cloud-toolchain.sh"

work=${TMPDIR:-$script_dir/../.work}/dotfiles-cloud-toolchain-test
profile=$work/profiles/dotfiles-toolchain
bin_dir=$work/usr-local-bin
manifest=$work/state/links
nix_bin=$work/nix-bin
extra_profile=$work/profiles/dotfiles-extra
fake_bin=$work/fake-bin
output_one=$work/output-one
output_two=$work/output-two
extra_output=$work/extra-output
user_bin=$work/user-bin

rm -rf "$work"
mkdir -p "$fake_bin" "$nix_bin" "$output_one/bin" "$output_two/bin" "$extra_output/bin" "$user_bin"

make_command() {
  local path=$1
  printf '#!/bin/sh\nexit 0\n' >"$path"
  chmod +x "$path"
}

make_command "$output_one/bin/alpha"
make_command "$output_one/bin/shared"
make_command "$output_two/bin/beta"
make_command "$output_two/bin/shared"
make_command "$extra_output/bin/gamma"
make_command "$extra_output/bin/shared"
make_command "$nix_bin/nix"
make_command "$user_bin/alpha"

{
  printf '#!%s\n' "$(command -v bash)"
  cat <<'EOF'
set -euo pipefail

profile=
while [ "$#" -gt 0 ]; do
  if [ "$1" = --profile ]; then
    profile=$2
    shift 2
    continue
  fi
  shift
done

[ -n "$profile" ]
mkdir -p "$(dirname "$profile")"
ln -sfn "$FAKE_TOOLCHAIN_OUTPUT" "$profile"
EOF
} >"$fake_bin/nix"
chmod +x "$fake_bin/nix"

export PATH=$fake_bin:$PATH
export FAKE_TOOLCHAIN_OUTPUT=$output_one
mkdir -p "$(dirname "$extra_profile")"
ln -s "$extra_output" "$extra_profile"

# manifest 導入前の版が張った link の移行。profile の更新で指す先を失ったものは
# 初回の manifest 実行で取り除き、管理外の壊れた link には触れない。
mkdir -p "$bin_dir"
ln -s "$profile/bin/removed-by-upgrade" "$bin_dir/removed-by-upgrade"
ln -s "$work/unmanaged-missing" "$bin_dir/unmanaged"

dotfiles_update_toolchain_profile repo#default "$profile"
dotfiles_install_toolchain_links "$profile" "$nix_bin" "$extra_profile" "$bin_dir" "$manifest" >/dev/null
dotfiles_verify_toolchain_links "$bin_dir" "$manifest"

[ "$(readlink "$bin_dir/alpha")" = "$profile/bin/alpha" ]
[ "$(readlink "$bin_dir/gamma")" = "$extra_profile/bin/gamma" ]
[ "$(readlink "$bin_dir/shared")" = "$extra_profile/bin/shared" ]
[ "$(readlink "$bin_dir/nix")" = "$nix_bin/nix" ]
if [ -L "$bin_dir/removed-by-upgrade" ]; then
  echo "manifest 導入前の壊れた管理 link が残っています。" >&2
  exit 1
fi
[ "$(readlink "$bin_dir/unmanaged")" = "$work/unmanaged-missing" ]

# 利用者が差し替えたリンクは、profile からコマンドが消えても削除しない。
ln -sfn "$user_bin/alpha" "$bin_dir/alpha"
export FAKE_TOOLCHAIN_OUTPUT=$output_two
rm "$extra_profile"

dotfiles_update_toolchain_profile repo#default "$profile"
dotfiles_install_toolchain_links "$profile" "$nix_bin" "$extra_profile" "$bin_dir" "$manifest" >/dev/null
dotfiles_verify_toolchain_links "$bin_dir" "$manifest"

[ "$(readlink "$bin_dir/alpha")" = "$user_bin/alpha" ]
[ "$(readlink "$bin_dir/beta")" = "$profile/bin/beta" ]
[ "$(readlink "$bin_dir/shared")" = "$profile/bin/shared" ]
[ ! -e "$bin_dir/gamma" ]
if grep -q '^alpha' "$manifest"; then
  echo "削除したコマンドが manifest に残っています。" >&2
  exit 1
fi

# 同じ出力へ再度収束させても、管理対象とリンクは変わらない。
before=$(sha256sum "$manifest")
dotfiles_update_toolchain_profile repo#default "$profile"
dotfiles_install_toolchain_links "$profile" "$nix_bin" "$extra_profile" "$bin_dir" "$manifest" >/dev/null
after=$(sha256sum "$manifest")
[ "$before" = "$after" ]

echo "cloud toolchain の検査に成功しました。"
