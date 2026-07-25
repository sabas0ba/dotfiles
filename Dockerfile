# syntax=docker/dockerfile:1
#
# ホストの `nix develop` と同一の環境をコンテナ内に構築する。
#
# 方針:
#   - ツールの一覧を本ファイルに記述しない。flake.nix および nix/packages.nix を
#     参照する。これによりホストとコンテナで内容が乖離しない。
#   - ビルド時に開発シェルを Nix の profile として実体化し、実行時はその profile に
#     入るだけとする (scripts/docker-entrypoint.sh)。実行時に flake を評価しないため、
#     起動が速く、ネットワークが無くても動作する。
#
# 使用方法:
#   docker build -t dotfiles-dev .
#   docker run --rm -it -v "$PWD:/workspace" dotfiles-dev
#   docker run --rm -v "$PWD:/workspace" dotfiles-dev scripts/check-env.sh
#
#   Makefile 経由: make docker-build / make docker-shell / make docker-check

# ベースイメージはタグに加えてダイジェストで固定する。タグは再割り当てが可能であり、
# 固定にはならない。更新時は NIX_VERSION と NIX_IMAGE_DIGEST を同時に変更する。
# ダイジェストの取得: docker buildx imagetools inspect nixos/nix:<version>
ARG NIX_VERSION=2.35.1
ARG NIX_IMAGE_DIGEST=sha256:377d4887aca98f0dfa12971c1ea6d6a625a435d8b610d4c95a436843da6fbfd1
FROM nixos/nix:${NIX_VERSION}@${NIX_IMAGE_DIGEST}

# flake を使用するため experimental-features を有効化する。
# sandbox と filter-syscalls を無効化しているのは、Docker のデフォルト seccomp
# プロファイルと Nix のサンドボックスが競合してビルドが失敗するため。本イメージでは
# 依存をすべて cache.nixos.org のバイナリで取得し、ビルドは行わない。
#
# flake-registry を空にしているのは、本リポジトリの flake が入力をすべて固定しており
# グローバルレジストリを参照しないため。空にしない場合、ネットワークの無い環境で
# nix を実行するたびに channels.nixos.org への取得失敗が出力される。
# 名前 `nixpkgs` の解決先は後段で本リポジトリが固定した nixpkgs に設定する。
RUN mkdir -p /etc/nix \
  && printf '%s\n' \
  'experimental-features = nix-command flakes' \
  'sandbox = false' \
  'filter-syscalls = false' \
  'max-jobs = auto' \
  'flake-registry = ' \
  >> /etc/nix/nix.conf

# 実体化した開発シェルの配置先。scripts/docker-entrypoint.sh と一致させる。
ENV DOTFILES_PROFILE=/nix/var/nix/profiles/dotfiles-dev

WORKDIR /workspace

# 環境の定義のみを先に配置する。これを独立したレイヤにすることで、dotfiles 本体の
# 変更でツールの再取得が発生しない。
COPY flake.nix flake.lock ./
COPY nix ./nix

# 開発シェルを profile として実体化する。profile は GC ルートであるため、以降この
# 閉包は削除されない。
#
# あわせて名前 `nixpkgs` を、flake.lock で固定した nixpkgs 自身に解決させる。
# コンテナ内の `nix shell nixpkgs#jq` 等が開発シェルと同一の nixpkgs を参照し、
# ネットワークを必要としない。
#
# 末尾の rm は取得済み tarball の展開キャッシュの削除であり、store は変更しない。
RUN nix develop --profile "$DOTFILES_PROFILE" --command true \
  && nix registry add nixpkgs \
  "path:$(nix eval --raw --impure --expr '(builtins.getFlake "/workspace").inputs.nixpkgs.outPath')" \
  && rm -rf /root/.cache/nix

# dotfiles 本体を配置する。実行時に -v "$PWD:/workspace" を指定した場合はマウントで
# 上書きされる。マウントせずに実行することもできる。
COPY . .

COPY scripts/docker-entrypoint.sh /usr/local/bin/dotfiles-entrypoint.sh
RUN chmod +x /usr/local/bin/dotfiles-entrypoint.sh

# ベースイメージにおける /usr/bin/env の存在を前提としないため、sh を明示的に指定する。
ENTRYPOINT ["/bin/sh", "/usr/local/bin/dotfiles-entrypoint.sh"]
CMD []
