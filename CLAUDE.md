# CLAUDE.md

Claude Code が本リポジトリで作業する際の補足。

本リポジトリの規約 (構成、変更手順、コーディング規約、コミット、禁止事項) は
[docs/development.md](docs/development.md) に定義してある。これらは人間の作業者にも
同様に適用されるため、本ファイルには重複して記述しない。当該ページを参照すること。

利用者向けの文書は `docs/` にあり、そのまま GitHub Pages で公開している。`README.md`
は概要と導線のみを持つ。内容を追記する場合は `docs/` を変更する。

利用者全体の共通規約は `home/.claude/CLAUDE.md` (配置先 `~/.claude/CLAUDE.md`) に
ある。

以下は、エージェントが作業する際に特に注意を要する事項のみを記述する。

## 作業前の確認

作業は開発シェルの内部で行う。開始時に確認すること。

```bash
scripts/check-env.sh   # ツールが揃い、その実体が Nix の store にあることを確認する
```

開発シェルの外にいる場合は `nix develop` (direnv 導入済みであれば `direnv allow`)
で入る。ツールを開発シェルの外から導入しない。

クラウド環境では SessionStart フックが `scripts/cloud-setup.sh` を呼び、開始時に環境を
構成するため上記の確認は最初から通る。通らない場合は当該スクリプトを再実行して原因を
確認する。詳細は [docs/setup.md](docs/setup.md#claude-code-のクラウド環境) にある。

## 確認を要する操作

以下は影響が利用者の環境に及ぶため、実行前に対象を提示し、承認を得ること。

- `make hm-switch` によるホームディレクトリへの配置。先に `make hm-dry` の結果を提示する
- `make wsl-switch` による WSL 上の NixOS への適用。先に `make wsl-dry` の結果を提示する
- `scripts/wsl-bootstrap.ps1` の実行。WSL にディストリビューションを登録し、
  利用者の Windows 環境を変更する
- 依存の追加 (flake の入力、`nix/packages.nix` のパッケージ、GitHub Actions)。
  追加する場合はリビジョンまたはダイジェストで固定する

## 単一情報源

`nix/packages.nix` は開発シェル、`nix build` の profile、Docker イメージの 3 つから
参照される。ツールの追加は本ファイルのみを編集する。`Dockerfile` にツール名を追記
した場合、定義が重複し不整合が生じる。

## WSL の隔離

WSL 上の環境は Windows 側から隔離してある (`/mnt` へのマウント、PATH の流入、
Windows の実行ファイルの起動をいずれも無効化)。目的と定義箇所は
[docs/windows.md](docs/windows.md#windows-側からの隔離) にある。

この設定を弱める変更を、作業を進めるために行わない。Windows 側のファイルが必要に
なった場合は、隔離を解除せず、対象を提示して指示を仰ぐ。`/etc/wsl.conf` を手元で
書き換えることも行わない (NixOS では次の switch で戻り、変更が記録されないため)。

## PowerShell スクリプト

`scripts/wsl-bootstrap.ps1` は `make lint` の対象外である。静的解析器
(PSScriptAnalyzer) を導入すると依存が増えるため、意図的に入れていない。したがって
本ファイルを変更した場合、機械的な検査は `scripts/check-pins.sh` による固定の確認
のみとなる。

このため、判断を伴う処理は `scripts/wsl-provision.sh` (shellcheck / shfmt および
`nix flake check` の対象) に置く。bootstrap 側に処理を足さないこと。足す場合は、
provision がまだ存在しない時点でしか実行できないものに限る。

## 変更後の検証

`make check` を通すこと。`Dockerfile` または `nix/` を変更した場合は
`make docker-check` も実行する。検査を通過させるために検査自体を削除しない。
