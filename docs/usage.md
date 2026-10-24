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

Playwright の browser path は `nix develop .#browser` と Docker では自動的に設定される。`nix build .#browser` の出力を PATH へ直接追加する場合は、同じ出力に含まれる環境定義も読み込む。

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
- 生ファイルの配置: `home/` 以下がホームディレクトリの構造に対応する (`home/.codex/AGENTS.md` → `~/.codex/AGENTS.md`、`home/.claude/CLAUDE.md` → `~/.claude/CLAUDE.md`、`home/.gemini/AGENTS.md` → `~/.gemini/AGENTS.md`)

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
| `agent` | `/home/agent` (明示) | [tidyy](https://github.com/sabas0ba/tidyy) の sandbox コンテナ内で agent を動かす利用者 |

`nixos` は NixOS-WSL の `wsl.defaultUser` の既定値である。改名すると初回の `nixos-rebuild` が終わるまで対象が存在しないことになるため、既定値のまま使う。

`agent` は tidyy がコンテナに接続する `HOME` (`/home/agent`) に対応する。コンテナ内の利用者は host の実行ユーザと同じ uid であり passwd の項目を持たないため、名前は利用者名ではなく役割を表す。

導入経路は tidyy の `--home-files` とする。host で activation package をビルドし、その `home-files` (store への symlink からなるホームの木) を session の作成時に `HOME` の volume へ複製する。複製は symlink を実体のファイルに展開し、所有者は host の実行ユーザ、権限はディレクトリ `0700`、ファイル `0600` になる。コンテナ内で home-manager の activation を実行しないため、passwd の項目や `USER`、nix store はコンテナに不要である。

```bash
nix build .#homeConfigurations.agent.activationPackage
tidyy new -s work --provider podman --base <image> --home-files result/home-files -- claude
```

この経路の制約を次に示す。

- 複製するのは `home-files` だけである。`home-path` (`hm-session-vars.sh` を含む profile) は複製しないため、`home.sessionVariables` はコンテナ内で設定されない。Claude Code の telemetry 無効化は `~/.claude/settings.json` の `env` で適用され、Codex の `/etc/codex/config.toml` は system 層のため image 側で配置する。
- `--home-files` は session の作成時だけ作用し、volume が空でない場合は既存の状態を守るため失敗する。構成を更新する場合は volume を削除して session を作り直す。
- コンテナ内で `make hm-switch HM_TARGET=agent` を実行する経路は、image に nix と本リポジトリを入れる必要があり、現時点では採らない。

Claude Code のリモート実行環境では `~/.gitconfig` をセッション側が管理している。home-manager が生成するのは `~/.config/git/config` なのでファイルの衝突は起きないが、git は `~/.gitconfig` を後に読むため、user の設定は当該環境ではセッション側が優先される。

### Claude Code の設定

`home/.claude` は `recursive = true` で配置する。ディレクトリごとではなく配下のファイルを個別に symlink するため、`~/.claude` に管理外のファイルがあっても置き換えない。

`home/.claude/settings.json` は permission の既定値で、認証情報を含むファイルの読み出しと認証済み CLI の実行をそれぞれ deny / ask に置く。対象とする操作の共通方針は `home/.codex/AGENTS.md` の「実行環境と到達範囲」、Claude Code 固有の制約は `home/.claude/CLAUDE.md` にある。

これは Claude Code がツール実行前に行う検査であって OS レベルの強制ではなく、Bash から起動した子プロセスには及ばない。WSL では[隔離](windows.md#windows-側からの隔離)を主たる担保とし、本設定はそれが使えない環境 (Windows ネイティブ、Linux ホスト) 向けの補助である。

配置されたファイルは Nix store への symlink であり書き込めない。プロジェクト側で緩める場合は当該リポジトリの `.claude/settings.json` を使う (プロジェクトの設定が優先される)。

### Antigravity の設定

`home/.gemini` も `recursive = true` で配置し、`~/.gemini` 内の認証情報や状態ファイルを置き換えずに `home/.gemini/AGENTS.md` だけを配置する。

Antigravity CLI の `~/.gemini/antigravity-cli/settings.json` および共通設定の `~/.gemini/config/config.json` は、モデル選択や `/config`・`/permissions` の操作時に Antigravity 自身が書き換えるファイルであり、ホスト固有の値も含む。読み取り専用の symlink で配置する home-manager の対象にすると設定変更の保存が失敗するため、本リポジトリでは配布しない。

手元の環境で `home/.claude/settings.json` と同等の補助検査を設定する場合は、`~/.gemini/antigravity-cli/settings.json` に次を設定する。

```json
{
  "allowNonWorkspaceAccess": false,
  "showFeedbackSurvey": false,
  "toolPermission": "request-review",
  "permissions": {
    "deny": [
      "read_file(/mnt/)",
      "read_file(~/.ssh/)",
      "read_file(~/.gnupg/)",
      "read_file(~/.aws/)",
      "read_file(~/.azure/)",
      "read_file(~/.config/gcloud/)",
      "read_file(~/.config/gh/)",
      "read_file(~/.kube/)",
      "read_file(~/.docker/config.json)",
      "read_file(~/.netrc)",
      "read_file(~/.npmrc)",
      "read_file(~/.pypirc)",
      "read_file(~/.git-credentials)",
      "read_file(.env)"
    ],
    "ask": [
      "command(sudo)",
      "command(gh)",
      "command(az)",
      "command(aws)",
      "command(gcloud)",
      "command(kubectl)",
      "command(docker)",
      "command(podman)",
      "command(ssh)",
      "command(scp)",
      "command(rsync)",
      "command(wsl.exe)",
      "command(cmd.exe)",
      "command(powershell.exe)",
      "command(pwsh.exe)"
    ]
  }
}
```

2026-10-24 に確認した [Agent permissions](https://antigravity.google/docs/permissions?tab=cli) と [CLI settings schema](https://antigravity.google/schemas/v1/settings.json) に基づく。上記の設定には次の制約がある。

- `allowNonWorkspaceAccess: false` と `toolPermission: "request-review"` は既定値である。`/config` で変更された場合に設定ファイル上で差分として確認できるよう明記している
- `read_file` の対象は「絶対パス、または workspace root からの相対パス」と記載されており、`~` の展開は記載がない。`~` を含む deny が有効である保証はないため、`/home/<user>/.ssh/` のような絶対パスも併記する。本ファイルは配布しないため、ホスト固有のパスを記載してよい
- ディレクトリを指定した規則は配下に再帰的に適用される。`**` などの glob は記載がないため、`read_file(.env)` は workspace root 直下の `.env` だけを対象とし、`home/.claude/settings.json` の `Read(//**/.env)` および `Read(//**/.env.*)` と同等にはならない
- `command(...)` は先頭の token から前方一致で照合し、パイプや `&&` で連結したコマンドは要素ごとに照合する。`$(...)` などを含む行では前方一致が無効になる
- 規則が shell から起動した child process や `cat` による読み取りに及ぶかは記載がない。Claude Code と同様に OS level の強制とはみなさない

より強い制限が必要な場合は次を検討する。

- `toolPermission: "strict"`: ファイルの読み取りを含むすべての操作の前に確認する
- `enableTerminalSandbox: true`: agent が起動する terminal command を OS の container 内で実行する。Windows 10、古い Windows 11、一部の Linux host や container では効果がなく、`/config` に表示されない。WSL での有効性は未確認である

### Telemetry の無効化

Claude Code、GitHub CLI、GitHub Copilot CLI、Codex CLI、Antigravity の telemetry およびデータ収集を無効化する。環境変数で制御できるものは `nix/telemetry.nix` で、Codex は system 層の `config.toml` で、Antigravity は各クライアントの設定で扱う。

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
| その他の home-manager 対象 | 自動では配置しない。開発シェル内で `sudo env "PATH=$PATH" scripts/install-etc.sh` を実行する。クラウド環境と同じ処理で overlay する |

既存の `/etc/codex/config.toml` は初回だけ `.dotfiles-backup` へ退避し、管理外の key を保持したまま本ファイルの値を重ねる。書き戻しでコメントは失われる。日時の値を含む場合や merge 結果を検証できない場合は、既存ファイルを変更せずに失敗する ([Setup script の制約](setup.md) を参照)。

値は `make check` の `codex-telemetry` が検査する。

#### Antigravity

Antigravity (CLI / Antigravity 2.0 / Antigravity IDE / VS Code 拡張) の設定ファイルはクライアント自身が書き込む user 層にあるため、home-manager の管理対象には置かず、環境ごとに次を設定する。設定変更後は稼働中の CLI やアプリケーションを再起動して全プロセスに反映する。

| 対象 | 設定箇所 | 設定内容 |
| --- | --- | --- |
| Antigravity App / IDE | Settings の Account | `Enable Telemetry` を無効化する |
| Antigravity CLI (`agy`) | `/config` | `Enable Telemetry` を無効化する。選択はアカウントに保存される |
| Antigravity CLI のアンケート表示 | `~/.gemini/antigravity-cli/settings.json` | 任意で `"showFeedbackSurvey": false` を設定する。telemetry 無効化とは別の設定 |

2026-10-24 に確認した [公式 Settings](https://antigravity.google/docs/settings) と [CLI settings schema](https://antigravity.google/schemas/v1/settings.json) に基づく。`enableTelemetry` は `settings.json` から読み取られず、CLI の保存時に削除されるため、同ファイルに `false` を記載しても無効化できない。設定後に `/config` または Account を開き直し、無効になっていることを確認する。

検証範囲は公式資料との照合に限る。実機で確認したクライアントのバージョン、および通信の停止確認は未記録である。IDE / VS Code 拡張の `antigravity.enableTelemetry`、IDE 固有の `User/settings.json` と `argv.json` の配置先・有効性は確認できていないため、無効化手順には含めない。VS Code 本体の telemetry と Antigravity のアカウント側の収集は区別し、本体の設定だけで拡張機能の収集も停止したとはみなさない。

### Agent の作業規約

`home/.codex/AGENTS.md` は利用者共通の作業規約の原本である。`home/.claude/CLAUDE.md` は Claude Code が `@path` import で、`home/.gemini/AGENTS.md` は Antigravity が `@[label](path)` include で同じ規約を読み込むための互換入口とし、共通規約を複製しない。本リポジトリの `AGENTS.md` はリポジトリ固有の規約と検証手順を追加する。これらには秘密情報やマシン固有の値を記載しない。

Antigravity の入口と include 構文は [公式 Rules](https://antigravity.google/docs/rules/) に従う。home-manager では `~/.codex/AGENTS.md` を参照する。Cloud Setup の `--setup-script` 経路では `CODEX_HOME` を変更できるため、Antigravity の入口を配置する際に原本の本文を展開し、配置先のパスに依存しないようにする。生成済みの入口は手編集せず、原本の更新後に Cloud Setup を再実行する。`make check` は実際の入口を用いて、共通規約の展開、再配置時の更新、初回 backup の保持、および展開後のサイズが Antigravity の規則ファイルの上限 (24,000 bytes) 以下であることを検査する。上限を超えた部分は切り詰められるため、共通規約を拡充する際は同検査の結果を確認する。

`home/.codex` および `home/.gemini` もファイル単位で配置するため、各ツールが同じディレクトリに作成する認証情報や状態ファイルを置き換えない。認証情報や実行環境ごとの差異を含む user 層の設定 (`${CODEX_HOME}/config.toml`、`~/.gemini/antigravity-cli/settings.json`、`~/.gemini/config/config.json`) は本リポジトリでは配布しない。Codex の telemetry 無効化だけを system 層に置く ([Codex CLI](#codex-cli))。

## コンテナ環境

ホストと同一の環境をコンテナ内に構築する。`Dockerfile` はツールの一覧を持たず `flake.nix` を評価するため、内容がホストと一致する。Windows で WSL containers (`wslc`) を使う場合は [Windows (WSL)](windows.md#wsl-containers-wslc) を参照する。

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
