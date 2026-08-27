# 使い方

操作ごとの対応 system は[対応範囲](index.md#対応範囲)にある。本ページは、使用する機能が対象 system に対応していることを前提とする。

## 日常の操作

```bash
make help          # 利用可能な操作の一覧
make check         # すべての検査 (整形・静的解析・環境のスモークテスト)
make fmt           # Nix およびシェルスクリプトの整形
make lint          # 静的解析のみ
make shell         # 開発シェルに入る (direnv 未使用時)
```

作業は開発シェルの内部で行う。`scripts/check-env.sh` が、必要なツールが揃っていることと、その実体が Nix の store にあることを検査する。開発シェルの内部であれば `DOTFILES_ENV` が `nix-develop` となり、同スクリプトの最後に表示される。

ツールを開発シェルの外から導入しない。`apt install` / `brew install` / `npm install -g` / `pip install --user` は再現性を損なう。必要なツールは [`nix/packages.nix`](https://github.com/sabas0ba/dotfiles/blob/main/nix/packages.nix) に追記して取得する。

## ホームディレクトリの構成

ホームディレクトリの内容は home-manager で宣言的に管理する。管理対象は 2 種類ある。

- 設定の生成: [`nix/home.nix`](https://github.com/sabas0ba/dotfiles/blob/main/nix/home.nix) の `programs.git` 等。git の user/email もここで設定する
- 生ファイルの配置: `home/` 以下がホームディレクトリの構造に対応する (`home/.claude/CLAUDE.md` → `~/.claude/CLAUDE.md`、`home/.codex/AGENTS.md` → `~/.codex/AGENTS.md`)

既存ファイルを置き換える可能性があるため、必ず先に配置内容を確認する。

```bash
make hm-build   # 構成の構築のみ (ホームディレクトリは変更しない)
make hm-dry     # 配置内容の確認
make hm-switch  # 配置の実行
```

`HM_TARGET` は既定で実行中のユーザー名 (`id -un`) を使う。その名前と system が `homeTargets` の定義に一致する場合は指定不要である。一致する定義がなければ実行できない。既存 target の対応 system は[対応範囲](index.md#対応範囲)にある。明示する場合は `make hm-switch HM_TARGET=<name>` とする。

### 適用対象

対象は `flake.nix` の `homeTargets` に定義する。ホームディレクトリはユーザー名と `system` から導出する (linux は `/home/<name>`、darwin は `/Users/<name>`)。規則から外れる対象だけ `homeDirectory` を明示する。したがってマシンを追加する場合、通常はユーザー名と `system` の指定で足りる。

| 対象 | ホームディレクトリ | 用途 |
| --- | --- | --- |
| `sabas0ba` | `/home/sabas0ba` (導出) | 個人環境 |
| `nixos` | `/home/nixos` (導出) | [WSL 上の環境](windows.md) |
| `root` | `/root` (明示) | Claude Code のリモート実行環境 |

`nixos` は NixOS-WSL の `wsl.defaultUser` の既定値である。改名すると初回の `nixos-rebuild` が終わるまで対象が存在しないことになるため、既定値のまま使う。

Claude Code のリモート実行環境では `~/.gitconfig` をセッション側が管理している。home-manager が生成するのは `~/.config/git/config` なのでファイルの衝突は起きないが、git は `~/.gitconfig` を後に読むため、user の設定は当該環境ではセッション側が優先される。

### Claude Code の設定

`home/.claude` は `recursive = true` で配置する。ディレクトリごとではなく配下のファイルを個別に symlink するため、`~/.claude` に管理外のファイルがあっても置き換えない。

`home/.claude/settings.json` は permission の既定値で、認証情報を含むファイルの読み出しと認証済み CLI の実行をそれぞれ deny / ask に置く。方針は `home/.claude/CLAUDE.md` の「実行環境と到達範囲」にある。

これは Claude Code がツール実行前に行う検査であって OS レベルの強制ではなく、Bash から起動した子プロセスには及ばない。WSL では[隔離](windows.md#windows-側からの隔離)を主たる担保とし、本設定はそれが使えない環境 (Windows ネイティブ、Linux ホスト) 向けの補助である。

配置されたファイルは Nix store への symlink であり書き込めない。プロジェクト側で緩める場合は当該リポジトリの `.claude/settings.json` を使う (プロジェクトの設定が優先される)。

### Codex の設定

`home/.codex/AGENTS.md` は Codex がリポジトリをまたいで参照する入口であり、利用者共通の作業規約である `~/.claude/CLAUDE.md` を参照する。規約を複製せず、Claude Code と Codex の内容を一致させる。本リポジトリの `AGENTS.md` はリポジトリ固有の規約と検証手順を追加する。これらには秘密情報やマシン固有の値を記載しない。

`home/.codex` もファイル単位で配置するため、Codex が同じディレクトリに作成する認証情報や状態ファイルを置き換えない。認証情報や実行環境ごとの差異を含む `config.toml` は本リポジトリでは配布しない。

## コンテナ環境

ホストと同一の環境をコンテナ内に構築する。`Dockerfile` はツールの一覧を持たず `flake.nix` を評価するため、内容がホストと一致する。

```bash
make docker-build   # イメージの構築
make docker-shell   # コンテナ内の開発シェルに入る (カレントディレクトリをマウント)
make docker-smoke   # ツールの存在を確認する軽量スモークテスト
make docker-check   # CI と同じオフラインの全検査
```

直接実行する場合:

```bash
docker build -t dotfiles-dev .
docker run --rm -it -v "$PWD:/workspace" dotfiles-dev
```

ビルド時に開発シェルを Nix の profile として実体化しているため、起動は約 1 秒でネットワークも要らない。flake のすべての入力のソースを含むので、`--network none` のまま `make check` が通る。

検査用の `docker run` オプションは Makefile の 1 か所に置く。`docker-smoke` と `docker-check` は、現在の Docker build context を `docker-build` でイメージへ保存し、その source を mount で上書きせずに検査する。commit 前の変更も build context に含まれ、`flake.nix`、`flake.lock`、`nix/` に対応する profile、Nix store の閉包、検査対象の source が同じイメージ内で揃う。`docker-smoke` はコマンドの存在だけを短時間で確認し、`docker-check` は `make check` の全項目と、ネットワーク無しでイメージが自己完結することを確認する。対話用の `docker-shell` だけは、編集を反映するため現在の worktree をマウントする。

コンテナ内では名前 `nixpkgs` も `flake.lock` で固定した nixpkgs に解決される。以下はネットワーク無しで動く。

```bash
nix shell nixpkgs#jq
```

---

[目次に戻る](index.md)
