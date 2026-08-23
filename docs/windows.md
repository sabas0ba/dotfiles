# Windows (WSL)

WSL の内部に Linux 環境を構築する。PowerShell で 2 コマンド実行すれば、開発シェルに入れる状態まで到達する。

```powershell
git clone https://github.com/sabas0ba/dotfiles.git $HOME\repos\dotfiles
powershell -ExecutionPolicy Bypass -File $HOME\repos\dotfiles\scripts\wsl-bootstrap.ps1
```

あとは `wsl -d NixOS` で入るだけである。管理者権限は要らない。

WSL 本体は 2.4.4 以降が必要である。`wsl --version` で確認し、古ければ `wsl --update` を実行する。WSL 自体が未導入なら `wsl --install --no-distribution` で有効化する。

## 引数

既定のままで本リポジトリの環境が構築される。

| 引数 | 既定 | 用途 |
| --- | --- | --- |
| `-Distro` | `nixos` | `nixos` または `ubuntu` |
| `-Name` | `NixOS` / `Ubuntu-24.04` | WSL に登録する名前 |
| `-Location` | wsl の既定 | 仮想ディスクの配置先 |
| `-RepoUrl` | 本リポジトリ | 取得するリポジトリ |
| `-Ref` | `main` | 取得する ref |
| `-User` | `nixos` | WSL 上の利用者 |
| `-FlakeTarget` | `wsl` | 適用する `nixosConfigurations` の名前 |
| `-Unregister` | — | 登録を解除する (仮想ディスクごと削除される) |

各手順は既に済んでいれば飛ばすため、中断してもそのまま再実行できる。配布イメージは `.work/wsl` に保存し、sha256 が一致すれば再取得しない。

## 経路の選択

| | NixOS-WSL | Ubuntu LTS |
| --- | --- | --- |
| system の管理 | [`nix/wsl.nix`](https://github.com/sabas0ba/dotfiles/blob/main/nix/wsl.nix) により宣言的 | スクリプトを適用した結果として残る |
| flake の入力 | `nixos-wsl` を使用 | 使用しない |
| Nix の導入 | 不要 (イメージに含まれる) | bootstrap が [同じ配布物](setup.md#nix-の導入) を入れる |
| sudo | NixOS-WSL の既定 (パスワード不要) | `/etc/sudoers.d/nixos` に NOPASSWD を置く |

NixOS-WSL は system 層まで本リポジトリの管理下に入る。Ubuntu は flake の入力を増やさずに済む。どちらでも開発シェルとホームディレクトリの構成は他の環境と同一である。

sudo にパスワードを設けないのは、WSL では `wsl.exe -u root` で無条件に root になれるため、パスワードが境界として機能しないことによる。

## Windows 側からの隔離

構築した環境は、既定の WSL と違って Windows 側から隔離してある。

- Windows のドライブを `/mnt` 以下にマウントしない
- Windows の PATH を流入させない
- Windows の実行ファイルを起動できない

当環境で動くエージェントやスクリプトが、ホストのシステムファイルや認証済みの CLI (gh / az / aws / gcloud 等) に到達しないようにするためである。規約による禁止ではなく、到達経路そのものを断つ。

成立しているかは `make check` が検査する。検査の定義は [`scripts/check-wsl-isolation.sh`](https://github.com/sabas0ba/dotfiles/blob/main/scripts/check-wsl-isolation.sh) の 1 か所にある。

設定の実体は経路で異なる。NixOS では `nix/wsl.nix` が `/etc/wsl.conf` を生成する (Nix store への symlink であり書き換えられない)。Ubuntu では [`scripts/wsl-provision.sh`](https://github.com/sabas0ba/dotfiles/blob/main/scripts/wsl-provision.sh) が書く。このとき既存の内容は保持し、自分が管理するキーだけを差し替える。イメージが出荷時に持つ `[boot] systemd` 等を消すと動かなくなるためで、この処理は [`scripts/test-wsl-conf.sh`](https://github.com/sabas0ba/dotfiles/blob/main/scripts/test-wsl-conf.sh) が検査する。

隔離を解除する場合は、手元の `/etc/wsl.conf` を書き換えるのではなく上記の定義を変更して commit する。NixOS では手元の変更は次の `make wsl-switch` で元に戻る。Windows のファイルを扱う必要が生じたときは、隔離を解除せず対象を個別に持ち込む。

`/mnt` の下にドライブ文字のディレクトリ (`/mnt/c` 等) が空のまま残ることがある。登録の直後、隔離が成立する前に WSL が作ったもので、マウントはされていない。

## 改変版を併存させる

同じ環境の改変版を、別のディストリビューションとして登録できる。登録名に加えて、リポジトリとその中で参照する対象を分ける。

```powershell
powershell -ExecutionPolicy Bypass -File scripts\wsl-bootstrap.ps1 `
  -Name NixOS-alt -RepoUrl https://github.com/example/dotfiles-alt.git `
  -User alt -FlakeTarget wsl-alt
```

改変版のリポジトリには、`-User` と同名の対象が `flake.nix` の `homeTargets` に、`-FlakeTarget` と同名の対象が `nixosConfigurations` に必要である。ホームディレクトリの構成を分ける必要がなければ `-User` は省略してよい。配布イメージは共有するため、2 つ目以降で取得は発生しない。

## 構築後の操作

```bash
make wsl-dry        # system の適用内容の確認
make wsl-switch     # system の構成を適用する (NixOS のみ)
make wsl-isolation  # 隔離の検査のみ
```

以降は他の Linux 環境と同一である ([使い方](usage.md) を参照)。利用者名が `flake.nix` の `homeTargets` にあるため `HM_TARGET` の指定は要らない。

`/etc/wsl.conf` を変更したときは、当該ディストリビューションを停止して反映させる。`wsl --shutdown` は他のディストリビューションも止めるため使わない。

```powershell
wsl --terminate NixOS
```

`nixos-rebuild` は systemd の user unit の再読込に失敗して警告を出す。WSL では対話セッションの外に user session が無いためで、system 側の切り替えには影響しない。

## 構築の流れ

bootstrap が行うことは以下である。

1. 配布イメージを取得し、固定した sha256 と照合する
2. `wsl --install --from-file` で登録する
3. 利用者を用意し、リポジトリを取得する
4. `scripts/wsl-provision.sh` の段 system を root で実行する
5. 反映のためディストリビューションを停止する
6. `scripts/wsl-provision.sh` の段 home を利用者で実行する (`make check` と `make hm-switch`)

段が 2 つに分かれるのは、`/etc/wsl.conf` が起動時にしか読まれず、間に再起動が必要なためである。隔離が成立するのは段 system の完了時で、それより前に動くのは利用者の作成とリポジトリの取得だけである。どちらも Windows 側を参照しないため、利用者が対話セッションに入る時点では隔離が成立している。

provision は単独でも再実行できる。構築が途中で失敗した場合や、構成を変更したあとに使う。

```bash
sudo scripts/wsl-provision.sh system nixos
scripts/wsl-provision.sh home nixos
```

---

[目次に戻る](index.md)
