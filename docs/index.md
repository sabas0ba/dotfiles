# dotfiles

Nix と direnv による再現性のある開発環境。同じ定義からコンテナ環境と WSL 環境も構築する。

環境に含まれるツールの一覧は [`nix/packages.nix`](https://github.com/sabas0ba/dotfiles/blob/main/nix/packages.nix) の 1 か所だけで定義する。ホストの開発シェル、`nix build` の profile、Docker イメージがすべてこれを参照するため、環境ごとに内容が食い違わない。

## 目次

- [セットアップ](setup.md) — Nix の導入から開発シェルに入るまで
- [Windows (WSL)](windows.md) — WSL 内に環境を構築する
- [使い方](usage.md) — 日常の操作、ホームディレクトリの構成、コンテナ環境
- [再現性](reproducibility.md) — 外部の成果物をどう固定し、どう検査するか
- [開発](development.md) — 本リポジトリを変更する際の手順と規約

## 環境の選び方

| 使う場所 | 手順 |
| --- | --- |
| Linux / macOS | [セットアップ](setup.md) |
| Windows | [Windows (WSL)](windows.md)。2 コマンドで完了する |
| コンテナ | [使い方](usage.md#コンテナ環境) |
| Claude Code (クラウド) | 自動。[セットアップ](setup.md#claude-code-のクラウド環境) |
| ChatGPT Codex (クラウド) | Setup script を設定。[セットアップ](setup.md#chatgpt-codex-のクラウド環境) |

いずれの環境でも、開発シェルに入る操作 (`nix develop`) とホームディレクトリの構成 (`make hm-switch`) は同一である。

## リポジトリ

<https://github.com/sabas0ba/dotfiles>
