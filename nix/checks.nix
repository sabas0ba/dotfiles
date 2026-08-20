# `nix flake check` (`make check`) が実行する検査。
#
# ローカル、CI、コンテナのいずれでも同一の derivation が実行される。
{ pkgs, src }:

let
  # 各検査で共通に使用するヘルパー。検査が成功した場合のみ $out を生成する。
  mkCheck =
    name: deps: script:
    pkgs.runCommandLocal "check-${name}" { nativeBuildInputs = deps; } ''
      cd ${src}
      ${script}
      touch "$out"
    '';
in
{
  # Nix コードが nixfmt で整形済みであること。
  # nixfmt にディレクトリを渡す方式は非推奨のため、ファイルを列挙する。
  nixfmt = mkCheck "nixfmt" [ pkgs.nixfmt pkgs.findutils ] ''
    find . -type f -name '*.nix' -exec nixfmt --check {} +
  '';

  # Nix コードの静的解析。
  statix = mkCheck "statix" [ pkgs.statix ] ''
    statix check .
  '';

  # 未使用の let 束縛および関数引数の検出。
  deadnix = mkCheck "deadnix" [ pkgs.deadnix ] ''
    deadnix --fail .
  '';

  # flake.nix の入力と flake.lock の整合。
  # 入力がブランチ名で参照されている場合、nix はこれを正常として扱うため、この検査が
  # 無ければ固定漏れが通過する。ネットワークは使用しない。
  lock = mkCheck "lock" [ pkgs.jq ] ''
    bash scripts/check-lock.sh
  '';

  # 外部の成果物 (ベースイメージ、GitHub Actions、ランナー、Nix インストーラ) が
  # 一意に固定されていること。タグのみの参照は固定とみなさない。
  pins = mkCheck "pins" [ pkgs.gnugrep pkgs.findutils ] ''
    bash scripts/check-pins.sh
  '';

  # シェルスクリプトの静的解析。.envrc も bash として検査する。
  shellcheck = mkCheck "shellcheck" [ pkgs.shellcheck ] ''
    shellcheck scripts/*.sh
    shellcheck --shell=bash .envrc
  '';

  # シェルスクリプトが shfmt で整形済みであること (インデント 2、case もインデント)。
  shfmt = mkCheck "shfmt" [ pkgs.shfmt ] ''
    shfmt --diff --indent 2 --case-indent scripts/*.sh
  '';
}
