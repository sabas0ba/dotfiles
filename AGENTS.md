# AGENTS.md

本リポジトリで作業する coding agent 向けの指示。Claude Code を含むすべての agent に適用する。

開発規約の原本は [docs/development.md](docs/development.md) である。作業前に参照すること。本段落は参照の許可を兼ねる。利用者共通規約の管理元は [home/.codex/AGENTS.md](home/.codex/AGENTS.md) であり、競合時は利用者の明示的な指示、本ファイルと `docs/development.md`、利用者共通規約の順に優先する。

利用者向け文書は `docs/` に置き、そのまま GitHub Pages で公開する。`README.md` は概要と導線だけを持つ。

## 作業前の確認

Nix 開発シェル内で作業し、開始時に次を実行する。

```bash
scripts/check-env.sh
```

失敗した場合は `nix develop` または `direnv allow` で開発シェルに入る。ツールを開発シェルの外へ導入しない。クラウド環境では `scripts/cloud-setup.sh` が環境を構成するため、失敗時は同スクリプトの実行結果を確認する。詳細は [docs/setup.md](docs/setup.md) を参照する。

## 承認が必要な操作

次の操作は対象と事前確認結果を提示し、承認後に実行する。

- `make hm-switch`: 先に `make hm-dry` を提示する
- `make wsl-switch`: 先に `make wsl-dry` を提示する
- `scripts/wsl-bootstrap.ps1`: WSL distro を登録し、Windows 環境を変更する
- 依存の追加: flake input、`nix/packages.nix` の package、GitHub Actions を含む。revision または digest で固定する

## 実装上の制約

### Toolchain

`nix/packages.nix` は開発シェル、`nix build` の profile、Docker image が共有する単一情報源である。ツールは同ファイルに追加し、`Dockerfile` に重複して記述しない。

### WSL

WSL は `/mnt` の mount、Windows PATH の流入、Windows executable の起動を無効化している。この隔離を作業都合で弱めない。Windows 側のファイルが必要な場合は、隔離や `/etc/wsl.conf` を変更せず指示を仰ぐ。詳細は [docs/windows.md](docs/windows.md#windows-側からの隔離) を参照する。

### PowerShell

`scripts/wsl-bootstrap.ps1` は `make lint` と PSScriptAnalyzer の対象外であり、機械的な検査は pin の確認に限られる。判断を伴う処理は原則として、shellcheck、shfmt、`nix flake check` の対象である shell script に置く。bootstrap に残せるのは、provision 前に必要な配布 image と管理 marker の照合、利用者の作成、repository の検証と取得に限る。

## 検証

変更後は次を実行する。

```bash
make check
```

`Dockerfile` または `nix/` を変更した場合は、追加で次を実行する。

```bash
make docker-check
```

検査を通すために検査自体を削除しない。WSL 関連の実機検証は承認を得てから行う。
