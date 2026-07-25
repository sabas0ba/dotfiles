# syntax=docker/dockerfile:1
#
# ホストの `nix develop` と同じ環境をコンテナの中に作る Dockerfile。
#
# 設計方針:
#   - ツールの一覧をここに書かない。flake.nix / nix/packages.nix をそのまま使う。
#     したがって「Dockerfile とホストで入っているものが違う」状態が原理的に起きない。
#   - ビルド時に開発シェルを Nix の profile として実体化しておき、実行時は
#     その profile に入るだけにする (scripts/docker-entrypoint.sh)。
#     起動が速く、ネットワークが無くても動く。
#
# 使い方:
#   docker build -t dotfiles-dev .
#   docker run --rm -it -v "$PWD:/workspace" dotfiles-dev
#   docker run --rm -v "$PWD:/workspace" dotfiles-dev scripts/check-env.sh
#
#   Makefile からも呼べる: make docker-build / make docker-shell / make docker-check

# ベースイメージも固定する。
# さらに厳密にしたい場合は `nixos/nix@sha256:...` とダイジェストで指定する。
ARG NIX_VERSION=2.35.1
FROM nixos/nix:${NIX_VERSION}

# flake を使うので experimental-features を有効にする。
# Docker のデフォルト seccomp プロファイルと Nix のサンドボックスが噛み合わず
# ビルドが落ちることがあるため、コンテナ内では sandbox を切っておく
# (どのみち依存はすべて cache.nixos.org からのバイナリで、ここでは何もビルドしない)。
#
# flake-registry を空にしているのは、この repo の flake が入力をすべて自前で固定して
# いてグローバルレジストリを引く必要が無いため。空にしないと、ネットワークの無い環境で
# nix を叩くたびに channels.nixos.org への取得失敗が出力される。
# 代わりに `nixpkgs` という名前は下でこの repo が固定した nixpkgs に向ける。
RUN mkdir -p /etc/nix \
  && printf '%s\n' \
  'experimental-features = nix-command flakes' \
  'sandbox = false' \
  'filter-syscalls = false' \
  'max-jobs = auto' \
  'flake-registry = ' \
  >> /etc/nix/nix.conf

# 実体化した開発シェルの置き場所。entrypoint と合わせる。
ENV DOTFILES_PROFILE=/nix/var/nix/profiles/dotfiles-dev

WORKDIR /workspace

# --- 1) 環境の定義だけを先にコピーする -------------------------------------
# ここだけを別レイヤにしておくと、dotfiles 本体を変更してもツールの再取得が起きない。
# flake.lock は「まだ生成していない」場合もあるので glob で任意扱いにしている
# (その場合はここで生成され、nixpkgs は flake.nix の rev 固定で決まる)。
COPY flake.nix flake.lock* ./
COPY nix ./nix

# --- 2) 開発シェルを profile として実体化する -------------------------------
# `nix develop --profile` は devShell の環境を profile に書き出す。
# profile は GC ルートなので、以降この閉包は消えない。
#
# あわせて `nixpkgs` という名前を、この repo が flake.lock で固定した nixpkgs 自身に
# 向けておく。コンテナの中で `nix shell nixpkgs#jq` のような使い方をしても、開発シェルと
# 同じ nixpkgs が使われ、しかもネットワークを引かない。
#
# 最後の rm は取得済み tarball の展開キャッシュを捨てているだけで、store には触らない。
RUN nix develop --profile "$DOTFILES_PROFILE" --command true \
  && nix registry add nixpkgs \
  "path:$(nix eval --raw --impure --expr '(builtins.getFlake "/workspace").inputs.nixpkgs.outPath')" \
  && rm -rf /root/.cache/nix

# --- 3) dotfiles 本体をコピーする ------------------------------------------
# 実行時に -v "$PWD:/workspace" でマウントすればこのコピーは上書きされる。
# マウントせずにそのまま動かすこともできる。
COPY . .

COPY scripts/docker-entrypoint.sh /usr/local/bin/dotfiles-entrypoint.sh
RUN chmod +x /usr/local/bin/dotfiles-entrypoint.sh

# ベースイメージに /usr/bin/env がある前提を置きたくないので明示的に sh で起動する。
ENTRYPOINT ["/bin/sh", "/usr/local/bin/dotfiles-entrypoint.sh"]
CMD []
