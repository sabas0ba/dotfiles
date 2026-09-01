#!/usr/bin/env bash
#
# cloud-setup.sh が setup-script 経路で配布する toolchain の補助関数。
# 副作用の対象を引数で受け取ることで、一時ディレクトリ上で回帰検査できるようにする。
set -euo pipefail

dotfiles_update_toolchain_profile() {
  local flake_ref=$1
  local profile=$2

  mkdir -p "$(dirname "$profile")"
  nix build --profile "$profile" "$flake_ref" >/dev/null

  if [ ! -d "$profile/bin" ]; then
    echo "エラー: toolchain profile に bin ディレクトリがありません: $profile" >&2
    return 1
  fi
  if ! compgen -G "$profile/bin/*" >/dev/null; then
    echo "エラー: $profile/bin にコマンドがありません。" >&2
    return 1
  fi
}

dotfiles_install_toolchain_links() {
  local profile=$1
  local nix_bin=$2
  local extra_profile=$3
  local bin_dir=$4
  local manifest=$5
  local source target name existing old_name old_source
  local manifest_next=$manifest.new.$$
  declare -A managed=()
  declare -A shadowed=()

  mkdir -p "$bin_dir" "$(dirname "$manifest")"

  for source in "$profile"/bin/* "$nix_bin"/* "$extra_profile"/bin/*; do
    # 対象が無い場合、glob は展開されずそのまま残る。
    [ -e "$source" ] || continue

    name=$(basename "$source")
    target=$bin_dir/$name

    if [ -d "$target" ] && [ ! -L "$target" ]; then
      echo "エラー: toolchain の配置先がディレクトリです: $target" >&2
      return 1
    fi

    # 置き換える前に、system 側で同名が解決できていたかを見る。既に本処理が張った
    # symlink と Nix の実体は対象から除く。
    existing=$(command -v "$name" 2>/dev/null || true)
    case "$existing" in
      "" | "$bin_dir"/* | /nix/*) ;;
      *) shadowed["$name"]=1 ;;
    esac

    ln -sfn -- "$source" "$target"
    managed["$name"]=$source
  done

  if [ "${#managed[@]}" -eq 0 ]; then
    echo "エラー: $profile/bin にコマンドがありません。" >&2
    return 1
  fi

  # 前回は管理していたが現在の profile には無いリンクを取り除く。利用者がリンク先を
  # 変更していた場合は管理外とみなし、そのリンクを削除しない。
  if [ -f "$manifest" ]; then
    while IFS=$'\t' read -r old_name old_source; do
      [ -n "$old_name" ] || continue
      case "$old_name" in
        */* | .* | *$'\t'*)
          echo "エラー: toolchain manifest のコマンド名が不正です: $old_name" >&2
          return 1
          ;;
      esac

      if [ -z "${managed[$old_name]+present}" ]; then
        target=$bin_dir/$old_name
        if [ -L "$target" ] && [ "$(readlink "$target")" = "$old_source" ]; then
          rm -f -- "$target"
        fi
      fi
    done <"$manifest"
  fi

  : >"$manifest_next"
  while IFS= read -r name; do
    printf '%s\t%s\n' "$name" "${managed[$name]}" >>"$manifest_next"
  done < <(printf '%s\n' "${!managed[@]}" | LC_ALL=C sort)
  mv -f -- "$manifest_next" "$manifest"

  printf '%s\n' "${#managed[@]}"

  if [ "${#shadowed[@]}" -ne 0 ]; then
    printf 'shadowed:'
    while IFS= read -r name; do
      printf ' %s' "$name"
    done < <(printf '%s\n' "${!shadowed[@]}" | LC_ALL=C sort)
    printf '\n'
  fi
}

dotfiles_verify_toolchain_links() {
  local bin_dir=$1
  local manifest=$2
  local name source target

  if [ ! -s "$manifest" ]; then
    echo "エラー: toolchain manifest がありません: $manifest" >&2
    return 1
  fi

  while IFS=$'\t' read -r name source; do
    [ -n "$name" ] || continue
    target=$bin_dir/$name

    if [ ! -L "$target" ]; then
      echo "エラー: toolchain の管理リンクがありません: $target" >&2
      return 1
    fi
    if [ "$(readlink "$target")" != "$source" ] || [ ! -e "$target" ]; then
      echo "エラー: toolchain の管理リンクが壊れています: $target" >&2
      return 1
    fi
  done <"$manifest"
}
