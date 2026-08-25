#!/usr/bin/env bash
#
# Claude Code および Codex のリモート実行環境 (クラウド) を構成する。
#
# 当該環境はセッションごとに用意される Ubuntu のコンテナであり、初期状態では Nix が
# 無い。本スクリプトは docs/setup.md と同じ手順で Nix を導入し、開発シェルを profile
# として実体化したうえで、その環境変数をセッションに引き渡す。これにより、以降の
# コマンドは他の環境と同一のツールで動作する。
#
# 呼ばれ方は 2 つある。
#
#   hook          本リポジトリの .claude/settings.json の SessionStart フックから。
#                 開発シェルの環境をセッションに引き渡す
#   setup-script  Claude Code または Codex の Setup script から。他のリポジトリでも
#                 本環境を使うための経路であり、ツールとホームの構成を配置する。
#                 system と $HOME を書き換えるため --disposable の明示を要する
#
# いずれもセッションの開始ごとに実行されるため、既に済んでいる処理は飛ばす。失敗した
# 場合はそのまま再実行できる。
#
# nix/packages.nix に無いツールを当該セッションに限って足す手段として、追加パッケージ
# の指定を受ける (--extra-packages および DOTFILES_EXTRA_PACKAGES)。クラウド環境の中に
# は、セットアップの完了後にネットワークを遮断するものがある。遮断後は取得できないため、
# ネットワークが生きている本スクリプトの実行中に store へ入れておく必要がある。
#
#   使用方法: scripts/cloud-setup.sh [--setup-script --disposable]
#             [--extra-packages "<名前> ..."]
set -euo pipefail

usage() {
  cat <<'USAGE'
使用方法: scripts/cloud-setup.sh [--setup-script --disposable]
                                 [--extra-packages "<名前> ..."]

オプション:
  --setup-script  クラウド環境の Setup script から呼ぶ経路。ツールを
                  /usr/local/bin へ、home/ 以下を $HOME へ配置する。
                  --disposable を併せて指定する必要がある
  --disposable    実行先が使い捨ての環境であることの明示。--setup-script が
                  行う配置は system と $HOME を書き換えるため、利用者のホストで
                  誤って実行されないよう明示を要求する
  --extra-packages "<名前> ..."
                  当該セッションに限って足す nixpkgs のパッケージ。空白区切りの
                  attribute 名で指定する (例: "python3 gcc")。環境変数
                  DOTFILES_EXTRA_PACKAGES でも同じ形式で指定でき、双方を与えた
                  場合は併合する。フックの経路は引数を渡せないため環境変数を使う

引数を与えない場合は SessionStart フックとしての動作となる。この経路は
CLAUDE_CODE_REMOTE=true の環境でのみ処理を行う。
USAGE
}

mode=hook
disposable=0

# 追加パッケージの名前。指定順を保つ。
extra_packages=()

# 実体化できなかった追加パッケージ。最後にまとめて報告する。
extra_failed=()

# 空白区切りの並びを受け取り、追加パッケージの一覧に足す。
#
# 引数と環境変数の双方から同じ名前が与えられることがあるため、重複は取り除く。
# 同じ名前を 2 度 install しても結果は変わらないが、その分だけ時間がかかり、
# 出力にも重複が出るためである。
add_extra_packages() {
  local list=$1
  local name
  local parsed=()

  # 区切りは空白と改行の双方とする。環境変数はクラウド環境の設定画面から複数行で
  # 与えられることがあり、既定の read では 1 行目しか読まないためである。入力の終端まで
  # 読む指定 (-d '') は終端で偽を返すため、それ自体は失敗として扱わない。
  #
  # 分割に read を用いるのは、$list を展開する方式では glob が働き、`*` のような指定が
  # ファイル名に化けるためである。
  read -rd '' -ra parsed <<<"$list" || true

  for name in "${parsed[@]}"; do
    case " ${extra_packages[*]} " in
      *" $name "*) continue ;;
    esac
    extra_packages+=("$name")
  done
}

