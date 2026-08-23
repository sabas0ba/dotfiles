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

### 環境に指定する設定

環境は claude.ai/code のメッセージ入力欄の上にある環境セレクタ (雲のアイコン) から作成・変更する。本リポジトリに対して指定するものは以下である。

| 項目 | 指定 |
| --- | --- |
| Network access | Trusted (既定)。変更しない |
| Environment variables | 不要 |
| Setup script | 不要 |

Network access を既定のままでよいのは、Trusted の許可リストに `*.nixos.org` が含まれるためである。フックが到達する必要があるのは以下の 2 つで、いずれもこれに含まれる。

- `releases.nixos.org` — Nix 本体の配布物
- `cache.nixos.org` — 依存のバイナリ

None を指定した場合、フックは Nix を取得できずに失敗する。セッション自体は開始するが、開発シェルが無いため `make` も検査も実行できない。Custom を指定する場合は上記の 2 つを許可リストに加える。

Setup script は使わない。当該欄は VM に素の状態で足りないツールを入れるためのものであり、本リポジトリの構成はリポジトリ内の SessionStart フックが行う。フックに置くことで、同じ定義がクラウドと手元の双方に効く。

### 到達範囲の制限

GitHub への要求は、ネットワークの設定とは別の proxy を通り、セッションに紐付いたリポジトリだけに制限される。したがって `github:` 形式の flake の入力は、当該リポジトリが紐付いていない限り取得できない (403)。これは Network access を Full にしても変わらない。

実際には入力ごとに以下のようになる。

- `nixpkgs` — 取得は 403 となるが、`cache.nixos.org` から substitute できるため影響がない
- `home-manager`、`NixOS-WSL` — substitute できないため取得が必要であり、`nix flake check` はここで失敗する

開発シェルは成立しているため、取得を伴わない検査は実行できる。

```bash
scripts/check-env.sh                             # 環境のスモークテスト
nix build --no-link .#checks.x86_64-linux.pins   # 個別の検査
```

すべての検査 (`make check`) は CI がコンテナ内で実行する。イメージは構築時に flake の入力をすべて取り込んでおり、`--network none` で完結する。

---

[目次に戻る](index.md)
