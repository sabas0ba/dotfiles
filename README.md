# dotfiles

Nix と direnv による再現性のある開発環境、および同一の定義から構築するコンテナ環境。

環境に含まれるツールの一覧は [`nix/packages.nix`](nix/packages.nix) の 1 か所のみで
定義し、ホストの開発シェル、`nix build` の profile、Docker イメージの 3 つすべてが
これを参照する。したがってホストとコンテナで内容が乖離しない。

本ファイルが本リポジトリの規約の所在である。Claude Code に対する指示 (`CLAUDE.md`)
も本ファイルを参照する。

## 前提

- [Nix](https://nixos.org/download/) (flakes を有効化すること)
- [direnv](https://direnv.net/) (任意。導入すると `cd` のみで環境に入る)
- Docker (任意。コンテナ環境を使用する場合のみ)

### Nix の導入

配布物をバージョン固定で取得し、チェックサムを検証してから展開する。インストーラを
検証せずに直接実行する方式 (`curl ... | sh`) は用いない。

```bash
NIX_VERSION=2.35.1
BASE="https://releases.nixos.org/nix/nix-${NIX_VERSION}"
TARBALL="nix-${NIX_VERSION}-$(uname -m)-linux.tar.xz"

curl -LO "${BASE}/${TARBALL}"
curl -L "${BASE}/${TARBALL}.sha256" | tr -d '\n' | sed "s|$|  ${TARBALL}|" | sha256sum -c -
tar -xf "${TARBALL}"
"nix-${NIX_VERSION}-$(uname -m)-linux/install" --daemon
```

x86_64-linux における sha256 は
`c3fe29778acaa93b5095ee66e36f11ec7c6a284c40970a24cc83ac4f04809db3` である。

flakes を有効化する (`~/.config/nix/nix.conf` または `/etc/nix/nix.conf`)。

```
experimental-features = nix-command flakes
```

## セットアップ

```bash
git clone https://github.com/sabas0ba/dotfiles.git ~/repos/dotfiles
cd ~/repos/dotfiles

# 環境に入る (flake.lock を同梱しているため、どの環境でも同一の内容となる)
nix develop
scripts/check-env.sh   # 構成の確認
```

### direnv のセットアップ

`cd` により環境に入り、ディレクトリを離れると元に戻る。

```bash
# シェルに direnv のフックを追加する (bash の例)
echo 'eval "$(direnv hook bash)"' >> ~/.bashrc

# nix-direnv を有効化する (flake の評価結果をキャッシュする)
mkdir -p ~/.config/direnv
echo 'source $HOME/.nix-profile/share/nix-direnv/direnvrc' >> ~/.config/direnv/direnvrc

# 本リポジトリの .envrc を許可する
cd ~/repos/dotfiles
direnv allow
```

マシン固有の設定は `.envrc.local` に置く。git 管理外であり、`.envrc` から読み込まれる。

## 操作

```bash
make help          # 利用可能な操作の一覧
make check         # すべての検査 (整形・静的解析・環境のスモークテスト)
make fmt           # Nix およびシェルスクリプトの整形
make lint          # 静的解析のみ
make shell         # 開発シェルに入る (direnv 未使用時)
```

作業は開発シェルの内部で行う。環境変数 `DOTFILES_ENV` が `nix-develop` であれば
開発シェル内である。`scripts/check-env.sh` で確認できる。

ツールを開発シェルの外から導入しない。`apt install` / `brew install` /
`npm install -g` / `pip install --user` 等は再現性を損なう。必要なツールは
`nix/packages.nix` に追記して取得する。

## ホームディレクトリの構成

ホームディレクトリの内容は home-manager で宣言的に管理する。設定は
[`nix/home.nix`](nix/home.nix) に定義し、適用対象 (ユーザー名とホームディレクトリ) は
`flake.nix` の `homeTargets` に定義する。

管理対象は 2 種類ある。

- 設定の生成: `programs.git` 等。git の user/email もここで設定する
- 生ファイルの配置: `home/` 以下がホームディレクトリの構造に対応する
  (例: `home/.claude/CLAUDE.md` は `~/.claude/CLAUDE.md` に配置される)

既存ファイルを置き換える可能性があるため、必ず先に配置内容を確認する。

```bash
make hm-build   # 構成の構築のみ (ホームディレクトリは変更しない)
make hm-dry     # 配置内容の確認 (実際には配置しない)
make hm-switch  # 配置の実行
```

`HM_TARGET` は既定で実行中のユーザー名 (`id -un`) を使用する。したがって環境ごとに
指定する必要はない。明示する場合は `make hm-switch HM_TARGET=<name>` とする。マシンを
追加する場合は `flake.nix` の `homeTargets` にユーザー名と一致する名前で追記する。

ホームディレクトリはユーザー名と `system` から導出する (linux は `/home/<name>`、
darwin は `/Users/<name>`)。規則から外れる対象のみ `homeDirectory` を明示する。
したがってマシンを追加する場合、通常はユーザー名と `system` の指定だけで足りる。

現在定義してある対象は以下のとおり。

| 対象 | ホームディレクトリ | 用途 |
| --- | --- | --- |
| `sabas0ba` | `/home/sabas0ba` (導出) | 個人環境 |
| `root` | `/root` (明示) | Claude Code のリモート実行環境 (root で動作する) |

Claude Code のリモート実行環境では、`~/.gitconfig` をセッション側が管理しており、
コミット署名やプロキシ経由の URL 書き換えが設定されている。home-manager が生成するのは
`~/.config/git/config` であるためファイルの衝突は起きないが、git は `~/.gitconfig` を
後に読むため、user の設定は当該環境ではセッション側が優先される。

`home/.claude` は `recursive = true` で配置しており、ディレクトリ自体ではなく配下の
ファイルを個別に symlink する。`~/.claude` に home-manager の管理外のファイルが
存在する場合でも、それらを置き換えない。

## コンテナ環境

ホストと同一の環境をコンテナ内に構築する。Dockerfile はツールの一覧を持たず、本
リポジトリの `flake.nix` を評価するため、内容はホストと一致する。

```bash
make docker-build   # イメージの構築
make docker-shell   # コンテナ内の開発シェルに入る (カレントディレクトリをマウント)
make docker-check   # コンテナ内でのスモークテスト
```

直接実行する場合:

```bash
docker build -t dotfiles-dev .
docker run --rm -it -v "$PWD:/workspace" dotfiles-dev
docker run --rm -v "$PWD:/workspace" dotfiles-dev scripts/check-env.sh
```

ビルド時に開発シェルを Nix の profile として実体化しているため、起動は約 1 秒であり、
ネットワークを必要としない。イメージは nixpkgs のソースを含むため、`--network none`
のまま `make check` (`nix flake check`) が実行できる。

コンテナ内では名前 `nixpkgs` も `flake.lock` で固定した nixpkgs に解決される。以下は
ネットワーク無しで動作し、開発シェルと同一の nixpkgs を参照する。

```bash
nix shell nixpkgs#jq
```

## CI

`.github/workflows/ci.yml` で、イメージを構築し、`--network none` のコンテナ内で
`make check` を実行する。CI 環境をホストおよびコンテナと別の環境にしないため、検査は
コンテナ内で行う。

## 開発

### ツールを追加する

1. `nix/packages.nix` にパッケージ名を追記する (グループのコメントに従って配置する)
2. コマンドとして使用するものは `scripts/check-env.sh` の `required_commands` にも
   追記する
3. `make check` が成功することを確認する

`Dockerfile` にツール名を追記しない。定義が重複し、不整合が生じるため。

### ホームディレクトリの構成を変更する

宣言的に書ける設定は `nix/home.nix` に記述する。生ファイルとして配置するものは
`home/` 以下に、ホームディレクトリからの相対パスで置く。手順は
[ホームディレクトリの構成](#ホームディレクトリの構成) を参照する。

### nixpkgs を更新する

`flake.nix` の `nixpkgs.url` はブランチ名ではなく 40 桁の rev で固定してある。更新は
以下のコマンドで行い、`flake.nix` と `flake.lock` を同一のコミットに含める。

```bash
make bump REV=$(curl -sL https://channels.nixos.org/nixos-26.05/git-revision)
make check
```

nixpkgs の更新は独立したコミットとし、他の変更と混在させない。

### ベースイメージを更新する

`Dockerfile` の `NIX_VERSION` と `NIX_IMAGE_DIGEST` を同時に変更する。ダイジェストは
`docker buildx imagetools inspect nixos/nix:<version>` で取得する。

### Dockerfile を変更する

コンテナはホストと同一の環境である必要がある。イメージの内容を変更する場合、変更先は
`nix/packages.nix` である。Dockerfile を直接変更してよいのは、レイヤ構成、ベース
イメージの固定、entrypoint の挙動を変更する場合に限る。

### コーディング規約

- Nix: `nixfmt` (RFC 166 スタイル) で整形する。`statix` および `deadnix` の指摘を
  残さない
- シェル: bash または POSIX sh。先頭に `set -euo pipefail` (sh では `set -eu`) を
  記述する。`shellcheck` を通し、`shfmt --indent 2 --case-indent` で整形する
- コメント: 実装内容ではなく、その選択の理由を記述する。既存ファイルに合わせて
  日本語で記述する
- 整形は手作業ではなく `make fmt` で行う

### コミット

- Conventional Commits (`feat:` / `fix:` / `chore:` / `docs:` / `refactor:` / `ci:`)
- 1 コミット 1 目的とする。環境の更新と dotfiles の変更を混在させない
- コミット前に `make check` を実行する

### 検証

以下が成功することを必須とする。

```bash
make check
```

`Dockerfile` または `nix/` を変更した場合は、コンテナ側も検証する。

```bash
make docker-check
```

### 禁止事項

- 秘密情報 (トークン、鍵、社内ホスト名) のコミット。マシン固有の設定は `.envrc.local`
  (git 管理外) に置く
- `flake.lock` の削除、`.gitignore` への追加、および検査を通過させるための検査自体の
  削除
- 開発シェルの外部でのツール導入
- 一時ファイルをリポジトリ外部 (`/tmp` 等) に作成すること。`.work/` を使用する

## 再現性

外部の成果物はすべて一意に固定する。タグやブランチ名のみによる参照は固定とみなさない。

| 対象 | 固定方法 | 定義箇所 |
| --- | --- | --- |
| nixpkgs | 40 桁の rev + `flake.lock` の narHash | `flake.nix` |
| home-manager | 40 桁の rev + `flake.lock` の narHash | `flake.nix` |
| ツール一式 | 上記 nixpkgs から解決 | `nix/packages.nix` |
| ベースイメージ | タグ + ダイジェスト (`@sha256:...`) | `Dockerfile` |
| GitHub Actions | コミット SHA | `.github/workflows/ci.yml` |
| ロケール | `LC_ALL=C.UTF-8` | `nix/devshell.nix` |

`flake.lock` は再現性の要件であるため必ずコミットする。存在しない場合は `make lock`
で生成する。

## 構成

```
flake.nix                入力 (nixpkgs の rev 固定) と出力の定義
flake.lock               入力の解決結果
nix/packages.nix         ツールの一覧 (単一情報源)
nix/devshell.nix         開発シェルの定義
nix/checks.nix           nix flake check が実行する検査
nix/home.nix             home-manager によるホームディレクトリの構成
.envrc                   direnv の設定
Dockerfile               同一の flake からコンテナを構築する
Makefile                 操作の入り口
scripts/                 ヘルパースクリプト
home/                    ホームディレクトリへ配置する生ファイル
.github/workflows/ci.yml CI 定義
CLAUDE.md                Claude Code 向けの補足
.work/                   作業用の一時ファイル置き場 (git ignore 対象)
```
