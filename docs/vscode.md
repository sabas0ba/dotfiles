# VS Code Remote

Windows の VS Code から NixOS-WSL または開発コンテナへ直接接続する。
SSH サーバーと SSH 鍵は使用しない。

VS Code Server は通常の Linux 向けのバイナリを配布するため、Nix の toolchain だけでは
起動できない場合がある。本構成では `nix-ld` と固定済み nixpkgs のライブラリを使用する。
ライブラリと接続準備に必要なツールは `nix/packages.nix` に定義する。
追加の native extension が必要とするライブラリは、この最小構成に含まれない場合がある。

## NixOS-WSL

1. WSL 内で変更済みの dotfiles を取得し、`nix develop` に入る。
2. `make check` と `make wsl-dry` で確認し、承認後に `make wsl-switch` で適用する。
3. Windows 側の VS Code のユーザー設定で、次の設定を有効にする。
4. Windows 側の VS Code で WSL 拡張を使用し、`WSL: Connect to WSL using Distro...`
   から対象 distro を選択する。
5. WSL 内の `~/repos/<project>` を開き、統合ターミナルで `nix develop` に入る。

```json
{
  "remote.WSL.experimental.scriptLessStartup": true
}
```

WSL 拡張 `0.104.3` の設定定義で確認した、interop 無効環境向けの実験的な起動経路である。
既定の起動経路は Windows 側の拡張スクリプトを参照するため、mount を無効にした環境では
`nix-ld` の追加だけでは足りない。ユーザー設定は接続元で変更し、秘密情報を含みうる
既存の設定ファイル全体を dotfiles に取り込まない。

Windows のドライブ mount、Windows PATH の流入、Windows executable の起動を無効にする
既存設定を維持する。起点は Windows 側の VS Code とし、WSL 内から Windows の `code.exe`
を呼び出さない。Server の配置・起動が失敗した場合は、WSL 拡張の出力ログで確認する。

`nix develop` はそのシェルと子プロセスに作用する。既に動いている extension host には
環境変数が遡って反映されないため、言語拡張が使う language server の実行パスや
Nix 環境の読み込みは、各プロジェクトの設定で指定する。

## Dev Containers

`.devcontainer/devcontainer.json` は本リポジトリの `Dockerfile` を使用する。
`DOTFILES_TOOLCHAIN_PROFILE` の既定値は `default` であり、必要に応じて `software` 等へ
変更して再構築する。外部の Dev Container Features は使用しない。

Windows 側の dotfiles フォルダーを VS Code で開き、`Dev Containers: Reopen in Container`
を実行する。作業領域は named volume `dotfiles-vscode-workspaces` の `/workspaces` である。
Windows のフォルダーは build context にのみ使い、コンテナ内には bind mount しない。

初回はコンテナの統合ターミナルから、作業対象を volume 内へ取得する。

```bash
git clone https://github.com/sabas0ba/dotfiles.git /workspaces/dotfiles
```

その後、VS Code の「フォルダーを開く」で `/workspaces/dotfiles` を選ぶ。
他のプロジェクトも `/workspaces/<project>` に配置する。
volume は再構築後も保持されるため、Windows 側の checkout の変更が作業領域へ自動同期される
ことはない。ビルド時の dotfiles の snapshot は `/workspace` にあり、イメージの検証に使用する。

Server や extension host が `docker exec` 経由で起動した場合も、選択した toolchain を
`/opt/dotfiles/bin` から利用できる。ENTRYPOINT を通るかどうかに依存しない。
Docker daemon や Podman socket、SSH agent、認証情報の mount は本構成に追加しない。
VS Code 自体の認証情報共有設定は接続元で確認する。

Podman を使う場合は、Windows 側で動作する Podman CLI を VS Code の
`dev.containers.dockerPath` に設定する。Docker 互換 CLI の対応範囲は Dev Containers の版にも
依存するため、接続ログで確認する。

## 接続後の検証

本リポジトリの作業フォルダーで次を確認する。

```bash
nix develop --command scripts/check-env.sh
nix develop --command make check
```

あわせて、ファイルの編集・保存、統合ターミナル、使用する言語拡張、切断後の再接続を確認する。
コンテナでは ENTRYPOINT を通さない `docker exec <container> bash -lc 'command -v git'`
でも toolchain に到達できることを確認する。

VS Code Server と拡張は接続元の VS Code によって配置されるため、その版は flake.lock の
管理対象ではない。実機検証にはクライアントと Remote 拡張の版、接続先、結果を記録する。

`wslc` の Dev Containers 互換性は未検証である。Docker/Podman での結果を `wslc` に対する
接続保証とはしない。

## 検証記録

2026-10-14、WSL 拡張 `0.104.3` と `scriptLessStartup` を使用し、
`dotfiles-nixos` への接続と WSL 内の `repos` ディレクトリの表示を実機で確認した。
この時点で、ファイル編集・言語拡張・再接続は未検証である。

## 参照

- [NixOS-WSL: Setup VSCode Remote](https://nix-community.github.io/NixOS-WSL/how-to/vscode.html)
- [VS Code: Developing in WSL](https://code.visualstudio.com/docs/remote/wsl)
- [VS Code: Developing inside a Container](https://code.visualstudio.com/docs/devcontainers/containers)
- [VS Code: Remote Development with Linux](https://code.visualstudio.com/docs/remote/linux)
