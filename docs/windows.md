# Windows (WSL)

WSL の内部に Linux 環境を構築する。PowerShell で 2 コマンド実行すれば、開発シェルに入れる状態まで到達する。distro を登録せずコンテナで使う場合は [WSL containers (wslc)](#wsl-containers-wslc) を参照する。

この bootstrap が対象とする Windows とゲストの system は[対応範囲](index.md#対応範囲)にある。

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
| `-AdoptExisting` | — | 内容を確認済みの未管理環境を明示的に引き継ぐ |
| `-Unregister` | — | 登録を解除する (仮想ディスクごと削除される) |

各手順は既に済んでいれば飛ばすため、中断してもそのまま再実行できる。配布イメージは `.work/wsl` に保存し、sha256 が一致すれば再取得しない。

登録時には `/etc/dotfiles-wsl-bootstrap.json` に、schema、登録名、distro、配布イメージの URL・version・sha256、利用者、flake target、リポジトリを記録する。同名の WSL ディストリビューションが既にある場合はこのマーカーを完全一致で検査し、無い場合や指定と異なる場合は、利用者作成や system 構成を始める前に停止する。したがって、既存の通常利用用ディストリビューションを既定値の名前だけで取り込むことはない。

マーカーの無い既存ディストリビューションを内容確認後に引き継ぐ場合だけ、`-AdoptExisting` を指定する。マーカーが既にあり、内容が異なる場合は上書きしない。別の `-Name` を使うか、対象を確認して解除する。

```powershell
powershell -ExecutionPolicy Bypass -File scripts\wsl-bootstrap.ps1 `
  -Name NixOS -AdoptExisting
```

`-Unregister` も管理マーカーを検査する。未管理の同名ディストリビューションは削除しないため、その場合は対象を別途確認した上で `wsl --unregister <名前>` を直接実行する。

リポジトリは `-Ref` を取得時に完全な commit SHA へ解決し、detached HEAD で配置する。解決した ref と SHA はリポジトリローカルの Git config に記録する。再実行時は origin URL、未コミット・未追跡変更、前回記録した HEAD を検査してから取得する。origin が異なる、変更が残る、または管理済み checkout の HEAD が外部で変わっている場合は停止する。未管理の既存 checkout の HEAD だけが指定 ref と異なる場合は、内容確認後に `-AdoptExisting` で引き継げる。

## 経路の選択

| | NixOS-WSL | Ubuntu LTS |
| --- | --- | --- |
| system の管理 | [`nix/wsl.nix`](https://github.com/sabas0ba/dotfiles/blob/main/nix/wsl.nix) により宣言的 | スクリプトを適用した結果として残る |
| flake の入力 | `nixos-wsl` を使用 | 使用しない |
| Nix の導入 | 不要 (イメージに含まれる) | bootstrap が [同じ配布物](setup.md#nix-の導入) を入れる |
| sudo | NixOS-WSL の既定 (パスワード不要) | `/etc/sudoers.d/nixos` に NOPASSWD を置く |

NixOS-WSL は system 層まで本リポジトリの管理下に入る。Ubuntu は flake の入力を増やさずに済む。どちらでも、対応する開発シェルと home-manager target は共通である。

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

## WSL containers (wslc)

WSL distro を登録せず、`Dockerfile` から構築したコンテナで開発シェルを使う経路である。`wslc.exe` は WSL に同梱されており、Docker Desktop や別のコンテナエンジンを導入しない。WSL 2.9.3 で preview、3.0.1 で GA となった ([WSL 3.0.1 release notes](https://github.com/microsoft/WSL/releases/tag/3.0.1)、[WSL containers](https://learn.microsoft.com/windows/wsl/wsl-container))。`wslc version` で利用可能かを確認する。

```powershell
cd $HOME\repos\dotfiles
wslc build -f Dockerfile -t dotfiles-dev .
wslc build -f Dockerfile --build-arg DOTFILES_TOOLCHAIN_PROFILE=software -t dotfiles-software .
wslc run --rm dotfiles-dev scripts/check-wsl-isolation.sh --force
wslc run --rm -it dotfiles-dev
wslc run --rm --network none dotfiles-dev make check
```

イメージは [コンテナ環境](usage.md#コンテナ環境) と同じ `Dockerfile` から構築するため、内容は Docker の経路と一致する。build 時に checkout を build context として取り込み、実行時は Windows の path を `-v` でマウントしない。

build context となる checkout の改行は LF である必要がある。CRLF の場合、`nix/` のシェル断片が CRLF のまま derivation に入り、`dotfiles-toolchain-info` の構築が構文エラーで失敗する。`.gitattributes` が LF を指定するため、これを含む revision を新規に clone した場合は対処が要らない。`.gitattributes` の追加より前に `core.autocrlf=true` で取得した checkout は CRLF のまま残るため、clone し直す。状態は次で確認でき、`w/lf` であれば問題ない。

```powershell
git ls-files --eol nix/packages.nix
```

使用を始める前に、コンテナ内で `scripts/check-wsl-isolation.sh --force` が成功することを確認する。[Windows 側からの隔離](#windows-側からの隔離) と同じ項目 (ドライブと Windows 側 filesystem のマウント、Windows の実行ファイルのハンドラ、PATH の流入) を検査する。`--force` は WSL の判定に関わらず検査させる指定であり、判定が外れて検査が省略されるのを防ぐ。検査が失敗した場合は、この経路で作業しない。

| | WSL distro | wslc |
| --- | --- | --- |
| 実行単位 | 登録した distro | build したイメージから起動するコンテナ |
| 構成の適用 | `scripts/wsl-bootstrap.ps1` と `make wsl-switch` | `wslc build` |
| Windows 側からの隔離 | `/etc/wsl.conf` で mount、PATH、実行ファイルを無効化し、`make check` が検査する | distro とは別の VM で動作し、`/etc/wsl.conf` は及ばない。`scripts/check-wsl-isolation.sh --force` で確認する |
| 状態の保持 | distro の仮想ディスク | `--rm` を付けなければコンテナに残る |

wslc の経路は CI で検証していない。実機では WSL 3.0.1.0 (Windows 10.0.26200.9445、x64) で次を確認した。

- `wslc build` が digest で固定したベースイメージから完了する (default、software、containers、hdl、browser、full の全 profile)
- `--network none` が使え、インターフェースが `lo` のみの状態で `make check` が成功する (同上の全 profile)
- `-v` を指定しないコンテナで `scripts/check-wsl-isolation.sh --force` が成功する。Windows のドライブ、9p / drvfs / virtiofs の mount、`binfmt_misc` の handler はいずれも存在しない
- `-v` で Windows の path を渡すと、device 名 `drvfs`、filesystem `virtiofs` で mount される。検査はこれを検出して失敗する

コンテナの kernel は `microsoft-standard-WSL2` を名乗るため、この版では `--force` が無くても WSL と判定される。版によって変わりうるため、手順では `--force` を付ける。

対応する Windows の最低 build は確認できていない。Microsoft の資料が wslc の要件として記載するのは WSL 2.9.3 以上であることだけで、Windows の build は記載が無い ([WSL containers](https://learn.microsoft.com/windows/wsl/wsl-container)、[Get started with containers on WSL](https://learn.microsoft.com/windows/wsl/tutorials/wsl-containers))。

既定の session は同じ利用者の他の作業と共有される。`wslc list --all` や `wslc images` には他の作業のコンテナとイメージも現れるため、操作は自分が作成した名前に限る。

`wslc container prune`、`wslc image prune`、`wsl --shutdown` は、他のコンテナや distro にも作用するため使わない。不要になったものは `wslc container remove <名前>`、`wslc image remove dotfiles-dev` のように対象を指定して削除する。

## 構築後の操作

```bash
make wsl-dry        # system の適用内容の確認
make wsl-switch     # system の構成を適用する (NixOS のみ)
make wsl-isolation  # 隔離の検査のみ
```

以降の操作は[使い方](usage.md)を参照する。利用者名が `flake.nix` の `homeTargets` にあるため `HM_TARGET` の指定は要らない。

`/etc/wsl.conf` を変更したときは、当該ディストリビューションを停止して反映させる。`wsl --shutdown` は他のディストリビューションも止めるため使わない。

```powershell
wsl --terminate NixOS
```

`nixos-rebuild` は systemd の user unit の再読込に失敗して警告を出す。WSL では対話セッションの外に user session が無いためで、system 側の切り替えには影響しない。

## 構築の流れ

bootstrap が行うことは以下である。

1. 配布イメージを取得し、固定した sha256 と照合する
2. `wsl --install --from-file` で登録する
3. 利用者を用意し、リポジトリの origin と状態を検査して、ref を commit SHA へ解決した detached HEAD を配置する
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
