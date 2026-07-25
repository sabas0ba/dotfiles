# dotfiles

Nix と direnv による再現性のある開発環境、および同一の定義から構築するコンテナ環境。

環境に含まれるツールの一覧は [`nix/packages.nix`](nix/packages.nix) の 1 か所のみで
定義し、ホストの開発シェル、`nix build` の profile、Docker イメージの 3 つすべてが
これを参照する。したがってホストとコンテナで内容が乖離しない。

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

## dotfiles の配置

`home/` 以下がホームディレクトリの構造に対応する (例: `home/.claude/CLAUDE.md` は
`~/.claude/CLAUDE.md` に配置される)。配置には GNU stow を使用する。

既存ファイルを置き換える可能性があるため、必ず先に配置内容を確認する。

```bash
make stow-dry   # 配置内容の確認 (実際には配置しない)
make stow       # 配置の実行
```

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

## 再現性

外部の成果物はすべて一意に固定する。

| 対象 | 固定方法 | 定義箇所 |
| --- | --- | --- |
| nixpkgs | 40 桁の rev + `flake.lock` の narHash | `flake.nix` |
| ツール一式 | 上記 nixpkgs から解決 | `nix/packages.nix` |
| ベースイメージ | タグ + ダイジェスト (`@sha256:...`) | `Dockerfile` |
| GitHub Actions | コミット SHA | `.github/workflows/ci.yml` |
| ロケール | `LC_ALL=C.UTF-8` | `nix/devshell.nix` |

nixpkgs を更新する場合:

```bash
make bump REV=$(curl -sL https://channels.nixos.org/nixos-26.05/git-revision)
make check
git add flake.nix flake.lock && git commit -m "chore: bump nixpkgs"
```

ベースイメージを更新する場合は、`Dockerfile` の `NIX_VERSION` と `NIX_IMAGE_DIGEST`
を同時に変更する。ダイジェストは
`docker buildx imagetools inspect nixos/nix:<version>` で取得する。

## 構成

```
flake.nix                入力 (nixpkgs の rev 固定) と出力の定義
flake.lock               入力の解決結果
nix/packages.nix         ツールの一覧 (単一情報源)
nix/devshell.nix         開発シェルの定義
nix/checks.nix           nix flake check が実行する検査
.envrc                   direnv の設定
Dockerfile               同一の flake からコンテナを構築する
Makefile                 操作の入り口
scripts/                 ヘルパースクリプト
home/                    ホームディレクトリへ配置する dotfiles (stow パッケージ)
.github/workflows/ci.yml CI 定義
CLAUDE.md                Claude Code に対する本リポジトリ固有の指示
```
