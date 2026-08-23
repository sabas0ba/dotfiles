#!/usr/bin/env bash
#
# Claude Code のリモート実行環境 (クラウド) を構成する。
#
# 当該環境はセッションごとに用意される Ubuntu のコンテナであり、初期状態では Nix が
# 無い。本スクリプトは docs/setup.md と同じ手順で Nix を導入し、開発シェルを profile
# として実体化したうえで、その環境変数をセッションに引き渡す。これにより、以降の
# コマンドは他の環境と同一のツールで動作する。
#
# .claude/settings.json の SessionStart フックから呼ばれる。セッションの開始ごとに
# 実行されるため、既に済んでいる処理は飛ばす。失敗した場合はそのまま再実行できる。
#
#   使用方法: scripts/cloud-setup.sh
set -euo pipefail

# リモート実行環境でのみ動作させる。手元の環境は direnv または nix develop で開発
# シェルに入る (docs/setup.md)。利用者のホストに Nix を導入する経路をここに作らない。
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  echo "リモート実行環境ではないため何もしない (CLAUDE_CODE_REMOTE が true でない)。"
  exit 0
fi

script_dir=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$script_dir/.." && pwd)

# shellcheck source=scripts/nix-pin.sh
. "$script_dir/nix-pin.sh"

# 実体化した開発シェルの配置先。Dockerfile が使う名前と揃える。
readonly DOTFILES_PROFILE=/nix/var/nix/profiles/dotfiles-dev

# 当該環境は USER を設定しない。Nix の profile スクリプトは HOME と USER の両方が
# ある場合にしか PATH を設定せず、home-manager の activation script も USER を参照する
# (Makefile の hm-switch が同じ理由で補っている)。ここで補い、セッションにも引き渡す。
export USER=${USER:-$(id -un)}

step() {
  printf '\n== %s\n' "$1"
}

note() {
  printf '   %s\n' "$1"
}

# --- Nix の導入 --------------------------------------------------------------

# Nix の設定を置く。導入より前に行う。インストーラ自身が nix-env を実行するため、
# 後から書いたのでは間に合わない。
configure_nix() {
  local path=/etc/nix/nix.conf

  if [ -f "$path" ] && grep -qF "$NIX_FLAKE_CONF" "$path"; then
    note "nix.conf は構成済みである"
    return
  fi

  mkdir -p "$(dirname "$path")"

  # build-users-group を空にする。root しか存在しないコンテナであり、ビルド用の
  # 利用者 (nixbld) を作れないため。空にしない場合、導入時の nix-env が失敗する。
  #
  # sandbox と filter-syscalls の無効化は Dockerfile と同じ理由による。コンテナの
  # seccomp プロファイルと Nix のサンドボックスが競合し、ビルドが失敗する。依存は
  # すべて cache.nixos.org のバイナリで取得する。
  printf '%s\n' \
    "$NIX_FLAKE_CONF" \
    'build-users-group =' \
    'sandbox = false' \
    'filter-syscalls = false' \
    'max-jobs = auto' \
    >>"$path"

  note "nix.conf を構成した ($path)"
}

