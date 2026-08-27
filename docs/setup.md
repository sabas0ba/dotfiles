# セットアップ

Nix が導入済みであれば、[対応する開発シェルの system](index.md#対応範囲) で本ページの「環境に入る」以降を使用できる。Windows では先に [Windows (WSL)](windows.md) で WSL 内に環境を作る (NixOS 経路では bootstrap がここまで自動で行う)。

## 前提

- [Nix](https://nixos.org/download/) — flakes を有効化すること
- [direnv](https://direnv.net/) — 任意。導入すると `cd` だけで環境に入る
- Docker — 任意。コンテナ環境を使う場合のみ

## Nix の導入

以下は `x86_64-linux` 専用の固定済み手順である。macOS (`x86_64-darwin` / `aarch64-darwin`) および `aarch64-linux` では実行しない。それらの system では [Nix 公式の対象 system 向け導入手順](https://nixos.org/download/)で Nix を導入し、本ページの「環境に入る」へ進む。本リポジトリは、それらの system 向けインストーラと sha256 を固定していない。

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

tarball 名、インストーラのパス、checksum コマンドはいずれも system に依存する。ほかの system で上記の sha256 だけを置き換えても動作しない。機能ごとの対応状況は[対応範囲](index.md#対応範囲)にある。

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

`flake.lock` を同梱しているため、同じ system では同じ入力から開発シェルを構築する。開発シェルを出力する system は[対応範囲](index.md#対応範囲)にある。

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

この経路の対象 system は[対応範囲](index.md#対応範囲)にある。ほかの CPU architecture には固定済みの Nix 配布物がなく、`cloud-setup.sh` は取得前に停止する。

- Nix の導入 — 版と sha256 は `scripts/nix-pin.sh` で定義し、WSL の Ubuntu 経路と共有する。systemd が無いため単一利用者の方式で入れる
- 開発シェルの実体化 — `nix develop` の結果を profile として置く (`Dockerfile` と同じ処理)
- 環境の引き渡し — 開発シェルの `PATH` と `DOTFILES_ENV` をセッションに渡す。以降のコマンドは `nix develop` を経由せず開発シェルと同一のツールで動く
- 構成の記録 — 何を元にどう構成したかを `/var/log/dotfiles/cloud-setup.log` に残す ([構成の記録](#構成の記録))

コンテナの状態は保存されるため、2 回目以降の開始は速い。フックは `CLAUDE_CODE_REMOTE=true` の環境でのみ動作する。

### 環境に指定する設定

環境セレクタ (claude.ai/code の入力欄の上にある雲のアイコン) から作成・変更する。

| 項目 | 指定 |
| --- | --- |
| Network access | Trusted (既定)。変更しない |
| Environment variables | 不要。`nix/packages.nix` に無いツールを足す場合のみ `DOTFILES_EXTRA_PACKAGES` ([追加のパッケージを指定する](#追加のパッケージを指定する)) |
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

### 追加のパッケージを指定する

`nix/packages.nix` に無いツールを、当該セッションに限って足せる。作業対象のリポジトリが必要とする言語のツールチェーン (Python、Go 等) のように、開発環境そのものには入れない依存を想定している。

クラウド環境によっては、セットアップの完了後にネットワークが遮断される (ChatGPT Codex の既定がこれである)。遮断後は取得できないため、セットアップの実行中に store へ入れておく必要がある。指定はここで受ける。

| 経路 | 指定方法 |
| --- | --- |
| SessionStart フック | 環境変数 `DOTFILES_EXTRA_PACKAGES` |
| Setup script | 引数 `--extra-packages`、または環境変数 |

フックのコマンドは `.claude/settings.json` に固定されており引数を渡せないため、環境変数を使う。双方を与えた場合は併合する。

```bash
DOTFILES_EXTRA_PACKAGES="python3 gcc ripgrep"
```

```bash
/opt/dotfiles/scripts/cloud-setup.sh --setup-script --disposable \
  --extra-packages "python3 gcc"
```

値は [nixpkgs](https://search.nixos.org/packages) の attribute 名を空白区切りで並べたものである。`nixpkgs#python3` のような flakeref ではなく、`python3` のように名前だけを与える。

- nixpkgs のリビジョンは `flake.lock` が固定したものを使う。開発シェルと同一であり、store も共有する。registry の `nixpkgs` (固定されていない) は参照しない
- 配置先は `/nix/var/nix/profiles/dotfiles-extra` である。開発シェルの profile とは分けてあり、[単一情報源](development.md#ツールを追加する)である `nix/packages.nix` の内容には影響しない
- PATH では開発シェルのツールより前に置く。名前が重なった場合は追加した側が使われる
- profile は毎回、その時点の指定から作り直す。コンテナはセッションをまたいで保存されるため、指定から外したパッケージが残り続けると、開発シェルのコマンドを覆ったまま指定からは分からない状態になる。指定を外せば次のセッションで消える
- `scripts/check-env.sh` の検査対象ではない。当該スクリプトが見るのは `nix/packages.nix` のツールのみである
- 名前の誤りは実体化の時点で失敗する。他の構成は最後まで進めたうえで終了状態を失敗とするため、指定を直して再実行すればよい。誤った 1 つのために他のパッケージまで落とすことはしない
- バイナリキャッシュに無いものを指定するとソースからの構築となり、時間がかかる。Setup script の目安 (5 分) を超えると環境のキャッシュが作られない

対象はコマンドを提供するパッケージである。言語のライブラリ (`python3Packages.requests` 等) は指定しても動かない。profile に入るのは指定したパッケージ自身だけで、それが伝播する依存は揃わないため、`import` の時点で失敗する。

```
>>> import requests
  File ".../site-packages/requests/__init__.py", line 43, in <module>
    import urllib3
ModuleNotFoundError: No module named 'urllib3'
```

ライブラリを含む環境は `python3.withPackages` のような合成を要し、attribute 名の列挙では表せない。必要な場合は `nix/packages.nix` に式として書く。

恒久的に必要なツールはここではなく `nix/packages.nix` に追加する。手順は[ツールを追加する](development.md#ツールを追加する)にある。本節の指定は環境の設定にしか残らず、他の環境 (手元、Docker、CI) には反映されない。

### 構成の記録

`scripts/cloud-setup.sh` は、実行のたびに何を元にどう構成したかを `/var/log/dotfiles/cloud-setup.log` へ追記する。構成の出力はセッションの終了とともに失われ、コンテナも作り直されるため、後から確認する手段が他に無い。

```
=== 2026-08-26T10:59:57Z 開始
経路            hook
引数            (なし)
dotfiles        fc4cdec... 2026-08-26 Merge pull request #34 from ...
nix (固定)      2.35.1
追加パッケージ  hello cowsay
環境変数
  CLAUDE_CODE_REMOTE=true
  CLAUDE_ENV_FILE=/root/.claude/session-env/.../sessionstart-hook-0.sh
  CODEX_HOME=(未設定)
  DOTFILES_EXTRA_PACKAGES=hello cowsay
  HOME=/root
  USER=root
--- 2026-08-26T11:00:05Z 終了 (状態 0)
nix (実行)      nix (Nix) 2.35.1
nixpkgs         597283ad8aa0b331c788e97c4c262d58877074ef
追加パッケージ  実体化できなかったもの: (なし)
```

記録する環境変数は上記の名前に限る。`env` の全体を取って名前のパターン (`*TOKEN*` 等) で濾す方式は採らない。列挙にない名前を取りこぼした時点で秘密が漏れるためである。変数を足す場合は、値が秘密になりえないものに限る。

- 未コミットの変更がある場合、`dotfiles` の行に「(未コミットの変更あり)」が付く。開発シェルの評価対象は HEAD ではなく作業ツリーであり、リビジョンだけでは別の内容の環境が同じ記録になるためである。未追跡のファイルは対象に含めない (flake の評価は git の管理下にあるものだけを見るため、環境の内容を変えない)
- 入力は開始時に書き、結果は終了時に書く。終了時にまとめて 1 度で済ませると、途中で異常終了した場合に何も残らず、記録が最も要る場面で失われる
- 構成が失敗した場合も記録される。終了状態がそのまま残る
- 引数の誤り、リモート実行環境でない場合、`--disposable` の欠落では記録しない。いずれも何も構成せずに終わるため、記録する対象が無い
- 記録先に書けない場合は、その旨を出力して構成を続ける。環境が構成できることを、記録が残ることより優先する
- 記録先はリポジトリの checkout と `$HOME` の双方から独立させてある。前者はセッションごとに作り直され、後者は `--setup-script` が上書きするため、いずれに置いても履歴が残らない

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
| ホームの構成の配置 | 行わない | `home/` 以下を `$HOME` へ置く (`home/.codex/` は `$CODEX_HOME` が設定されていればその直下へ置く) |
| 追加パッケージ | 環境変数で指定する | 引数または環境変数で指定する |
| 構成の記録 | 行う | 行う |

Setup script には `CLAUDE_ENV_FILE` が無く、セッションのシェルは `/etc/profile` を読まないため、環境変数では渡せない。既に PATH にある `/usr/local/bin` へ、`nix build .#default` の profile (中身は `nix/packages.nix`) と `nix` 自身を置く。

- system の同名のコマンド (`git`、coreutils 等) は Nix 版に置き換わる。覆ったものは実行時に列挙する
- 言語のツールチェーン (Node、Python 等) は含まない。クラウド環境が持つものを使うか、[追加のパッケージ](#追加のパッケージを指定する)として指定する
- ホームの構成は home-manager を経由しない (前節のとおり取得できないため)。置く内容は同一で、既存のファイルは上書きする。内容が異なるものは初回に `<ファイル名>.dotfiles-backup` へ退避する
- 本経路では `DOTFILES_ENV` が設定されない。`scripts/check-env.sh` はコマンドの実体が Nix の store にあることで判定するため、開発シェルを経由せずそのまま実行して成功する
- 初回は数分かかる。Setup script の目安 (5 分) を超えると環境のキャッシュが作られない

## ChatGPT Codex のクラウド環境

Codex のクラウド環境では、Environment の Setup script に以下を設定する。本リポジトリには Codex 向けの自動実行 hook を置いていないため、本リポジトリを対象にする場合もこの設定を使用する。

```bash
#!/bin/bash
set -euo pipefail

git clone --depth 1 https://github.com/sabas0ba/dotfiles /opt/dotfiles
/opt/dotfiles/scripts/cloud-setup.sh --setup-script --disposable
```

版を固定する場合、`--depth 1` を外し、`git -C /opt/dotfiles checkout <40 桁のリビジョン>` を setup script に加える。処理内容、既存ファイルの退避、再現性の例外および到達範囲の制約は、前節の「[他のリポジトリで使う](#他のリポジトリで使う)」と同じである。

Codex のクラウド環境は、既定では setup script の完了後にネットワークを遮断する。以降は取得ができないため、作業に必要なツールは setup script の中で揃える。`nix/packages.nix` に無いものは `--extra-packages` で足す ([追加のパッケージを指定する](#追加のパッケージを指定する))。

```bash
/opt/dotfiles/scripts/cloud-setup.sh --setup-script --disposable \
  --extra-packages "python3 gcc"
```

セットアップにより `home/.codex/AGENTS.md` が `${CODEX_HOME:-$HOME/.codex}/AGENTS.md` に配置され、リポジトリをまたぐ利用者共通の作業指示として Codex に読み込まれる。Codex のクラウド環境では `CODEX_HOME=/opt/codex` のため、配置先は `/opt/codex/AGENTS.md` となる。本リポジトリ内では、ルートの `AGENTS.md` がリポジトリ固有の手順を追加する。

---

[目次に戻る](index.md)
