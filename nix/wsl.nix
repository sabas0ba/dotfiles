# WSL 上で動作させる NixOS の system 構成。
#
# `nixos-rebuild switch --flake .#wsl` (make wsl-switch) から適用する。
#
# 本ファイルの対象は WSL 固有の設定と、リポジトリを取得して開発シェルに入るまでに
# 要る最小限のツールに限る。開発用ツール一式は nix/packages.nix が単一情報源であり、
# 開発シェル経由で取得する。system に入れると同じ一覧が 2 か所に存在することになる。
# ホームディレクトリの内容は home-manager (nix/home.nix) が持つ。
{ pkgs, ... }:

{
  wsl = {
    enable = true;

    # NixOS-WSL の既定値と同じ。flake.nix の homeTargets に同名の対象がある。
    defaultUser = "nixos";

    # --- Windows 側からの隔離 -------------------------------------------------
    #
    # 既定では /mnt 以下に Windows のドライブが見え、Windows の PATH が流入し、
    # Windows の実行ファイルを起動できる。この状態では、当環境で動作するエージェントや
    # スクリプトが、ホスト側のシステムファイルや、認証済みの CLI (gh / az / aws /
    # gcloud 等) に到達しうる。規約による禁止ではなく到達経路自体を断つ。
    #
    # 解除する場合は本ファイルを変更して commit する。手元だけで /etc/wsl.conf を
    # 書き換えても次の switch で元に戻る。実際に隔離されているかは
    # scripts/check-wsl-isolation.sh が検査し、make check に含まれる。
    #
    # wslConf は WSL 側の機構 (/etc/wsl.conf) を、interop は NixOS-WSL 側の機構
    # (binfmt_misc の登録と PATH の構成) を制御する。別の機構であるため両方を指定する。
    wslConf = {
      automount.enabled = false;
      interop = {
        enabled = false;
        appendWindowsPath = false;
      };
    };

    interop = {
      register = false;
      includePath = false;
    };
  };

  # flake 形式の構成を扱うために必要。初回の switch は本設定が未適用の状態から
  # 実行するため、README の手順では NIX_CONFIG で同等の指定を与えている。
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # リポジトリの取得と direnv の利用に要るもののみ。他は開発シェルから取得する。
  environment.systemPackages = [
    pkgs.git
  ];

  # 構成の互換性の基準となる NixOS のリリース。追従したい場合を除いて変更しない。
  system.stateVersion = "26.05";
}
