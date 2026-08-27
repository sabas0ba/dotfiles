#!/usr/bin/env bash
#
# WSL のディストリビューション内部で行う構成。scripts/wsl-bootstrap.ps1 から呼ばれる。
#
# Windows 側の PowerShell は静的解析の対象外であるため、判断を伴う処理は本ファイルに
# 寄せてある。bootstrap 側に残るのは、イメージの取得と登録、および本ファイルが存在
# しない時点で必要となる 2 つの短い呼び出し (ユーザーの作成とリポジトリの取得) のみ。
#
# 段は 2 つある。/etc/wsl.conf はディストリビューションの起動時にしか読まれないため、
# 間に再起動を挟む必要があるため。
#
#   system  root で実行する。/etc/wsl.conf、ユーザー、Nix、system の構成
#   home    利用者で実行する。環境の検査とホームディレクトリへの配置
#
# いずれの段も、既に済んでいる処理は飛ばす。失敗した場合はそのまま再実行できる。
#
# 利用者名と nixosConfigurations の名前はオプションで差し替えられる。同じ環境の
# 改変版を別のディストリビューションとして併存させる場合に用いる。
#
#   使用方法: scripts/wsl-provision.sh <段> <distro> [オプション]  (--help で一覧)
set -euo pipefail

usage() {
  cat <<'USAGE'
使用方法: scripts/wsl-provision.sh <段> <distro> [オプション]

段:
  system   root で実行する。/etc/wsl.conf、ユーザー、Nix、system の構成
  home     利用者で実行する。環境の検査とホームディレクトリへの配置
  wslconf  wsl.conf の構成のみを行う。復旧および検査に使う (distro は参照しない)

distro:
  nixos   NixOS-WSL。system の構成は nix/wsl.nix が持つ
  ubuntu  Ubuntu。Nix を導入する。system は宣言的にならない

オプション:
  --user <名前>          WSL 上の利用者。既定 nixos。flake.nix の homeTargets に
                         同名の対象が必要である
  --flake-target <名前>  nixosConfigurations の名前。既定 wsl
  --wsl-conf <パス>      wsl.conf の対象。既定 /etc/wsl.conf。検査で差し替える

同じ環境の改変版を別の WSL ディストリビューションとして併存させる場合は、
--user と --flake-target で対象を分ける。登録名とリポジトリは
scripts/wsl-bootstrap.ps1 の -Name と -RepoUrl で指定する。

通常は scripts/wsl-bootstrap.ps1 から呼ばれる。単独で再実行することもできる。
USAGE
}

if [ "$#" -lt 2 ]; then
  usage >&2
  exit 1
fi

stage=$1
distro=$2
shift 2

# 既定値。上書きは以降のオプションで行う。
provision_user=nixos
flake_target=wsl
wsl_conf=/etc/wsl.conf

while [ "$#" -gt 0 ]; do
  case "$1" in
    --user)
      provision_user=${2:?--user に値が必要です}
      shift 2
      ;;
    --flake-target)
      flake_target=${2:?--flake-target に値が必要です}
      shift 2
      ;;
    --wsl-conf)
      wsl_conf=${2:?--wsl-conf に値が必要です}
      shift 2
      ;;
    *)
      echo "エラー: オプションが不明です: $1" >&2
      echo >&2
      usage >&2
      exit 1
      ;;
  esac
done

case "$distro" in
  nixos | ubuntu) ;;
  *)
    echo "エラー: distro が不明です: $distro" >&2
    exit 1
    ;;
esac

script_dir=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$script_dir/.." && pwd)

# Ubuntu 経路で導入する Nix の版。定義は 1 か所に置き、ここでは複製しない
# (scripts/cloud-setup.sh も同じファイルを参照する)。
# shellcheck source=scripts/nix-pin.sh
. "$script_dir/nix-pin.sh"
# shellcheck source=scripts/pinned-download.sh
. "$script_dir/pinned-download.sh"

step() {
  printf '\n== %s\n' "$1"
}

note() {
  printf '   %s\n' "$1"
}

# --- /etc/wsl.conf -----------------------------------------------------------
#
# 隔離の設定と既定ユーザーを与える。既存の内容は保持する。イメージが出荷時に持つ
# 設定 (Ubuntu の [boot] systemd 等) を消すと、以降の処理が成立しないため、丸ごと
# 上書きせず、自分が管理するキーだけを差し替える。
#
# NixOS では扱わない。当該経路のこのファイルは nix/wsl.nix から生成された Nix store
# への symlink であり、書き込めないため。呼ばれるのは Ubuntu 経路と、段 wslconf
# (復旧および検査) のときだけである。

