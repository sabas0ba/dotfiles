# AGENTS.md

Codex が本リポジトリで作業する際の補足。

本リポジトリの規約 (構成、変更手順、コーディング規約、コミット、禁止事項) は
[docs/development.md](docs/development.md) に定義してある。作業前に同ページと
[CLAUDE.md](CLAUDE.md) を参照すること。`CLAUDE.md` にある規約は Claude Code に限らず、
本リポジトリを変更する作業者に適用する。本段落は両ファイルを参照する許可を兼ねる。

利用者共通の規約と競合する場合は本リポジトリの規約を優先する。本ファイルは Codex
固有の入口であり、`CLAUDE.md` と `docs/development.md` の競合しない指示もすべて適用する。

作業は Nix の開発シェル内で行い、開始時に次を実行する。

```bash
scripts/check-env.sh
```

通らない場合は `nix develop` で開発シェルに入る。変更後は `make check` を実行する。
`Dockerfile` または `nix/` を変更した場合は `make docker-check` も実行する。

