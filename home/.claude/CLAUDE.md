# CLAUDE.md

@~/.codex/AGENTS.md

Claude Code 用の互換入口。上記の `~/.codex/AGENTS.md` を利用者共通の作業規約として読み込む。対象 repository の `CLAUDE.md` から、その repository の `AGENTS.md` も読み込む。

管理元は [sabas0ba/dotfiles](https://github.com/sabas0ba/dotfiles) である。作業中に管理元や配置済みファイルを自動更新しない。更新が必要な場合は差分と配置先を示して許可を得る。

`~/.claude/settings.json` の deny / ask は Claude Code が tool 実行前に行う補助検査であり、OS level の強制ではなく、shell から起動した child process には及ばない。到達経路の隔離と `~/.codex/AGENTS.md` の規約を優先する。
