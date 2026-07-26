# CLAUDE.md

Claude Code が本リポジトリで作業する際の補足。

本リポジトリの規約 (構成、変更手順、コーディング規約、コミット、禁止事項) は
[README.md](README.md) に定義してある。これらは人間の作業者にも同様に適用されるため、
本ファイルには重複して記述しない。README.md を参照すること。

利用者全体の共通規約は `home/.claude/CLAUDE.md` (配置先 `~/.claude/CLAUDE.md`) に
ある。

以下は、エージェントが作業する際に特に注意を要する事項のみを記述する。

## 作業前の確認

作業は開発シェルの内部で行う。開始時に確認すること。

```bash
scripts/check-env.sh   # DOTFILES_ENV=nix-develop であれば開発シェル内
```

開発シェルの外にいる場合は `nix develop` (direnv 導入済みであれば `direnv allow`)
で入る。ツールを開発シェルの外から導入しない。

## 確認を要する操作

以下は影響が利用者の環境に及ぶため、実行前に対象を提示し、承認を得ること。

- `make stow` によるホームディレクトリへの配置。先に `make stow-dry` の結果を提示する
- 依存の追加 (flake の入力、`nix/packages.nix` のパッケージ、GitHub Actions)。
  追加する場合はリビジョンまたはダイジェストで固定する

## 単一情報源

`nix/packages.nix` は開発シェル、`nix build` の profile、Docker イメージの 3 つから
参照される。ツールの追加は本ファイルのみを編集する。`Dockerfile` にツール名を追記
した場合、定義が重複し不整合が生じる。

## 変更後の検証

`make check` を通すこと。`Dockerfile` または `nix/` を変更した場合は
`make docker-check` も実行する。検査を通過させるために検査自体を削除しない。
