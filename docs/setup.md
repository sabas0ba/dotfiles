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

[Claude Code](https://claude.ai/code) のリモート実行環境では、セッションごとに Nix を持たない Ubuntu のコンテナが用意される。`.claude/settings.json` の SessionStart フックが `scripts/cloud-setup.sh` を呼び、上記と同じ手順で環境を構成するため、手動の操作は要らない。

- Nix の導入 — 本ページと同じ版を、固定した sha256 で検証してから展開する。版と sha256 は `scripts/nix-pin.sh` の 1 か所で定義し、WSL の Ubuntu 経路と共有する。当該環境には systemd が無いため、daemon ではなく単一利用者の方式で導入する
- 開発シェルの実体化 — `nix develop` の結果を profile として置く。`Dockerfile` がイメージのビルド時に行っているのと同じ処理であり、profile は GC ルートとなる
- 環境の引き渡し — 開発シェルの `PATH` と `DOTFILES_ENV` をセッションに渡す。以降のコマンドは `nix develop` を経由せずに開発シェルと同一のツールで動作し、`scripts/check-env.sh` がそのまま通る

構成後のコンテナの状態は保存されるため、2 回目以降のセッションの開始は速い。フックは `CLAUDE_CODE_REMOTE=true` の環境でのみ動作し、手元の環境には何も行わない。

到達できる取得先は環境のネットワーク設定に依存する。許可されていない取得先は 403 となるため、`nix flake check` が flake の入力 (home-manager、NixOS-WSL) の取得で失敗することがある。この場合も開発シェルは成立しており、取得を伴わない検査は実行できる。

```bash
scripts/check-env.sh                          # 環境のスモークテスト
nix build --no-link .#checks.x86_64-linux.pins  # 個別の検査
```

すべての検査を実行する必要がある場合は、環境のネットワーク設定で当該の取得先を許可する。

---

[目次に戻る](index.md)
