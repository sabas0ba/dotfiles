# dotfiles

Nix と direnv による再現性のある開発環境。同じ定義からコンテナ環境と WSL 環境も構築する。

環境に含まれるツール、コマンド契約、用途別 profile は [`nix/packages.nix`](https://github.com/sabas0ba/dotfiles/blob/main/nix/packages.nix) の 1 か所だけで定義する。ホストの開発シェル、`nix build` の profile、Docker イメージがすべてこれを参照するため、環境ごとに内容が食い違わない。既定環境は軽量に保ち、言語、コンテナ、HDL、Playwright は[用途別に選択する](usage.md#toolchain-profile)。

## 目次

- [セットアップ](setup.md) — Nix の導入から開発シェルに入るまで
- [Windows (WSL)](windows.md) — WSL 内に環境を構築する
- [使い方](usage.md) — 日常の操作、ホームディレクトリの構成、コンテナ環境
- [再現性](reproducibility.md) — 外部の成果物をどう固定し、どう検査するか
- [開発](development.md) — 本リポジトリを変更する際の手順と規約

## 対応範囲

表の system は、Nix を実行する環境を指す。WSL とクラウド環境では、Windows や利用者のローカル環境ではなくゲスト側の system である。「対応」は本リポジトリにその入口と定義があること、「未対応」は入口または定義がないこと、「対象外」はその system で使用する機能ではないことを示す。「未検証」は対応を保証しない。CI で継続的に検証している system は `x86_64-linux` である。

| 機能・入口 | `x86_64-linux` | `aarch64-linux` | `x86_64-darwin` | `aarch64-darwin` | 手順 |
| --- | --- | --- | --- | --- | --- |
| 開発シェル (`nix develop`) | 対応 | 対応 | 対応 | 対応 | [セットアップ](setup.md#環境に入る) |
| 固定済みの Nix 導入例 | 対応 | 未対応 | 未対応 | 未対応 | [Nix の導入](setup.md#nix-の導入) |
| home-manager (`make hm-*`) | 対応 (定義済み target のみ) | 未対応 (target 未定義) | 未対応 (target 未定義) | 未対応 (target 未定義) | [ホームディレクトリの構成](usage.md#ホームディレクトリの構成) |
| Windows からの WSL bootstrap | 対応 (x64 Windows) | 未対応 | 対象外 | 対象外 | [Windows (WSL)](windows.md) |
| Docker イメージ | 対応 (CI 検証済み) | 未検証 | 対象外 | 対象外 | [コンテナ環境](usage.md#コンテナ環境) |
| Claude Code / ChatGPT Codex (`cloud-setup.sh`) | 対応 | 未対応 | 対象外 | 対象外 | [クラウド環境](setup.md#claude-code-のクラウド環境) |

開発シェルは `flake.nix` が 4 つの system に出力する。これとは別に、現在定義されている home-manager target はすべて `x86_64-linux` である。該当する target がない system では `make hm-switch` を実行できず、先に `homeTargets` の追加が必要となる。

WSL bootstrap は x64 Windows 上の `x86_64-linux` ゲストを対象とする。`cloud-setup.sh` も Ubuntu の `x86_64-linux` 実行環境を対象とし、ほかの CPU architecture では Nix の取得前に停止する。未対応の system でも開発シェルに対応していれば、別途 Nix を導入して `nix develop` を利用できる。

## リポジトリ

<https://github.com/sabas0ba/dotfiles>