install_nix() {
  if [ -e /nix/var/nix/profiles/default ] || [ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
    note "Nix は既に導入されている"
    return
  fi

  local arch
  arch=$(uname -m)
  if [ "$arch" != x86_64 ]; then
    echo "エラー: 固定した sha256 は x86_64-linux 向けである (実行環境: $arch)。" >&2
    echo "他のアーキテクチャで動かす場合は scripts/nix-pin.sh を対応する値にする。" >&2
    exit 1
  fi

  local work=$repo/.work/nix
  local tarball="nix-${NIX_VERSION}-x86_64-linux.tar.xz"
  local url="https://releases.nixos.org/nix/nix-${NIX_VERSION}/${tarball}"

  # 作業用のファイルはリポジトリ内の git ignore された場所に置く。
  mkdir -p "$work"

  if [ ! -f "$work/$tarball" ]; then
    note "取得する: $url"
    curl -fsSL -o "$work/$tarball" "$url"
  fi

  # 固定した値と照合する。配布元から取得した .sha256 との照合は、配布物と同時に
  # 差し替えられるため検証にならない。docs/setup.md と同じ方針である。
  printf '%s  %s\n' "$NIX_SHA256" "$work/$tarball" | sha256sum -c -

  tar -xf "$work/$tarball" -C "$work"

  # 当該環境には systemd が無いため daemon 方式は成立しない。単一の利用者しか
  # 存在しないコンテナであり、--no-daemon で足りる。
  # NIX_INSTALLER_YES で確認のプロンプトを省く。
  NIX_INSTALLER_YES=1 "$work/nix-${NIX_VERSION}-x86_64-linux/install" --no-daemon
  note "Nix を導入した (取得したものは $work に残る)"
}

# 導入直後は PATH に nix が無い。導入方式によって置き場所が異なるため両方を見る。
load_nix() {
  if command -v nix >/dev/null 2>&1; then
    return
  fi

  local candidate
  for candidate in \
    "$HOME/.nix-profile/etc/profile.d/nix.sh" \
    /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh; do
    if [ -f "$candidate" ]; then
      # shellcheck disable=SC1090
      . "$candidate"
      return
    fi
  done

  echo "エラー: 導入した Nix の profile スクリプトが見つかりません。" >&2
  exit 1
}

# --- 開発シェル --------------------------------------------------------------

# 開発シェルを profile として実体化する。profile は GC ルートであるため、以降この
# 閉包は削除されない。Dockerfile がイメージのビルド時に行っているのと同じ処理である。
build_dev_shell() {
  nix develop "$repo" --profile "$DOTFILES_PROFILE" --command true

  note "開発シェルを実体化した ($DOTFILES_PROFILE)"

  # flake archive は、開発シェルが参照しない入力も含めて store に取り込む。nix は
  # 評価に必要な入力しか取得しないため、これが無いと nixosConfigurations および
  # homeConfigurations が参照する入力 (nixos-wsl / home-manager) が無く、make check が
  # そこで取得を試みる。Dockerfile が同じ理由で行っている。
  #
  # ただしリモート実行環境の egress は環境の設定によって制限される。取得できない入力が
  # あってもセッションは成立する (開発シェルは既に揃っている) ため、ここでの失敗は
  # 構成全体の失敗とせず、何が起きたかを示して続ける。
  if (cd "$repo" && nix flake archive --json >/dev/null); then
    note "flake の入力をすべて store に取り込んだ"
  else
    note "flake の入力をすべては取得できなかった (egress の制限が疑われる)"
    note "make check が入力の取得で失敗する場合は、環境のネットワーク設定を確認する"
  fi
}

# セッションのシェルに開発シェルの環境を引き渡す。
#
# 値は開発シェルから取り出したものをそのまま使う。ここで PATH 等を組み立て直すと
# nix/devshell.nix の内容と乖離するため。shellHook の出力が混ざるので export 行だけを取る。
write_env_file() {
  local env_file=${CLAUDE_ENV_FILE:-}

  if [ -z "$env_file" ]; then
    note "CLAUDE_ENV_FILE が無いため環境変数は引き渡さない"
    note "この場合は nix develop $DOTFILES_PROFILE --command <コマンド> で実行する"
    return
  fi

  local exported
  # 展開は開発シェルの内側で行う。ここで展開してしまうと外側の値になる。
  # shellcheck disable=SC2016
  exported=$(
    nix develop "$DOTFILES_PROFILE" --command bash -c '
      for name in PATH USER DOTFILES_ENV DOTFILES_ROOT LC_ALL; do
        printf "export %s=%q\n" "$name" "${!name}"
      done
    ' | grep '^export ' || true
  )

  if [ -z "$exported" ]; then
    echo "エラー: 開発シェルから環境変数を取り出せませんでした。" >&2
    exit 1
  fi

  printf '%s\n' "$exported" >>"$env_file"
  note "開発シェルの環境を引き渡した ($env_file)"
}

# --- 実行 --------------------------------------------------------------------

step "Nix を導入する"
configure_nix
install_nix
load_nix

step "開発シェルを構築する"
build_dev_shell

step "セッションに環境を引き渡す"
write_env_file

step "環境を検査する"
nix develop "$DOTFILES_PROFILE" --command "$repo/scripts/check-env.sh"

step "構成を終えた"
