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

  # 固定した配布物の cache が、破損や中断から検証済みの内容へ自己復旧すること。
  pinned-download = mkCheck "pinned-download" [ pkgs.bashInteractive pkgs.coreutils ] ''
    PINNED_DOWNLOAD_TEST_TMPDIR="$TMPDIR" bash scripts/test-pinned-download.sh
  '';

  # /etc/wsl.conf のマージが、管理外の記述を保ちつつ自分のキーだけを差し替えること。
  # 本リポジトリで唯一の非自明なテキスト処理であり、読んだだけでは確かめられない。
  wsl-conf = mkCheck "wsl-conf" [ pkgs.bashInteractive ] ''
    bash scripts/test-wsl-conf.sh
  '';

  # Cloud Setup の home/ 配置先、CODEX_HOME の fallback、backup の一回性。
  # source は読み取り専用の store にあるため、書き込み先を明示して渡す。
  cloud-home = mkCheck "cloud-home" [ pkgs.bashInteractive pkgs.coreutils pkgs.findutils ] ''
    CLOUD_HOME_TEST_TMPDIR="$TMPDIR" bash scripts/test-cloud-home.sh
  '';

  # hook や permission の JSON が壊れると設定全体が読み込まれない。
  # jq に複数ファイルを渡すと -e は最後の出力しか見ないため、1 ファイルずつ検査する。
  settings-json = mkCheck "settings-json" [ pkgs.jq ] ''
    for settings in .claude/settings.json home/.claude/settings.json; do
      jq -e 'type == "object"' "$settings" >/dev/null
    done
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
