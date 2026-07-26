{
  description = "dotfiles: Nix と direnv による再現性のある開発環境";

  inputs = {
    # 入力はリビジョンで固定する。ブランチ名 (nixos-26.05 等) による参照は
    # flake.lock が無い環境で取得結果が変動するため使用しない。
    # 更新は `make bump REV=<rev>` で行い、flake.lock を同一のコミットに含める。
    nixpkgs.url = "github:NixOS/nixpkgs/597283ad8aa0b331c788e97c4c262d58877074ef"; # nixos-26.05

    # ホームディレクトリの設定を宣言的に管理する。nixpkgs のリリースに対応する
    # ブランチ (release-26.05) のリビジョンで固定する。
    home-manager = {
      url = "github:nix-community/home-manager/4ce190229c73d44536caa7072f6308fb2d8feeb3"; # release-26.05
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
    }:
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

      # home-manager の適用対象。マシンを追加する場合はここに追記する。
      # 名前は `make hm-switch HM_TARGET=<name>` で指定するものと一致する。
      homeTargets = {
        sabas0ba = {
          system = "x86_64-linux";
          homeDirectory = "/home/sabas0ba";
        };
      };

      mkHomeConfiguration =
        username:
        {
          system,
          homeDirectory,
        }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs { inherit system; };
          modules = [ ./nix/home.nix ];
          extraSpecialArgs = { inherit username homeDirectory; };
        };
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

      # ホームディレクトリの構成。`make hm-switch` から適用する。
      homeConfigurations = nixpkgs.lib.mapAttrs mkHomeConfiguration homeTargets;

      # `nix flake check` および `make check` が実行する検査。
      checks = forAllSystems (
        pkgs:
        import ./nix/checks.nix {
          inherit pkgs;
          src = self;
        }
      );

      # `nix fmt` が使用するフォーマッタ。
      #
      # nixfmt を直接指定してはならない。`nix fmt` は引数無しでフォーマッタを起動する
      # ことがあり、その場合 nixfmt は標準入力を読もうとして失敗する。対象が
      # 与えられなかったときに対象を補うラッパを噛ませる。
      formatter = forAllSystems (
        pkgs:
        pkgs.writeShellApplication {
          name = "dotfiles-fmt";
          runtimeInputs = [
            pkgs.nixfmt
            pkgs.findutils
          ];
          text = ''
            if [ "$#" -gt 0 ]; then
              nixfmt "$@"
              exit 0
            fi

            # 対象が与えられない場合はリポジトリ配下の *.nix を対象とする。
            # nixfmt にディレクトリを渡す方式は非推奨のため、ファイルを列挙する。
            find . -type f -name '*.nix' -exec nixfmt {} +
          '';
        }
      );
    };
}
