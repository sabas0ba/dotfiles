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

## Toolchain profile

既定の `nix develop` と direnv は、dotfiles の保守に必要な `default` profile だけを導入する。容量の大きいコンパイラ、コンテナ、HDL、browser、Blender は用途別 profile を明示して取得する。

| Profile | 主な内容 | 対応 platform |
| --- | --- | --- |
| `default` | Git、Nix・shell の formatter/linter、基本 utility | Linux / Darwin |
| `software` | Python、Rust、Zig、native C/C++、CMake、Ninja、Node.js、TypeScript | Linux / Darwin |
| `containers` | Docker CLI、Podman、QEMU | Linux / Darwin。Podman は Linux のみ |
| `hdl` | Veryl、Verible、Verilator、native C/C++ | Linux / Darwin。Verible は Linux のみ |
| `browser` | TypeScript、Playwright と Chromium/Firefox/WebKit | Linux のみ |
| `vrchat` | Blender (headless 実行と FBX export) | Linux / Darwin |
| `full` | 現在の platform で利用可能な上記すべて | Linux / Darwin |

開発シェルと通常の Nix package は同じ profile 名を使う。

```bash
nix develop .#software
make shell TOOLCHAIN_PROFILE=hdl

nix build .#containers
make toolchain-build TOOLCHAIN_PROFILE=full
```

`scripts/check-env.sh` の検査対象も選択した profile に追従する。コマンド一覧を shell script 側で重複管理せず、`nix/packages.nix` の各 package と対応付けたコマンド契約から生成する。

Playwright の browser path は `nix develop .#browser` と Docker では自動的に設定される。`nix build .#browser` の出力を PATH へ直接載せる場合は、同じ出力に含まれる環境定義も読み込む。

```bash
out=$(nix build --no-link --print-out-paths .#browser)
export PATH="$out/bin:$PATH"
. "$out/share/dotfiles/environment"
```

プロジェクト側で `@playwright/test` または `playwright` を依存に持つ場合、その version は `nix/packages.nix` が固定する `playwright-driver.browsers` と一致させる。version が異なる browser を実行時に download しない。

`vrchat` は Blender を headless (`blender -b --python`) で使う前提であり、GUI の起動は host 側の display と GPU に依存する。モデル制作の project は本リポジトリに置かず、専用リポジトリからこの profile を利用する。

`containers` は CLI と仮想化 tool を提供するだけである。Docker daemon、Podman の user namespace、QEMU/KVM などの権限と system service はホスト側で構成する。

## ホームディレクトリの構成

ホームディレクトリの内容は home-manager で宣言的に管理する。管理対象は 2 種類ある。

