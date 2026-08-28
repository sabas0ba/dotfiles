# `nix develop` および direnv が使用する開発シェルの定義。
#
# 本ファイルはシェルの構成のみを定義し、ツールとコマンド契約は
# nix/packages.nix に置く。Docker イメージも同じ profile を参照する。
{
  commandManifest,
  metadataPackages,
  pkgs,
  profile,
  profileEnvironment,
  profileName,
}:

pkgs.mkShellNoCC {
  name = "dotfiles-${profileName}";

  packages = profile.packages ++ metadataPackages;

  env = profile.env // {
    # 開発シェル内であることをスクリプトから判定するために使用する。
    DOTFILES_ENV = "nix-develop";

    # check-env.sh が profile 固有のコマンド契約を読む。
    DOTFILES_COMMAND_MANIFEST = commandManifest;
    DOTFILES_PROFILE_ENV = profileEnvironment;
    DOTFILES_TOOLCHAIN_PROFILE = profileName;

    # ロケールによる挙動の差異を排除する。
    LC_ALL = "C.UTF-8";
  };

  shellHook = ''
    # リポジトリのルートを基準とした PATH。scripts/ 配下を直接実行できるようにする。
    if root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
      export DOTFILES_ROOT="$root"
      export PATH="$root/scripts:$PATH"
    fi

    echo "dotfiles dev shell: ${profileName}"
    echo "  ${profile.description}"
    echo "  nixpkgs ${pkgs.lib.versions.majorMinor pkgs.lib.version}, ${pkgs.stdenv.hostPlatform.system}"
    echo "  make help: 利用可能な操作の一覧"
  '';
}