readonly MANAGED_SECTIONS=(automount interop user)

emit_managed_keys() {
  case "$1" in
    automount) printf 'enabled = false\n' ;;
    interop) printf 'enabled = false\nappendWindowsPath = false\n' ;;
    user) printf 'default = %s\n' "$provision_user" ;;
  esac
}

is_managed_section() {
  case " ${MANAGED_SECTIONS[*]} " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

is_managed_key() {
  case "$1/$2" in
    automount/enabled | interop/enabled | interop/appendWindowsPath | user/default) return 0 ;;
    *) return 1 ;;
  esac
}

merge_wsl_conf() {
  local path=$1
  local section='' line key managed_line
  local output=()
  local seen=()

  if [ -f "$path" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      if [[ $line =~ ^[[:space:]]*\[([^]]+)\][[:space:]]*$ ]]; then
        # 直前のセクションが管理対象であれば、その末尾で自分のキーを出す。
        if [ -n "$section" ] && is_managed_section "$section"; then
          while IFS= read -r managed_line; do
            output+=("$managed_line")
          done < <(emit_managed_keys "$section")
        fi

        section=${BASH_REMATCH[1]}
        seen+=("$section")
        output+=("$line")
        continue
      fi

      if [[ $line =~ ^[[:space:]]*([A-Za-z0-9_]+)[[:space:]]*= ]]; then
        key=${BASH_REMATCH[1]}
        # 管理対象のキーは捨てる。セクションの末尾で自分の値を出すため。
        if [ -n "$section" ] && is_managed_key "$section" "$key"; then
          continue
        fi
      fi

      output+=("$line")
    done <"$path"

    if [ -n "$section" ] && is_managed_section "$section"; then
      while IFS= read -r managed_line; do
        output+=("$managed_line")
      done < <(emit_managed_keys "$section")
    fi
  else
    output+=('# WSL の設定。scripts/wsl-provision.sh が管理するキーを含む。')
  fi

  # 現れなかった管理対象のセクションを追記する。
  local candidate found existing
  for candidate in "${MANAGED_SECTIONS[@]}"; do
    found=0
    for existing in ${seen[@]+"${seen[@]}"}; do
      if [ "$existing" = "$candidate" ]; then
        found=1
        break
      fi
    done

    if [ "$found" -eq 0 ]; then
      output+=("[$candidate]")
      while IFS= read -r managed_line; do
        output+=("$managed_line")
      done < <(emit_managed_keys "$candidate")
    fi
  done

  printf '%s\n' "${output[@]}" >"$path"
}

# --- 段: system --------------------------------------------------------------

ensure_sudoers() {
  local path=/etc/sudoers.d/$provision_user

  if [ -f "$path" ]; then
    note "sudo の設定は既にある ($path)"
    return
  fi

  # パスワードを要求しない。WSL では wsl.exe -u root で無条件に root になれるため、
  # ここでのパスワードは境界として機能しない。NixOS-WSL が既定ユーザーに対して
  # security.sudo.wheelNeedsPassword = false としているのと同じ扱いに揃える。
  printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$provision_user" >"$path"
  chmod 0440 "$path"
  note "sudo をパスワード無しで許可した ($path)"
}

install_nix() {
  if [ -e /nix/var/nix/profiles/default ]; then
    note "Nix は既に導入されている"
    return
  fi

  local work=$repo/.work/nix
  local tarball="nix-${NIX_VERSION}-x86_64-linux.tar.xz"
  local url="https://releases.nixos.org/nix/nix-${NIX_VERSION}/${tarball}"
  local owner

  # 作業用のファイルはリポジトリ内の git ignore された場所に置く。ただし本段は root
  # で動くため、作ったディレクトリの所有者を利用者に合わせる。root 所有のまま残すと、
  # 以降 .work が利用者から書けなくなる。
  owner=$(stat -c '%U:%G' "$repo")
  mkdir -p "$work"
  chown "$owner" "$repo/.work" "$work"

  # 固定した値と照合する。配布元から取得した .sha256 との照合は、配布物と同時に
  # 差し替えられるため検証にならない。README の導入手順と同じ方針である。
  note "Nix の配布物を用意する: $url"
  pinned_download "$url" "$NIX_SHA256" "$work/$tarball"

  tar -xf "$work/$tarball" -C "$work"

  # NIX_INSTALLER_YES で確認のプロンプトを省く。
  NIX_INSTALLER_YES=1 "$work/nix-${NIX_VERSION}-x86_64-linux/install" --daemon
  chown -R "$owner" "$work"
  note "Nix を導入した (取得したものは $work に残る)"
}