- 設定の生成: [`nix/home.nix`](https://github.com/sabas0ba/dotfiles/blob/main/nix/home.nix) の `programs.git` 等。git の user/email もここで設定する
- 生ファイルの配置: `home/` 以下がホームディレクトリの構造に対応する (`home/.codex/AGENTS.md` → `~/.codex/AGENTS.md`、`home/.claude/CLAUDE.md` → `~/.claude/CLAUDE.md`)

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

`home/.claude/settings.json` は permission の既定値で、認証情報を含むファイルの読み出しと認証済み CLI の実行をそれぞれ deny / ask に置く。対象とする操作の共通方針は `home/.codex/AGENTS.md` の「実行環境と到達範囲」、Claude Code 固有の制約は `home/.claude/CLAUDE.md` にある。

これは Claude Code がツール実行前に行う検査であって OS レベルの強制ではなく、Bash から起動した子プロセスには及ばない。WSL では[隔離](windows.md#windows-側からの隔離)を主たる担保とし、本設定はそれが使えない環境 (Windows ネイティブ、Linux ホスト) 向けの補助である。

配置されたファイルは Nix store への symlink であり書き込めない。プロジェクト側で緩める場合は当該リポジトリの `.claude/settings.json` を使う (プロジェクトの設定が優先される)。

### Telemetry の無効化

Claude Code、GitHub CLI、GitHub Copilot CLI、Codex CLI の telemetry およびデータ収集を無効化する。Codex 以外は環境変数で、Codex は環境変数で制御できないため system 層の `config.toml` で扱う。

#### 環境変数

一覧は [`nix/telemetry.nix`](https://github.com/sabas0ba/dotfiles/blob/main/nix/telemetry.nix) が単一情報源であり、次の経路に反映する。

| 経路 | 反映先 |
| --- | --- |
| `home/.claude/settings.json` と `.claude/settings.json` の `env` | Claude Code 本体と、その Bash tool から起動する子プロセス。シェルを経由しない起動 (IDE 拡張等) も含む |
| `nix/home.nix` の `home.sessionVariables` | `hm-session-vars.sh` を読み込むシェル |
| `nix/wsl.nix` の `environment.sessionVariables` | WSL 上の NixOS の全ユーザーのログインシェル |
| 開発シェルと profile の環境 | `nix develop`、direnv、Docker image (entrypoint が開発シェルに入る)、`dotfiles-toolchain-info environment` |

本構成は home-manager にシェルの設定ファイル (`~/.bashrc` 等) を管理させていないため、WSL 上の NixOS 以外のホストでは `make hm-switch` だけでは通常のシェルに `home.sessionVariables` が反映されない。当該ホストでは、既存のシェルの設定ファイル (bash では `~/.profile` または `~/.bashrc`) に次を追記する。

```bash
if [ -f "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" ]; then
  . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
fi
```

`hm-session-vars.sh` は一度読み込むと再読み込みを抑止する変数を設定するため、`nix/telemetry.nix` を変更した後は新しいログインシェルで反映を確認する。

クラウド環境では経路ごとに次が適用される。

- Claude Code のフック経路 (本リポジトリ): `.claude/settings.json` の `env` が Claude Code の起動時に読まれる。`scripts/cloud-setup.sh` は profile の環境を `$CLAUDE_ENV_FILE` へ書き、Bash tool にも渡す
- setup script 経路: 同スクリプトが配置する `~/.claude/settings.json` の `env` が Claude Code に、`/etc/codex/config.toml` の `shell_environment_policy.set` が Codex の実行するコマンドに適用される。setup script はセッションのシェルへ環境変数を渡せないため、Codex 側はこの設定で与える

| 変数 | 値 | 対象 |
| --- | --- | --- |
| `DISABLE_TELEMETRY` | `1` | Claude Code の利用状況 metrics |
| `DISABLE_ERROR_REPORTING` | `1` | Claude Code のエラー報告 |
| `DISABLE_FEEDBACK_COMMAND` | `1` | Claude Code の `/feedback`、`/bug`、`/share` |
| `CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY` | `1` | Claude Code のセッション品質 survey と transcript 共有の確認 |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` | `1` | Claude Code の非必須通信全体 (上記 4 項目を含む) |
| `GH_TELEMETRY` | `false` | GitHub CLI (2.91.0 以降) の利用状況 telemetry |
| `COPILOT_OFFLINE` | `true` | GitHub Copilot CLI の offline mode。telemetry を含め GitHub へ接続しない |
| `DO_NOT_TRACK` | `1` | 慣習的な opt-out。gh と Claude Code が参照する |

`settings.json` と `etc/codex/config.toml` は生ファイルのため値を複製している。一致は `make check` の `telemetry-env` と `codex-telemetry` が検査する。

GitHub Copilot CLI は telemetry だけを無効化する公開設定を持たない。`COPILOT_OFFLINE=true` は telemetry を止める一方で GitHub への接続と認証も無効にし、BYOK provider を使う offline mode へ動作を変える。Copilot は GitHub の Web 上でのみ使い CLI は使わない前提のため、共通設定に含める。CLI を使う環境では `unset COPILOT_OFFLINE` とする。Web 上の Copilot には影響しない。

`CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` と `DISABLE_TELEMETRY` は `0` や `false` でも有効になる。戻す場合は変数ごと削除する。

#### Claude Code への副作用

一次情報は [Environment variables](https://code.claude.com/docs/en/env-vars) と [Data usage](https://code.claude.com/docs/en/data-usage#telemetry-services) である。

`DISABLE_TELEMETRY`、`DO_NOT_TRACK`、`CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` のいずれかで feature flag の取得が止まり、次が使えなくなる。

- `AGENTS.md` の自動読み込み (`CLAUDE.md` のみ読む)。本リポジトリと `home/.claude/CLAUDE.md` は `@` import で `AGENTS.md` を読むため影響しない
- Pro / Max / Team plan での auto mode による既定の開始
- Remote Control、他のマシンのセッションへの messaging
- claude.ai で有効にした skill と plugin の同期
- advisor tool、`/skill-doctor`、`claude import`
- artifact の comment の読み取りと返信
- 大きな貼り付けを pasted text として扱う処理、API が拒否する MCP tool schema の除外

`CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` は加えて次を止める。

- 自動更新、release notes、PR / MR status badge の確認、fast mode 等の可用性確認
- plugin の `command` source の background 実行
- artifact の作成

公式 plugin marketplace の自動導入と WebFetch の domain 検査は対象外であり、それぞれ `CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL` と `skipWebFetchPreflight` で制御する。後者は安全性の検査のため無効化していない。

#### Codex CLI

[`etc/codex/config.toml`](https://github.com/sabas0ba/dotfiles/blob/main/etc/codex/config.toml) を system 層の `/etc/codex/config.toml` に置き、`analytics.enabled`、`feedback.enabled`、`otel.metrics_exporter` で無効化する。user 層 (`${CODEX_HOME}/config.toml`) は Codex 自身が書き込むため、home-manager による読み取り専用の配置と両立しない。system 層は user 層より優先度が低く、user 層で同じ key を設定するとそちらが有効になる。

| 環境 | 配置 |
| --- | --- |
| WSL 上の NixOS | `nix/wsl.nix` の `environment.etc` (`make wsl-switch`) |
| クラウド環境 (setup script 経路) | `scripts/cloud-setup.sh` が既存の `/etc/codex/config.toml` を保持しつつ、本ファイルの値を overlay する |
| その他の home-manager 対象 | 自動では配置しない。`sudo install -D -m 0644 etc/codex/config.toml /etc/codex/config.toml` で配置する |

値は `make check` の `codex-telemetry` が検査する。

### Agent の作業規約

`home/.codex/AGENTS.md` は利用者共通の作業規約の原本である。`home/.claude/CLAUDE.md` は Claude Code が `@path` import で同じ規約を読み込むための互換入口とし、共通規約を複製しない。本リポジトリの `AGENTS.md` はリポジトリ固有の規約と検証手順を追加する。これらには秘密情報やマシン固有の値を記載しない。

`home/.codex` もファイル単位で配置するため、Codex が同じディレクトリに作成する認証情報や状態ファイルを置き換えない。認証情報や実行環境ごとの差異を含む user 層の `config.toml` は本リポジトリでは配布しない。telemetry の無効化だけを system 層に置く ([Codex CLI](#codex-cli))。

## コンテナ環境

ホストと同一の環境をコンテナ内に構築する。`Dockerfile` はツールの一覧を持たず `flake.nix` を評価するため、内容がホストと一致する。

```bash
make docker-build                              # default profile のイメージ構築
make docker-shell TOOLCHAIN_PROFILE=software   # software profile の開発シェルに入る
make docker-smoke                              # ツールの存在を確認する軽量スモークテスト
make docker-check TOOLCHAIN_PROFILE=hdl        # hdl profile で CI と同じオフラインの全検査
```

直接実行する場合:

```bash
docker build -t dotfiles-dev .
docker build --build-arg DOTFILES_TOOLCHAIN_PROFILE=browser -t dotfiles-browser .
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
