# CLAUDE.md

@AGENTS.md

Claude Code 用の互換入口。上記の `AGENTS.md` を本リポジトリの agent 指示として読み込む。開発規約の原本は [docs/development.md](docs/development.md) である。

Claude Code のクラウド環境では SessionStart hook が `scripts/cloud-setup.sh` を実行する。`scripts/check-env.sh` が失敗した場合は hook の実行結果を確認する。詳細は [docs/setup.md](docs/setup.md#claude-code-のクラウド環境) を参照する。
