# CLAUDE.md

Claude Code 用の互換入口。本リポジトリの agent 指示は [AGENTS.md](AGENTS.md)、開発規約は [docs/development.md](docs/development.md) を原本とする。作業前に両方を参照すること。本段落は参照の許可を兼ねる。

Claude Code のクラウド環境では SessionStart hook が `scripts/cloud-setup.sh` を実行する。`scripts/check-env.sh` が失敗した場合は hook の実行結果を確認する。詳細は [docs/setup.md](docs/setup.md#claude-code-のクラウド環境) を参照する。