# nixpkgs の attribute 名として妥当かを見る。
#
# 値は引数として nix に渡すため、シェルの解釈による注入は起こらない。ここで弾くのは
# nix に別の意味で解釈される形である。すなわち、オプションと解釈される先頭の `-` と、
# flakeref の区切りである `#` を含むものである。後者は `nixpkgs#python3` のように参照を
# 明示した場合に起こる。いずれも本スクリプトが `nixpkgs#<名前>` を組み立てるため要らない。
validate_extra_package() {
  local name=$1

  case "$name" in
    -*)
      echo "エラー: 追加パッケージの名前が - で始まっています: $name" >&2
      return 1
      ;;
    *'#'*)
      echo "エラー: 追加パッケージには flakeref ではなく attribute 名を与えます: $name" >&2
      echo "       例: 'nixpkgs#python3' ではなく 'python3'" >&2
      return 1
      ;;
    *[!A-Za-z0-9._+-]*)
      echo "エラー: 追加パッケージの名前に使用できない文字があります: $name" >&2
      return 1
      ;;
  esac
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --setup-script) mode=setup-script ;;
    --disposable) disposable=1 ;;
    --extra-packages)
      if [ "$#" -lt 2 ]; then
        echo "エラー: --extra-packages には値が必要です。" >&2
        exit 1
      fi
      add_extra_packages "$2"
      shift
      ;;
    --extra-packages=*) add_extra_packages "${1#*=}" ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "エラー: 引数が不明です: $1" >&2
      echo >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

# フックの経路は引数を渡せない (コマンドが .claude/settings.json に固定されている)。
# クラウド環境の設定で与えられる環境変数を、引数と同じ形式で受ける。
add_extra_packages "${DOTFILES_EXTRA_PACKAGES:-}"

# 名前の検査は Nix を導入するより前に済ませる。誤りが分かるのが構成の終盤では、
# 待ち時間の後にやり直すことになるためである。1 つ目で止めず、すべて報告する。
extra_invalid=0
for package in "${extra_packages[@]}"; do
  validate_extra_package "$package" || extra_invalid=1
done

if [ "$extra_invalid" -ne 0 ]; then
  echo >&2
  echo "追加パッケージは nixpkgs の attribute 名を空白区切りで指定します。" >&2
  echo "  例: --extra-packages \"python3 gcc python3Packages.requests\"" >&2
  exit 1
fi

