# `nix develop` および direnv が使用する開発シェルの定義。
#
# 本ファイルはシェルの構成のみを定義し、ツールの一覧は nix/packages.nix に置く。
# Docker イメージも同一の packages.nix を参照するため、内容は常に一致する。
{ pkgs }:

pkgs.mkShellNoCC {
  name = "dotfiles";

  packages = import ./packages.nix { inherit pkgs; };

  env = {
    # 開発シェル内であることをスクリプトから判定するために使用する。
    DOTFILES_ENV = "nix-develop";

    # ロケールによる挙動の差異を排除する。
    LC_ALL = "C.UTF-8";
  };

  shellHook = ''
    # リポジトリのルートを基準とした PATH。scripts/ 配下を直接実行できるようにする。
    if root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
      export DOTFILES_ROOT="$root"
      export PATH="$root/scripts:$PATH"
    fi

    echo "dotfiles dev shell (nixpkgs ${pkgs.lib.versions.majorMinor pkgs.lib.version}, ${pkgs.stdenv.hostPlatform.system})"
    echo "  make help: 利用可能な操作の一覧"
  '';
}
