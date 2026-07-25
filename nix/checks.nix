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
  nixfmt = mkCheck "nixfmt" [ pkgs.nixfmt ] ''
    nixfmt --check .
  '';

  # Nix コードの静的解析。
  statix = mkCheck "statix" [ pkgs.statix ] ''
    statix check .
  '';

  # 未使用の let 束縛および関数引数の検出。
  deadnix = mkCheck "deadnix" [ pkgs.deadnix ] ''
    deadnix --fail .
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
