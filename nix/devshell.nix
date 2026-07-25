# `nix develop` / direnv が入る開発シェル。
#
# ここでは「シェルの形」だけを定義し、ツールの一覧は nix/packages.nix に置く。
# Docker イメージも同じ packages.nix を使うので、中身は常に一致する。
{ pkgs }:

pkgs.mkShellNoCC {
  name = "dotfiles";

  packages = import ./packages.nix { inherit pkgs; };

  env = {
    # このシェルの中にいることをスクリプトから判定できるようにする。
    DOTFILES_ENV = "nix-develop";

    # ロケール依存で挙動が変わらないように固定する。
    LC_ALL = "C.UTF-8";
  };

  shellHook = ''
    # リポジトリのルートを基準にした PATH。scripts/ 配下を直接叩けるようにする。
    if root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
      export DOTFILES_ROOT="$root"
      export PATH="$root/scripts:$PATH"
    fi

    echo "dotfiles dev shell (nixpkgs ${pkgs.lib.versions.majorMinor pkgs.lib.version}, ${pkgs.stdenv.hostPlatform.system})"
    echo "  make help  … 使えるコマンド一覧"
  '';
}
