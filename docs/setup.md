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

---

[目次に戻る](index.md)