# フックから呼ばれた場合はリモート実行環境でのみ動作させる。手元の環境は direnv または
# nix develop で開発シェルに入る (docs/setup.md)。利用者のホストに Nix を導入する経路を
# ここに作らない。
#
# Setup script は Claude Code の起動より前に走り、当該変数を持たないため対象外とする。
# こちらは利用者が環境の設定として明示的に書いたときにしか実行されない。
if [ "$mode" = hook ] && [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  echo "リモート実行環境ではないため何もしない (CLAUDE_CODE_REMOTE が true でない)。"
  exit 0
fi

# Setup script の経路は、フックと違って環境変数による判定ができない。使い捨ての環境で
# あることを --disposable の明示で確認する。当該環境をコンテナの印 (/.dockerenv、
# /run/.containerenv、/proc/1/cgroup) から判定する方式は採らない。実際のクラウド環境には
# いずれも存在せず、判定できないためである。
#
# この経路は /usr/local/bin へ system の同名のコマンドを覆う symlink を張り、$HOME の
# ファイルを置き換える。利用者のホストで誤って実行された場合の影響が大きいため、
# 引数の明示を要求する。
if [ "$mode" = setup-script ] && [ "$disposable" -ne 1 ]; then
  echo "エラー: --setup-script には --disposable が必要です。" >&2
  echo >&2
  echo "本経路は /usr/local/bin と \$HOME を書き換えます。使い捨てのクラウド実行環境" >&2
  echo "でのみ実行してください。手元の環境では nix develop または" >&2
  echo "direnv を使います (docs/setup.md)。" >&2
  echo >&2
  echo "  scripts/cloud-setup.sh --setup-script --disposable" >&2
  exit 1
fi

# 配置先はいずれも root を要する。非 root で走った場合、Nix の導入まで進んでから
# 途中で失敗するため、先に止める。
if [ "$mode" = setup-script ] && [ "$(id -u)" -ne 0 ]; then
  echo "エラー: --setup-script は root で実行してください (現在: $(id -un))。" >&2
  exit 1
fi

script_dir=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$script_dir/.." && pwd)

# shellcheck source=scripts/nix-pin.sh
. "$script_dir/nix-pin.sh"

# 実体化した開発シェルの配置先。Dockerfile が使う名前と揃える。
readonly DOTFILES_PROFILE=/nix/var/nix/profiles/dotfiles-dev

# 追加パッケージの配置先。開発シェルの profile とは分ける。
#
# nix/packages.nix は開発シェル、`nix build` の profile、Docker イメージの単一情報源で
# あり、その内容はリポジトリのすべての環境で同一である。追加パッケージは当該セッション
# に限るものであるため、そこへ混ぜず別の profile に置く。どちらの経路で入ったツールかが
# 実行時にも区別できる。
readonly DOTFILES_EXTRA_PROFILE=/nix/var/nix/profiles/dotfiles-extra

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
  # サンドボックスは無効化しない。Dockerfile 側は docker build の seccomp プロファイル
  # との競合のために無効化しているが、当該環境ではその制約が無く、sandbox と
  # filter-syscalls を有効にしたまま stdenv を用いるビルドまで成立する (user namespace
  # が利用できる)。ビルドは root で走るため、無効化すると隔離が失われる。
  printf '%s\n' \
    "$NIX_FLAKE_CONF" \
    'build-users-group =' \
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

# --- 追加パッケージ ----------------------------------------------------------

# 指定された nixpkgs のパッケージを store へ入れ、profile に載せる。
#
# nixpkgs は `--inputs-from` で本リポジトリの flake の入力を参照する。registry の
# `nixpkgs` をそのまま使うと固定されていないリビジョンを引き、開発シェルと異なる
# nixpkgs から取ることになる。入力は flake.lock で固定されており、開発シェルと同一の
# リビジョンから解決される (store も共有される)。
#
# 1 つずつ install する。まとめて渡すと 1 つの誤りで全体が失敗し、正しく指定された分も
# 入らない。ネットワークが遮断される環境では後から入れ直せないため、入るものは入れる。
#
# 既に入っているパッケージは nix が警告して成功するため、再実行はそのまま通る。
install_extra_packages() {
  local name

  for name in "${extra_packages[@]}"; do
    if nix profile install \
      --inputs-from "$repo" \
      --profile "$DOTFILES_EXTRA_PROFILE" \
      "nixpkgs#$name"; then
      note "実体化した: $name"
    else
      note "実体化できなかった: $name"
      extra_failed+=("$name")
    fi
  done

  if [ "${#extra_failed[@]}" -eq 0 ]; then
    note "追加パッケージを profile に置いた ($DOTFILES_EXTRA_PROFILE)"
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

  # 追加パッケージは開発シェルの外にあるため、その bin を PATH の先頭に足す。
  # 先頭に置くのは、後ろでは system の同名のコマンドに負けるためである
  # (開発シェルから取り出した PATH は既に system の分を含む)。
  local extra_bin=
  if [ -d "$DOTFILES_EXTRA_PROFILE/bin" ]; then
    extra_bin=$DOTFILES_EXTRA_PROFILE/bin
  fi

  local exported
  # 展開は開発シェルの内側で行う。ここで展開してしまうと外側の値になる。
  # shellcheck disable=SC2016
  exported=$(
    nix develop "$DOTFILES_PROFILE" --command bash -c '
      if [ -n "$1" ]; then
        PATH=$1:$PATH
      fi

      for name in PATH USER DOTFILES_ENV DOTFILES_ROOT LC_ALL; do
        printf "export %s=%q\n" "$name" "${!name}"
      done
    ' bash "$extra_bin" | grep '^export ' || true
  )

  if [ -z "$exported" ]; then
    echo "エラー: 開発シェルから環境変数を取り出せませんでした。" >&2
    exit 1
  fi

  printf '%s\n' "$exported" >>"$env_file"
  note "開発シェルの環境を引き渡した ($env_file)"
}

# --- 他のリポジトリから使うための配置 (--setup-script) ------------------------

# 動かしているリビジョンを示す。
#
# この経路は本リポジトリを固定せず、最新を使う運用を許す (docs/reproducibility.md)。
# 固定しない以上、何を動かしているかは実行時にしか分からない。戻す判断ができるよう、
# 実際に使ったリビジョンを出力する。
show_revision() {
  local revision

  if revision=$(git -C "$repo" log -1 --format='%H %cs %s' 2>/dev/null); then
    note "$revision"
  else
    note "リビジョンを取得できない ($repo は git のリポジトリではない)"
  fi
}

# ツールをセッションの PATH に載せる。
#
# フックと違い Setup script には CLAUDE_ENV_FILE が無く、環境変数を引き渡す手段が
# ない。セッションのシェルは /etc/profile を読まない (ツールは bash -c で起動し、
# 事前に作られるシェルの写しにも /etc/profile.d の内容は入らない) ため、profile.d や
# rc ファイルでも渡せない。既に PATH にある /usr/local/bin へ実体を置く。
#
# 開発シェルではなく nix build .#default の profile を対象とする。前者は
# nix develop を経由しなければ入れないが、後者は bin/ を持つ通常のディレクトリで
# あるため symlink できる。中身はいずれも nix/packages.nix である。
#
# system の同名のコマンド (git、coreutils 等) は Nix 版に置き換わる。環境を揃える
# ことが目的であるため意図した挙動だが、影響する範囲であるため docs/setup.md に明記し、
# 実際に覆ったものを実行時にも示す。
install_toolchain() {
  local profile=/nix/var/nix/profiles/dotfiles-toolchain
  local dir source target name existing
  local count=0
  local shadowed=()

  if [ -e "$profile" ]; then
    note "ツールの profile は既にある ($profile)"
  else
    nix profile install --profile "$profile" "$repo#default"
    note "ツールを profile として実体化した ($profile)"
  fi

  # profile が空でないことを、配置する前に確かめる。配置の総数で見ると、nix 自身や
  # 追加パッケージの分で 0 にならず、ツールが入っていないことを見落とす。
  if ! compgen -G "$profile/bin/*" >/dev/null; then
    echo "エラー: $profile/bin にコマンドがありません。" >&2
    exit 1
  fi

  mkdir -p /usr/local/bin

  # nix 自身も対象に含める。他のリポジトリのセッションでも nix develop や nix shell を
  # 使えるようにするため。導入方式によって置き場所が異なるため、解決済みの nix から辿る。
  local nix_bin
  nix_bin=$(dirname "$(command -v nix)")

  # 追加パッケージは最後に置く。同名がある場合は後から張った symlink が残るため、
  # フックの経路で PATH の先頭に足すのと同じ優先順位になる。
  local dirs=("$profile/bin" "$nix_bin" "$DOTFILES_EXTRA_PROFILE/bin")

  for dir in "${dirs[@]}"; do
    for source in "$dir"/*; do
      # 対象が無い場合、glob は展開されずそのまま残る。
      [ -e "$source" ] || continue

      name=$(basename "$source")
      target=/usr/local/bin/$name

      # 置き換える前に、system 側で同名が解決できていたかを見る。既に本処理が張った
      # symlink (/usr/local/bin) と Nix の実体は対象から除く。
      existing=$(command -v "$name" 2>/dev/null || true)
      case "$existing" in
        "" | /usr/local/bin/* | /nix/*) ;;
        *) shadowed+=("$name") ;;
      esac

      ln -sfn "$source" "$target"
      count=$((count + 1))
    done
  done

  note "/usr/local/bin へ配置した ($count 件)"

  if [ "${#shadowed[@]}" -ne 0 ]; then
    note "system の同名のコマンドを覆った (${#shadowed[@]} 件): ${shadowed[*]}"
  fi
}

# home/ 以下をホームディレクトリの構造に対応させて配置する。
#
# home-manager は使わない。当該環境からは flake の入力 (nix-community/home-manager)
# を取得できないため (docs/setup.md の「到達範囲の制限」)。したがって配置の機構は
# 手元の環境と異なる。置く内容は同一である。
#
# 既存のファイルは上書きする。使い捨ての VM であり、かつ本処理は Claude Code の起動
# より前に走るため、セッションが書いたものを消すことはない。
#
# ただし内容が異なるものを黙って消さない。最初に見つけた状態を .dotfiles-backup へ
# 退避し、退避先を出力する。退避は 1 度だけ行う。再実行のたびに上書きすると、本処理が
# 置いた内容で元の状態が置き換わるためである。
install_home() {
  local source target backup

  while IFS= read -r source; do
    case "$source" in
      "$repo/home/.codex/"*)
        # Codex は設定の基点を CODEX_HOME から探索する。Cloud runtime では
        # HOME/.codex と異なるため、.codex 以下はそちらへ対応させる。
        target=${CODEX_HOME:-"$HOME/.codex"}/${source#"$repo/home/.codex/"}
        ;;
      *) target=$HOME/${source#"$repo/home/"} ;;
    esac
    backup=$target.dotfiles-backup
    mkdir -p "$(dirname "$target")"

    if [ -e "$target" ] && [ ! -e "$backup" ] && ! cmp -s "$source" "$target"; then
      cp -p "$target" "$backup"
      note "退避した ${backup#"$HOME/"}"
    fi

    cp -f "$source" "$target"
    note "配置した ${target#"$HOME/"}"
  done < <(find "$repo/home" -type f)
}

# --- 実行 --------------------------------------------------------------------

if [ "$mode" = setup-script ]; then
  step "使用する dotfiles のリビジョン"
  show_revision
fi

step "Nix を導入する"
configure_nix
install_nix
load_nix

step "開発シェルを構築する"
build_dev_shell

# 追加パッケージは開発シェルより後、配置より前に置く。前者は nixpkgs の解決に
# flake の入力を使うため、後者は配置の対象に含めるためである。
if [ "${#extra_packages[@]}" -ne 0 ]; then
  step "追加パッケージを実体化する"
  install_extra_packages
fi

if [ "$mode" = hook ]; then
  step "セッションに環境を引き渡す"
  write_env_file
else
  step "ツールを配置する"
  install_toolchain

  step "ホームディレクトリの構成を配置する"
  install_home
fi

step "環境を検査する"
nix develop "$DOTFILES_PROFILE" --command "$repo/scripts/check-env.sh"

# 追加パッケージの失敗は、構成を最後まで進めてから報告する。ここで途中で止めると、
# 名前を 1 つ誤っただけで開発シェルの引き渡しごと失われ、セッションが構成前の状態に
# なるためである。指定されたものが揃っていない事実は残すため、終了状態は失敗とする。
if [ "${#extra_failed[@]}" -ne 0 ]; then
  step "追加パッケージを実体化できなかった"
  echo "エラー: 次のパッケージを実体化できませんでした: ${extra_failed[*]}" >&2
  echo "       名前は nixpkgs の attribute である必要があります" >&2
  echo "       (https://search.nixos.org/packages で確認できます)。" >&2
  echo "       他の構成は完了しているため、指定を直して再実行すれば足ります。" >&2
  exit 1
fi

step "構成を終えた"
