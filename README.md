# dotfiles

Nix と direnv による再現性のある開発環境。同じ定義からコンテナ環境と WSL 環境も構築する。

ドキュメント: <https://sabas0ba.github.io/dotfiles/>

環境に含まれるツールの一覧は [`nix/packages.nix`](nix/packages.nix) の 1 か所だけで定義する。ホストの開発シェル、`nix build` の profile、Docker イメージがすべてこれを参照するため、環境ごとに内容が食い違わない。

## はじめに

Linux / macOS:

```bash
git clone https://github.com/sabas0ba/dotfiles.git ~/repos/dotfiles
cd ~/repos/dotfiles
nix develop
```

Nix の導入から行う場合は [セットアップ](docs/setup.md) を参照する。

Windows (WSL 内に構築する):

```powershell
git clone https://github.com/sabas0ba/dotfiles.git $HOME\repos\dotfiles
powershell -ExecutionPolicy Bypass -File $HOME\repos\dotfiles\scripts\wsl-bootstrap.ps1
```

詳細は [Windows (WSL)](docs/windows.md) を参照する。

## ドキュメント

- [セットアップ](docs/setup.md) — Nix の導入から開発シェルに入るまで
- [Windows (WSL)](docs/windows.md) — WSL 内に環境を構築する
- [使い方](docs/usage.md) — 日常の操作、ホームディレクトリの構成、コンテナ環境
- [再現性](docs/reproducibility.md) — 外部の成果物をどう固定し、どう検査するか
- [開発](docs/development.md) — 本リポジトリを変更する際の手順と規約

`docs/` の内容をそのまま GitHub Pages で公開している。

## ライセンス

[LICENSE](LICENSE) を参照する。
