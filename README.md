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

Windows 上で使用する場合は、先に [Windows (WSL)](#windows-wsl) の手順で WSL 内に Linux 環境を構築する。以降の手順はその内部で実行する。

### Nix の導入

配布物をバージョン固定で取得し、チェックサムを検証してから展開する。インストーラを
検証せずに直接実行する方式 (`curl ... | sh`) は用いない。

チェックサムは本文に固定した値を使用する。配布元から取得した値との照合は、配布元が
差し替えられた場合に同時に差し替わるため、検証にならない。

```bash
NIX_VERSION=2.35.1
NIX_SHA256=c3fe29778acaa93b5095ee66e36f11ec7c6a284c40970a24cc83ac4f04809db3
TARBALL="nix-${NIX_VERSION}-x86_64-linux.tar.xz"

curl -LO "https://releases.nixos.org/nix/nix-${NIX_VERSION}/${TARBALL}"
echo "${NIX_SHA256}  ${TARBALL}" | sha256sum -c -
tar -xf "${TARBALL}"
"nix-${NIX_VERSION}-x86_64-linux/install" --daemon
```

上記の sha256 は x86_64-linux の配布物に対する値である。他のアーキテクチャで導入する
場合は、対応する配布物の sha256 を確認したうえで置き換える。`NIX_VERSION` は
`Dockerfile` の `ARG NIX_VERSION` と一致させる。

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

## Windows (WSL)

Windows 上では WSL の内部に Linux 環境を構築し、その中で上記のセットアップを行う。経路は 2 つあり、いずれも配布イメージをバージョンと sha256 で固定して取得する。

| 経路 | system の管理 | flake の入力 | Nix の導入 |
| --- | --- | --- | --- |
| NixOS-WSL | `nix/wsl.nix` により宣言的 | `nixos-wsl` を使用 | 不要 (イメージに含まれる) |
| Ubuntu LTS | 宣言的でない | 使用しない | [Nix の導入](#nix-の導入) の手順による |

前者は system 層まで本リポジトリの管理下に入る。後者は入力を増やさずに済むが、WSL の設定は手作業の結果として残る。いずれの経路でも、開発シェル (`nix develop`) とホームディレクトリの構成 (`make hm-switch`) は他の環境と完全に同一の手順となる。

WSL 本体は 2.4.4 以降が必要である (`.wsl` 形式を直接登録できる版)。`wsl --version` で確認し、古い場合は `wsl --update` を実行する。WSL 自体が未導入の場合は `wsl --install --no-distribution` で有効化する。

### Windows 側からの隔離

登録した環境は、既定の WSL とは異なり Windows 側から隔離した状態にする。

- Windows のドライブを `/mnt` 以下にマウントしない
- Windows の PATH を流入させない
- Windows の実行ファイルを起動できるようにしない

目的は、当環境で動作するエージェントやスクリプトが、ホスト側のシステムファイルや、認証済みの CLI (gh / az / aws / gcloud 等) に到達しないようにすることである。規約による禁止ではなく到達経路の遮断によって担保する。

設定の実体は経路ごとに異なる。NixOS では [`nix/wsl.nix`](nix/wsl.nix) の `wsl.wslConf` および `wsl.interop` が宣言的に生成する。Ubuntu では `scripts/wsl-bootstrap.ps1` が登録の直後に `/etc/wsl.conf` を配置する。いずれの経路でも満たすべき結果は [`scripts/check-wsl-isolation.sh`](scripts/check-wsl-isolation.sh) が定義し、`make check` に含まれる。

隔離を解除する場合は、手元の `/etc/wsl.conf` を書き換えるのではなく、上記の定義を変更して commit する。NixOS では手元の変更は次の `make wsl-switch` で元に戻る。

Windows のファイルを WSL から扱う必要が生じた場合は、隔離を解除するのではなく、対象を明示して個別に持ち込む。

### 登録

PowerShell で実行する (管理者権限は不要)。イメージは `.work/wsl` に保存し、sha256 が一致する場合は再取得しない。中断した場合はそのまま再実行できる。

```powershell
git clone https://github.com/sabas0ba/dotfiles.git $HOME\repos\dotfiles
cd $HOME\repos\dotfiles

# NixOS-WSL の経路
powershell -ExecutionPolicy Bypass -File scripts\wsl-bootstrap.ps1 -Distro nixos

# Ubuntu の経路
powershell -ExecutionPolicy Bypass -File scripts\wsl-bootstrap.ps1 -Distro ubuntu
```

スクリプトは、取得、sha256 の照合、`wsl --install --from-file` による登録、`/etc/wsl.conf` の配置、反映のための停止までを行う。取得元と sha256 はスクリプト本文に固定してあり、配布元の隣に置かれたチェックサムファイルとは照合しない (配布物と同時に差し替えられるため検証にならない)。

登録に使用したイメージを破棄する場合は `.work/wsl` を削除する。環境そのものを作り直す場合は `wsl --unregister <名前>` を実行してから再度登録する。

### NixOS-WSL の経路

登録直後の既定ユーザーは `nixos` である。`flake.nix` の `homeTargets` に同名の対象を定義してあるため、以降 `HM_TARGET` を指定する必要はない。

```bash
wsl -d NixOS

# 配布イメージに git が含まれない場合がある。nix-shell 経由で取得する。
nix-shell -p git --run 'git clone https://github.com/sabas0ba/dotfiles.git ~/repos/dotfiles'
cd ~/repos/dotfiles

# 初回の rebuild を行う時点では本リポジトリの構成が未適用であり、flakes が有効に
# なっていない。この 1 回のみ NIX_CONFIG で補う。sudo は環境変数を引き継がないため
# env で与える (シェルで export しても root には渡らない)。
sudo env NIX_CONFIG='experimental-features = nix-command flakes' \
  nixos-rebuild dry-activate --flake '.#wsl'   # 適用内容の確認

sudo env NIX_CONFIG='experimental-features = nix-command flakes' \
  nixos-rebuild switch --flake '.#wsl'         # system の構成を適用する
```

2 回目以降は構成側で flakes が有効になっているため、`make wsl-dry` および
`make wsl-switch` を使う。sudo はパスワードを要求しない (NixOS-WSL が既定ユーザーに
対し `security.sudo.wheelNeedsPassword = false` を設定している)。

適用後、`/etc/wsl.conf` の反映のために一度停止する。Windows 側で実行する。

```powershell
wsl --shutdown
```

以降は他の Linux 環境と同一である。

```bash
wsl -d NixOS
cd ~/repos/dotfiles
nix develop
make check        # 開発環境と WSL の隔離を検査する
make hm-dry       # ホームディレクトリへの配置内容の確認
make hm-switch
```

### Ubuntu の経路

登録直後の既定ユーザーは root である。`homeTargets` の対象を NixOS の経路と揃えるため、ユーザー `nixos` を作成する。

```bash
wsl -d Ubuntu-24.04

# パスワードを設定する。sudo が要求するため --disabled-password では作成しない。
adduser nixos
usermod -aG sudo nixos

# bootstrap が配置した隔離の設定に、既定ユーザーの指定を追記する。
printf '[user]\ndefault = nixos\n' >> /etc/wsl.conf
```

Windows 側で `wsl --terminate Ubuntu-24.04` を実行して反映させたのち、[Nix の導入](#nix-の導入) と [セットアップ](#セットアップ) の手順に進む。`/etc/wsl.conf` の隔離の設定は既に配置されているため、変更しない。

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
| `nixos` | `/home/nixos` (導出) | WSL 上の環境 ([Windows (WSL)](#windows-wsl) を参照) |
| `root` | `/root` (明示) | Claude Code のリモート実行環境 (root で動作する) |

`nixos` は NixOS-WSL の `wsl.defaultUser` の既定値である。改名すると初回の `nixos-rebuild` が完了するまで対象が存在しないことになるため、既定値のまま受け入れている。Ubuntu の経路でも同名で作成し、WSL 上の対象を 1 つに揃えている。

Claude Code のリモート実行環境では、`~/.gitconfig` をセッション側が管理しており、
コミット署名やプロキシ経由の URL 書き換えが設定されている。home-manager が生成するのは
`~/.config/git/config` であるためファイルの衝突は起きないが、git は `~/.gitconfig` を
後に読むため、user の設定は当該環境ではセッション側が優先される。

`home/.claude` は `recursive = true` で配置しており、ディレクトリ自体ではなく配下の
ファイルを個別に symlink する。`~/.claude` に home-manager の管理外のファイルが
存在する場合でも、それらを置き換えない。

`home/.claude/settings.json` は Claude Code の permission の既定値である。認証情報を含むファイルの読み出しと、認証済みの CLI の実行をそれぞれ deny / ask に置く。方針は `home/.claude/CLAUDE.md` の「実行環境と到達範囲」に記述してある。これは Claude Code がツールの実行前に行う検査であり、OS レベルの強制ではない。Bash から起動した子プロセスには及ばないため、WSL では[隔離](#windows-側からの隔離)を主たる担保とし、本設定はそれが使えない環境 (Windows ネイティブ、Linux ホスト) 向けの補助と位置付ける。

配置されたファイルは Nix store への symlink であり書き込めない。プロジェクト側で緩める場合は当該リポジトリの `.claude/settings.json` を用いる (プロジェクトの設定が利用者全体の設定より優先される)。

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
コンテナ内で行う。push (main) と pull request で自動実行する。

`.github/workflows/update-pins.yml` は固定の更新と PR の作成を行う。手動実行のみで、
定期実行はしない。詳細は [開発](#ci-から更新して-pr-を作成する) を参照する。

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

nixpkgs の更新は独立したコミットとし、他の変更と混在させない。`flake.lock` の
再生成を忘れた場合は `make check` が失敗する ([再現性](#再現性) を参照)。

### home-manager を更新する

nixpkgs と同様に rev で固定してある。`release-26.05` の HEAD を指定する。

```bash
make bump-hm REV=<40 桁の rev>
make check
```

### NixOS-WSL を更新する

nixpkgs と同様に rev で固定してある。`release-26.05` 上のタグが指すコミット SHA を指定し、`flake.nix` のコメントのタグ名も併せて更新する。

```bash
make bump-wsl REV=<40 桁の rev>
make check
```

配布イメージ (`scripts/wsl-bootstrap.ps1`) とは別の固定である。両者は系列を揃えるが、前者は登録済みの環境には影響しない。

### ベースイメージ・Actions・インストーラを更新する

これらは `flake.lock` の再生成を伴わないため、`scripts/update-pins.sh` を直接呼ぶ。
対象と値の取得方法は `make bump-help` で一覧できる。

```bash
# ベースイメージ (docker buildx imagetools inspect nixos/nix:<バージョン> で取得)
scripts/update-pins.sh image 2.35.1 sha256:377d4887...

# GitHub Actions (対象タグが指すコミット SHA)
scripts/update-pins.sh action actions/checkout 11bd7190...

# Nix インストーラ (releases.nixos.org の .sha256)
scripts/update-pins.sh nix-installer 2.35.1 c3fe2977...

# WSL の配布イメージ
scripts/update-pins.sh wsl-image nixos 2605.7.2 https://.../nixos.wsl e7180ad5...
scripts/update-pins.sh wsl-image ubuntu 24.04.4 https://.../ubuntu-...wsl 9b2f7730...
```

WSL の配布イメージの値は以下から取得する。いずれも配布物と同じ場所に置かれたチェックサムファイルではないため、差し替えの検出になる。

- NixOS-WSL: GitHub の releases に置かれた `nixos.wsl` と、GitHub API が返す当該アセットのダイジェスト
- Ubuntu: Microsoft が配布する [`DistributionInfo.json`](https://raw.githubusercontent.com/microsoft/WSL/master/distributions/DistributionInfo.json) の `Amd64Url` (`Url` と `Sha256`)

上流の最新版を自動で取得して書き換えることはしない。更新は意図的な操作であり、値は
明示的に与える。与えた値は形式を検査したうえで書き込み、変更対象が見つからない場合は
失敗する (記述が変わったことに気付かないまま進むのを防ぐため)。

### CI から更新して PR を作成する

手元に環境が無い場合は、GitHub Actions の `Update pins` ワークフローを手動実行する
(Actions タブ、または `gh workflow run update-pins.yml`)。対象と値を入力すると、更新、
検証、PR の作成までを行う。定期実行はしない。更新は意図的な操作であるため。

ワークフローが行う手順は以下である。

1. `scripts/update-pins.sh` で値を書き換える
2. `flake.nix` を変更した場合は `flake.lock` を再生成する。イメージを構築する前に行う
   (両者が整合していないと nix が暗黙に再ロックするため)。ここで使う nix は
   `Dockerfile` が固定しているベースイメージから取る。ワークフローに版を書くと
   二重管理になるため
3. イメージを構築し、`--network none` のコンテナ内で `make check` を実行する。CI と
   同一の経路である
4. ブランチを作成し、PR を開く

PR の作成には外部 action を使用せず、ランナー同梱の `gh` と `GITHUB_TOKEN` を用いる。
外部 action を増やさないため。

`GITHUB_TOKEN` で作成した PR では他のワークフローが起動しない (GitHub の仕様)。その
PR に CI のチェックは付かないため、上記 3 の結果を PR 本文に記載している。CI を回す
必要がある場合は、close して reopen するか、ブランチに空でないコミットを push する。

ベースイメージを更新した場合は、README の `NIX_VERSION` も一致させる。不一致は
`make check` が検出する。

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
| NixOS-WSL | 40 桁の rev + `flake.lock` の narHash | `flake.nix` |
| WSL の配布イメージ | バージョン + URL + sha256 | `scripts/wsl-bootstrap.ps1` |
| ツール一式 | 上記 nixpkgs から解決 | `nix/packages.nix` |
| ベースイメージ | タグ + ダイジェスト (`@sha256:...`) | `Dockerfile` |
| GitHub Actions | コミット SHA | `.github/workflows/ci.yml` |
| CI ランナー | バージョン付きラベル (`ubuntu-24.04`) | `.github/workflows/ci.yml` |
| Nix インストーラ | バージョン + sha256 | `README.md` |
| ロケール | `LC_ALL=C.UTF-8` | `nix/devshell.nix` |

`flake.lock` は再現性の要件であるため必ずコミットする。存在しない場合は `make lock`
で生成する。

`flake.nix` と `flake.lock` の整合は `scripts/check-lock.sh` が検査する (`make check`
および CI に含まれる)。ネットワークを使用せず、両ファイルの内容のみを照合する。

nix 自身が検出するのは、lock の再生成が必要になる乖離 (rev の不一致等) に限られる。
この場合 nix は入力の再取得を試みるため、失敗はネットワークのエラーとして現れ、原因が
lock の古さであることが分からない。一方、**入力がブランチ名で参照されている場合、nix は
これを正常として扱う**。lock には rev が記録されるため評価は再現するが、`flake.nix` の
記述は固定になっておらず、lock を再生成した時点で追従先が変わる。本検査はこの双方を、
オフラインかつ原因の分かる形で検出する。

検査する内容は以下である。

- `flake.nix` の入力がすべて 40 桁の rev で指定されていること
- その rev が `flake.lock` に同一の値で記録されていること
- `flake.lock` の各ノードが narHash を持ち、一意に固定されていること
- `flake.nix` から削除された入力が `flake.lock` に取り残されていないこと

flake 以外の参照は `scripts/check-pins.sh` が検査する。こちらもネットワークを使用せず、
作業木の内容のみを見る。

- `Dockerfile` の `FROM` がダイジェストで固定されていること (`ARG` 経由の参照も展開して
  判定する。既定値を持たない `ARG` はビルド時に差し替え可能なため固定とみなさない)
- ワークフローの `uses` がコミット SHA で固定されていること
- ワークフローの `runs-on` が `-latest` でないこと
- README の `NIX_VERSION` が `Dockerfile` の `ARG NIX_VERSION` と一致すること
- README に固定した `NIX_SHA256` があり、配布元から取得した値との照合になっていないこと
- `scripts/wsl-bootstrap.ps1` の配布イメージが https の URL と 64 桁の sha256 で固定されており、こちらも配布元から取得した値との照合になっていないこと

いずれも「上流に新しい版があるか」は見ない。それは更新の判断であり、検査の対象では
ないため。更新の手順は [開発](#開発) にある。

## 構成

```
flake.nix                入力 (nixpkgs の rev 固定) と出力の定義
flake.lock               入力の解決結果
nix/packages.nix         ツールの一覧 (単一情報源)
nix/devshell.nix         開発シェルの定義
nix/checks.nix           nix flake check が実行する検査
nix/home.nix             home-manager によるホームディレクトリの構成
nix/wsl.nix              WSL 上の NixOS の system 構成 (Windows 側からの隔離を含む)
.envrc                   direnv の設定
Dockerfile               同一の flake からコンテナを構築する
Makefile                 操作の入り口
scripts/                 ヘルパースクリプト
home/                    ホームディレクトリへ配置する生ファイル
.github/workflows/ci.yml CI 定義
CLAUDE.md                Claude Code 向けの補足
.work/                   作業用の一時ファイル置き場 (git ignore 対象)
```
