# dotfiles

Nix と direnv で閉じた、再現性のある開発環境。同じ定義からコンテナイメージも作れる。

環境に入っているツールの一覧は [`nix/packages.nix`](nix/packages.nix) の 1 か所だけで
定義していて、ホストの開発シェル・`nix build` の profile・Docker イメージの
3 つすべてがそこを参照する。したがって「手元とコンテナで入っているものが違う」
という状態が原理的に起きない。

## 必要なもの

- [Nix](https://nixos.org/download/) (flakes を有効にすること)
- [direnv](https://direnv.net/) (任意。あると `cd` するだけで環境に入れる)
- Docker (任意。コンテナ環境を使う場合のみ)

Nix のインストール:

```bash
curl -L https://nixos.org/nix/install | sh -s -- --daemon
```

flakes を有効にする (`~/.config/nix/nix.conf` か `/etc/nix/nix.conf`):

```
experimental-features = nix-command flakes
```

## セットアップ

```bash
git clone https://github.com/sabas0ba/dotfiles.git
cd dotfiles

# 環境に入る (flake.lock は同梱済みなので、誰の手元でも同じものが入る)
nix develop
scripts/check-env.sh   # 揃っているか確認
```

### direnv のセットアップ (推奨)

`cd` しただけで環境に入り、抜けると元に戻るようになる。

```bash
# シェルに direnv のフックを入れる (bash の例。zsh なら zshrc に zsh 用の行を)
echo 'eval "$(direnv hook bash)"' >> ~/.bashrc

# nix-direnv を有効にする (flake の評価結果をキャッシュして cd を速くする)
mkdir -p ~/.config/direnv
echo 'source $HOME/.nix-profile/share/nix-direnv/direnvrc' >> ~/.config/direnv/direnvrc

# このリポジトリの .envrc を許可する
cd /path/to/dotfiles
direnv allow
```

マシン固有の設定 (トークンなど) は `.envrc.local` に置く。git 管理外で、
`.envrc` から自動で読み込まれる。

## 使い方

```bash
make help          # 使えるコマンドの一覧
make check         # 検査ぜんぶ (整形・lint・環境のスモークテスト)
make fmt           # Nix とシェルスクリプトを整形
make lint          # 静的解析だけ
make shell         # 開発シェルに入る (direnv を使わない場合)
```

## コンテナで使う

ホストと同じ環境をコンテナの中に作る。Dockerfile はツール一覧を持たず、
この repo の `flake.nix` をそのまま評価するので、中身は必ずホストと一致する。

```bash
make docker-build   # イメージをビルド
make docker-shell   # 中の開発シェルに入る (カレントディレクトリをマウント)
make docker-check   # 中でスモークテストを走らせる
```

直接叩く場合:

```bash
docker build -t dotfiles-dev .
docker run --rm -it -v "$PWD:/workspace" dotfiles-dev
docker run --rm -v "$PWD:/workspace" dotfiles-dev scripts/check-env.sh
```

ビルド時に開発シェルを Nix の profile として実体化しているので、起動は速く
(1 秒程度)、ネットワークが無くても中に入れる。イメージは nixpkgs のソースごと
抱えているため、`--network none` のまま `make check` (= `nix flake check`) まで通る。

コンテナの中では `nixpkgs` という名前も、この repo が `flake.lock` で固定した
nixpkgs に向けてある。したがって次もオフラインで動き、開発シェルと同じ nixpkgs
から解決される。

```bash
nix shell nixpkgs#jq
```

## 再現性について

固定しているもの:

| 対象 | 固定方法 |
| --- | --- |
| nixpkgs | `flake.nix` の `nixpkgs.url` に 40 桁の rev を直書き + `flake.lock` |
| ツール一式 | `nix/packages.nix` (上の nixpkgs から解決) |
| ベースイメージ | `Dockerfile` の `ARG NIX_VERSION` |
| ロケール | 開発シェルで `LC_ALL=C.UTF-8` |

nixpkgs を更新するとき:

```bash
make bump REV=$(curl -sL https://channels.nixos.org/nixos-26.05/git-revision)
make check
git add flake.nix flake.lock && git commit -m "chore: bump nixpkgs"
```

## 構成

```
flake.nix              入力 (nixpkgs の rev 固定) と出力の定義
nix/packages.nix       ツールの一覧 (単一情報源)
nix/devshell.nix       開発シェルの形
nix/checks.nix         nix flake check が走らせる検査
.envrc                 direnv の設定
Dockerfile             同じ flake からコンテナを作る
Makefile               操作の入り口
scripts/               ヘルパースクリプト
CLAUDE.md              Claude Code 向けの作業指示
```
