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

    # NixOS を WSL のディストリビューションとして動作させるモジュール。nixpkgs の
    # リリースに対応するブランチ (release-26.05) のタグが指すリビジョンで固定する。
    #
    # flake-compat は上流が default.nix / shell.nix の互換のためだけに持つ入力であり、
    # モジュールの評価には使用しない。ブランチ参照のまま flake.lock に残ると
    # scripts/check-lock.sh の固定の検査に反するため、follows = "" で取り除く。
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/add6b01c7ca72240046b5d541a74845423f1ee35"; # 2605.7.2
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-compat.follows = "";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      nixos-wsl,
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

      mkToolchainOutputs =
        pkgs: profileName: profile:
        let
          commandManifestPackage = pkgs.writeTextDir "share/dotfiles/required-commands" ''
            ${pkgs.lib.concatStringsSep "\n" profile.commands}
          '';
          commandManifest = "${commandManifestPackage}/share/dotfiles/required-commands";

          profileEnvironmentValues = profile.env // {
            DOTFILES_COMMAND_MANIFEST = commandManifest;
            DOTFILES_TOOLCHAIN_PROFILE = profileName;
          };
          environmentLines = pkgs.lib.mapAttrsToList (
            name: value: "export ${name}=${pkgs.lib.escapeShellArg value}"
          ) profileEnvironmentValues;
          profileEnvironmentPackage = pkgs.writeTextDir "share/dotfiles/environment" ''
            # shellcheck shell=sh
            ${pkgs.lib.concatStringsSep "\n" environmentLines}
          '';
          profileEnvironment = "${profileEnvironmentPackage}/share/dotfiles/environment";

          toolchainInfo = pkgs.writeShellApplication {
            name = "dotfiles-toolchain-info";
            runtimeInputs = [ pkgs.coreutils ];
            text = ''
              case "''${1:-}" in
                name)
                  printf '%s\n' ${pkgs.lib.escapeShellArg profileName}
                  ;;
                commands)
                  cat ${pkgs.lib.escapeShellArg commandManifest}
                  ;;
                environment)
                  cat ${pkgs.lib.escapeShellArg profileEnvironment}
                  ;;
                environment-file)
                  printf '%s\n' ${pkgs.lib.escapeShellArg profileEnvironment}
                  ;;
                *)
                  echo "使用方法: dotfiles-toolchain-info {name|commands|environment|environment-file}" >&2
                  exit 2
                  ;;
              esac
            '';
          };

          metadataPackages = [
            commandManifestPackage
            profileEnvironmentPackage
            toolchainInfo
          ];
        in
        {
          devShell = import ./nix/devshell.nix {
            inherit
              commandManifest
              metadataPackages
              pkgs
              profile
              profileEnvironment
              profileName
              ;
          };

          package = pkgs.buildEnv {
            name = "dotfiles-toolchain-${profileName}";
            paths = profile.packages ++ metadataPackages;
          };
        };

      toolchainOutputs = forAllSystems (
        pkgs:
        let
          catalog = import ./nix/packages.nix { inherit pkgs; };
        in
        pkgs.lib.mapAttrs (mkToolchainOutputs pkgs) catalog.profiles
      );

      # ユーザー名とプラットフォームからホームディレクトリを導出する。
      # 規則から外れる対象は homeTargets 側で homeDirectory を明示する。
      defaultHomeDirectory =
        username: system:
        if nixpkgs.lib.hasSuffix "darwin" system then "/Users/${username}" else "/home/${username}";

      # home-manager の適用対象。マシンを追加する場合はここに追記する。
      # 名前はユーザー名と一致させる。Makefile の HM_TARGET は既定で実行中の
      # ユーザー名 (id -un) を使うため、環境ごとに指定せずに済む。
      homeTargets = {
        sabas0ba.system = "x86_64-linux";

        # WSL 上の環境。NixOS-WSL の wsl.defaultUser の既定値が nixos であり、
        # 改名すると初回の nixos-rebuild まで対象が存在しないことになるため、
        # 既定値のまま受け入れる。Nix を導入する経路 (Ubuntu 等) でも同名で作成し、
        # WSL 上の対象を 1 つに揃える。
        nixos.system = "x86_64-linux";

        # Claude Code のリモート実行環境。root で動作する。
        # ホームは /home/<name> の規則から外れるため明示する。
        root = {
          system = "x86_64-linux";
          homeDirectory = "/root";
        };
      };

      mkHomeConfiguration =
        username: target:
        let
          homeDirectory = target.homeDirectory or (defaultHomeDirectory username target.system);
        in
        home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs { inherit (target) system; };
          modules = [ ./nix/home.nix ];
          extraSpecialArgs = { inherit username homeDirectory; };
        };
    in
    {
      # `nix develop .#<profile>` が使用する用途別の開発シェル。
      # direnv の `use flake` は軽量な default を選択する。
      devShells = nixpkgs.lib.mapAttrs (
        _system: profiles: nixpkgs.lib.mapAttrs (_name: output: output.devShell) profiles
      ) toolchainOutputs;

      # `nix build .#<profile>`、Dockerfile および `nix profile install` が使用する。
      packages = nixpkgs.lib.mapAttrs (
        _system: profiles: nixpkgs.lib.mapAttrs (_name: output: output.package) profiles
      ) toolchainOutputs;

      # ホームディレクトリの構成。`make hm-switch` から適用する。
      homeConfigurations = nixpkgs.lib.mapAttrs mkHomeConfiguration homeTargets;

      # WSL 上の NixOS の system 構成。`make wsl-switch` から適用する。
      #
      # 開発用ツールとホームディレクトリの内容は本構成の対象ではない。前者は開発シェル
      # (nix/devshell.nix)、後者は home-manager (nix/home.nix) が持つ。したがって WSL
      # でも他の環境と同一の手順 (`nix develop` / `make hm-switch`) となる。
      nixosConfigurations.wsl = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          nixos-wsl.nixosModules.default
          ./nix/wsl.nix
        ];
      };

      # `nix flake check` および `make check` が実行する検査。
      checks = forAllSystems (
        pkgs:
        import ./nix/checks.nix {
          inherit pkgs;
          src = self;
          inherit (self) homeConfigurations nixosConfigurations;
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

            # 対象が与えられない場合は、管理対象の *.nix だけを列挙する。
            # worktree や direnv の生成物を変更しないよう、管理外ディレクトリは探索しない。
            find . \
              -type d \( -name .git -o -name .direnv -o -name .work \) -prune -o \
              -type f -name '*.nix' -exec nixfmt {} +
          '';
        }
      );
    };
}