enable_flakes() {
  local path=/etc/nix/nix.conf

  if [ -f "$path" ] && grep -qF "$NIX_FLAKE_CONF" "$path"; then
    note "flakes は既に有効である"
    return
  fi

  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$NIX_FLAKE_CONF" >>"$path"
  note "flakes を有効にした ($path)"
}

# nix の git fetcher (libgit2) は、リポジトリの所有者が実行ユーザーと異なる場合に
# 開くことを拒否する。nixos-rebuild は root で動く一方、リポジトリは利用者のもので
# あるため、当該パスを例外として登録する。
#
# これは provision だけの問題ではない。以降 make wsl-switch を実行するたびに同じ経路
# を通るため、恒久的な設定として置く。対象はこのリポジトリのパスに限る ('*' は使わない)。
#
# git コマンドは使わない。NixOS では初回の switch まで root の PATH に git が無い。
ensure_root_safe_directory() {
  local path=/root/.gitconfig

  if [ -f "$path" ] && grep -qF "directory = $repo" "$path"; then
    note "safe.directory は登録済み ($repo)"
    return
  fi

  printf '[safe]\n\tdirectory = %s\n' "$repo" >>"$path"
  note "root の safe.directory に $repo を登録した ($path)"
}

apply_nixos_system() {
  local expected

  # 初回は本リポジトリの構成が未適用であり flakes が有効になっていないため、
  # NIX_CONFIG で補う。2 回目以降は nix/wsl.nix が同じ設定を持つ。
  expected=$(
    NIX_CONFIG=$NIX_FLAKE_CONF nix build --no-link --print-out-paths \
      "$repo#nixosConfigurations.$flake_target.config.system.build.toplevel"
  )

  if NIX_CONFIG=$NIX_FLAKE_CONF nixos-rebuild switch --flake "$repo#$flake_target"; then
    return
  fi

  # nixos-rebuild は systemd の user unit を再読込できなかった場合にも非零で終わる。
  # WSL では対話セッションの外に user session が無いため、provision からの実行では
  # これが起きる。system 側の切り替えは完了しているため、終了コードではなく実際に
  # 入れ替わったかどうかで判断する。
  if [ "$(readlink -f /run/current-system)" = "$expected" ]; then
    note "user unit の再読込には失敗したが、system の構成は適用されている"
    note "user session は次回の起動で開始する"
    return
  fi

  echo "エラー: system の構成を適用できませんでした。" >&2
  echo "  期待した構成: $expected" >&2
  echo "  現在の構成:   $(readlink -f /run/current-system)" >&2
  exit 1
}

provision_system() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "エラー: 段 system は root で実行してください。" >&2
    exit 1
  fi

  if [ "$distro" = nixos ]; then
    # NixOS では /etc/wsl.conf は nix/wsl.nix から生成され、Nix store への symlink と
    # して置かれる。書き込めないため触らない。隔離はこの後の switch で成立する。
    step "$wsl_conf は nix/wsl.nix が生成する"
    note "宣言的に管理されているため書き換えない"
  else
    step "$wsl_conf を構成する"
    merge_wsl_conf "$wsl_conf"
    note "隔離の設定と既定ユーザー ($provision_user) を反映した"
  fi

  if [ "$distro" = ubuntu ]; then
    step "sudo を構成する"
    ensure_sudoers

    step "Nix を導入する"
    install_nix
    enable_flakes
  fi

  if [ "$distro" = nixos ]; then
    step "root から本リポジトリを読めるようにする"
    ensure_root_safe_directory

    step "system の構成を適用する"
    apply_nixos_system
  fi

  step "段 system を終えた"
  note "反映には再起動が必要である (Windows 側で wsl.exe --terminate)"
}

# --- 段: home ----------------------------------------------------------------

provision_home() {
  if [ "$(id -un)" != "$provision_user" ]; then
    echo "エラー: 段 home は $provision_user で実行してください。" >&2
    exit 1
  fi

  cd "$repo"

  step "環境を検査する"
  # make は開発シェルから取る。ディストリビューション側には要求しない。
  nix develop --command make check

  step "ホームディレクトリへ配置する"
  nix develop --command make hm-switch

  step "段 home を終えた"
}

case "$stage" in
  system) provision_system ;;
  home) provision_home ;;
  wslconf) merge_wsl_conf "$wsl_conf" ;;
  *)
    echo "エラー: 段が不明です: $stage" >&2
    echo >&2
    usage >&2
    exit 1
    ;;
esac
