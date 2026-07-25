{
  description = "dotfiles: Nix + direnv で閉じた再現性のある開発環境";

  inputs = {
    # nixpkgs は「必ず」リビジョン固定で参照する。
    # ブランチ名 (nixos-26.05 など) で参照すると flake.lock が無い環境で
    # 取得結果がブレるため、rev をここに直書きしている。
    # 更新は `make update` (= nix flake update) ではなく `make bump REV=<rev>` で行い、
    # flake.lock も同じコミットで更新すること。
    nixpkgs.url = "github:NixOS/nixpkgs/597283ad8aa0b331c788e97c4c262d58877074ef"; # nixos-26.05
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      forAllSystems =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          f (
            import nixpkgs {
              inherit system;
              config = { };
              overlays = [ ];
            }
          )
        );
    in
    {
      # `nix develop` / direnv の `use flake` が使う開発シェル。
      devShells = forAllSystems (pkgs: {
        default = import ./nix/devshell.nix { inherit pkgs; };
      });

      # ツール一式を 1 つの profile にまとめたもの。
      # Dockerfile やホストへの `nix profile install` から使える。
      packages = forAllSystems (pkgs: {
        default = pkgs.buildEnv {
          name = "dotfiles-toolchain";
          paths = import ./nix/packages.nix { inherit pkgs; };
        };
      });

      # `nix flake check` / `make check` で走る検査。
      checks = forAllSystems (
        pkgs:
        import ./nix/checks.nix {
          inherit pkgs;
          src = self;
        }
      );

      # `nix fmt` で使うフォーマッタ。
      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
