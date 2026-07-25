# `nix flake check` (= `make check`) が走らせる検査。
#
# CI でもローカルでも Docker の中でも、まったく同じ derivation が走る。
{ pkgs, src }:

let
  # 検査ごとに使い回す薄いヘルパー。
  # 成功したら $out に空ファイルを作るだけの derivation を作る。
  mkCheck =
    name: deps: script:
    pkgs.runCommandLocal "check-${name}" { nativeBuildInputs = deps; } ''
      cd ${src}
      ${script}
      touch "$out"
    '';
in
{
  # Nix コードが nixfmt で整形済みかどうか。
  nixfmt = mkCheck "nixfmt" [ pkgs.nixfmt ] ''
    nixfmt --check .
  '';

  # Nix コードの lint。
  statix = mkCheck "statix" [ pkgs.statix ] ''
    statix check .
  '';

  # 使われていない let 束縛・引数の検出。
  deadnix = mkCheck "deadnix" [ pkgs.deadnix ] ''
    deadnix --fail .
  '';

  # シェルスクリプトの静的解析。.envrc も bash として検査する。
  shellcheck = mkCheck "shellcheck" [ pkgs.shellcheck ] ''
    shellcheck scripts/*.sh
    shellcheck --shell=bash .envrc
  '';

  # シェルスクリプトが shfmt で整形済みかどうか (インデント 2 / case もインデント)。
  shfmt = mkCheck "shfmt" [ pkgs.shfmt ] ''
    shfmt --diff --indent 2 --case-indent scripts/*.sh
  '';
}
