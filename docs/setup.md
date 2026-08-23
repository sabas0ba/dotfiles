# セットアップ

Linux および macOS 向けの手順である。Windows では先に [Windows (WSL)](windows.md) で WSL 内に環境を作り、その中で本手順を行う (NixOS 経路では bootstrap がここまで自動で行う)。

## 前提

- [Nix](https://nixos.org/download/) — flakes を有効化すること
- [direnv](https://direnv.net/) — 任意。導入すると `cd` だけで環境に入る
- Docker — 任意。コンテナ環境を使う場合のみ

## Nix の導入

配布物をバージョン固定で取得し、チェックサムを検証してから展開する。`curl ... | sh` のようにインストーラを検証せず実行する方式は用いない。

チェックサムは以下に固定した値を使う。配布元から取得した値との照合は、配布元が差し替えられれば同時に差し替わるため検証にならない。

```bash
NIX_VERSION=2.35.1
NIX_SHA256=c3fe29778acaa93b5095ee66e36f11ec7c6a284c40970a24cc83ac4f04809db3
TARBALL="nix-${NIX_VERSION}-x86_64-linux.tar.xz"

curl -LO "https://releases.nixos.org/nix/nix-${NIX_VERSION}/${TARBALL}"
echo "${NIX_SHA256}  ${TARBALL}" | sha256sum -c -
tar -xf "${TARBALL}"
"nix-${NIX_VERSION}-x86_64-linux/install" --daemon
```

上記の sha256 は x86_64-linux 向けの値である。他のアーキテクチャでは対応する配布物の sha256 に置き換える。

続いて flakes を有効化する (`~/.config/nix/nix.conf` または `/etc/nix/nix.conf`)。

```
experimental-features = nix-command flakes
```

## 環境に入る

```bash
git clone https://github.com/sabas0ba/dotfiles.git ~/repos/dotfiles
cd ~/repos/dotfiles

nix develop
scripts/check-env.sh
```

`flake.lock` を同梱しているため、どの環境でも同じ内容の開発シェルになる。

## direnv

導入すると `cd` で環境に入り、ディレクトリを離れると元に戻る。

```bash
# シェルにフックを追加する (bash の例)
echo 'eval "$(direnv hook bash)"' >> ~/.bashrc

# nix-direnv を有効化する (flake の評価結果をキャッシュする)
mkdir -p ~/.config/direnv
echo 'source $HOME/.nix-profile/share/nix-direnv/direnvrc' >> ~/.config/direnv/direnvrc

cd ~/repos/dotfiles
direnv allow
```

マシン固有の設定は `.envrc.local` に置く。git 管理外で、`.envrc` から読み込まれる。

## Claude Code のクラウド環境

[Claude Code](https://claude.ai/code) のリモート実行環境では、セッションごとに Nix を持たない Ubuntu のコンテナが用意される。`.claude/settings.json` の SessionStart フックが `scripts/cloud-setup.sh` を呼び、本ページと同じ手順で環境を構成するため、手動の操作は要らない。

- Nix の導入 — 版と sha256 は `scripts/nix-pin.sh` で定義し、WSL の Ubuntu 経路と共有する。systemd が無いため単一利用者の方式で入れる
- 開発シェルの実体化 — `nix develop` の結果を profile として置く (`Dockerfile` と同じ処理)
- 環境の引き渡し — 開発シェルの `PATH` と `DOTFILES_ENV` をセッションに渡す。以降のコマンドは `nix develop` を経由せず開発シェルと同一のツールで動く

コンテナの状態は保存されるため、2 回目以降の開始は速い。フックは `CLAUDE_CODE_REMOTE=true` の環境でのみ動作する。

### 環境に指定する設定

環境セレクタ (claude.ai/code の入力欄の上にある雲のアイコン) から作成・変更する。

| 項目 | 指定 |
| --- | --- |
| Network access | Trusted (既定)。変更しない |
| Environment variables | 不要 |
| Setup script | 不要 |

Trusted の許可リストには `*.nixos.org` が含まれ、フックが必要とする `releases.nixos.org` (Nix 本体) と `cache.nixos.org` (依存のバイナリ) が共に通る。None ではフックが Nix を取得できず、開発シェルの無いセッションになる。Custom では上記の 2 つを許可する。

以上は本リポジトリを開いたセッションに対するものである。フックは本リポジトリにあるため、他のリポジトリのセッションでは動作しない。その場合は[他のリポジトリで使う](#他のリポジトリで使う)。

### 到達範囲の制限

GitHub への要求はネットワークの設定とは別の proxy を通り、セッションに紐付いたリポジトリだけに制限される。`github:` 形式の flake の入力は、紐付いていなければ取得できない (403)。Network access を Full にしても変わらない。

- `nixpkgs` — 403 となるが `cache.nixos.org` から substitute できるため影響しない
- `home-manager`、`NixOS-WSL` — substitute できない。`nix flake check` と `make hm-switch` はここで失敗する

取得を伴わない検査は実行できる。

```bash
scripts/check-env.sh                             # 環境のスモークテスト
nix build --no-link .#checks.x86_64-linux.pins   # 個別の検査
```

すべての検査 (`make check`) は CI がコンテナ内で行う。イメージは構築時に入力をすべて取り込んでおり、`--network none` で完結する。

### 他のリポジトリで使う

本リポジトリ以外の開発で本環境を使う場合は、クラウド環境の Setup script に以下を書く。フックは本リポジトリにしか無いため、環境の側から入れる。

```bash
#!/bin/bash
set -euo pipefail

git clone --depth 1 https://github.com/sabas0ba/dotfiles /opt/dotfiles

# 版を固定する場合は --depth 1 を外し、以下を続ける。
#   git -C /opt/dotfiles checkout <40 桁のリビジョン>

/opt/dotfiles/scripts/cloud-setup.sh --setup-script --disposable
```

`--disposable` は、実行先が使い捨ての環境であることの明示である。本経路は `/usr/local/bin` と `$HOME` を書き換えるため、指定が無ければ実行しない。フックと違い Setup script は Claude Code の起動より前に走るため `CLAUDE_CODE_REMOTE` を持たず、コンテナであることを示す印 (`/.dockerenv`、`/run/.containerenv`、`/proc/1/cgroup`) も当該環境には無い。環境から判定できないため引数で明示する。

本リポジトリは public であり、セッションに紐付いていなくても clone できる (tarball は 403 だが git 経由は通る)。

ここでは本リポジトリを固定しない。常に最新を使う運用であり、[再現性](reproducibility.md)における唯一の例外である。使用したリビジョンは `--setup-script` が最初に出力する。後から見る場合は clone を直接見る。

```bash
git -C /opt/dotfiles log -1 --format='%H %cs %s'
```

`--setup-script` は、環境変数を引き渡す代わりに実体を配置する。

| 処理 | フック | Setup script |
| --- | --- | --- |
| Nix の導入 | 行う | 行う |
| 開発シェルの実体化 | 行う | 行う |
| 環境の引き渡し | `$CLAUDE_ENV_FILE` へ書く | 行わない |
| ツールの配置 | 行わない | `/usr/local/bin` へ symlink する |
| ホームの構成の配置 | 行わない | `home/` 以下を `$HOME` へ置く |

Setup script には `CLAUDE_ENV_FILE` が無く、セッションのシェルは `/etc/profile` を読まないため、環境変数では渡せない。既に PATH にある `/usr/local/bin` へ、`nix build .#default` の profile (中身は `nix/packages.nix`) と `nix` 自身を置く。

- system の同名のコマンド (`git`、coreutils 等) は Nix 版に置き換わる。覆ったものは実行時に列挙する
- 言語のツールチェーン (Node、Python 等) は含まない。クラウド環境が持つものを使う
- ホームの構成は home-manager を経由しない (前節のとおり取得できないため)。置く内容は同一で、既存のファイルは上書きする。内容が異なるものは初回に `<ファイル名>.dotfiles-backup` へ退避する
- 初回は数分かかる。Setup script の目安 (5 分) を超えると環境のキャッシュが作られない

---

[目次に戻る](index.md)
