{
  description = "dotfiles: Nix と direnv による再現性のある開発環境";

  inputs = {
    # nixpkgs はリビジョンで固定する。ブランチ名 (nixos-26.05 等) による参照は
    # flake.lock が無い環境で取得結果が変動するため使用しない。
    # 更新は `make bump REV=<rev>` で行い、flake.lock を同一のコミットに含める。
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
      # `nix develop` および direnv の `use flake` が使用する開発シェル。
      devShells = forAllSystems (pkgs: {
        default = import ./nix/devshell.nix { inherit pkgs; };
      });

      # ツール一式を 1 つの profile にまとめたもの。Dockerfile およびホストへの
      # `nix profile install` から使用する。
      packages = forAllSystems (pkgs: {
        default = pkgs.buildEnv {
          name = "dotfiles-toolchain";
          paths = import ./nix/packages.nix { inherit pkgs; };
        };
      });

      # `nix flake check` および `make check` が実行する検査。
      checks = forAllSystems (
        pkgs:
        import ./nix/checks.nix {
          inherit pkgs;
          src = self;
        }
      );

      # `nix fmt` が使用するフォーマッタ。
      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
