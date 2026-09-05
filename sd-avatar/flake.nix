{
  description = "sd-avatar: SD 頭身キャラクターの VRChat 向け 3D model を Blender script で生成する";

  inputs = {
    # sabas0ba/dotfiles と同じリビジョンで固定する (nixos-26.05)。
    # Blender の版はこの入力が決める。更新は flake.lock を同一コミットに含める。
    nixpkgs.url = "github:NixOS/nixpkgs/597283ad8aa0b331c788e97c4c262d58877074ef";
  };

  outputs =
    { self, nixpkgs }:
    let
      # Blender の Nix package は Linux 向けに提供される。
      systems = [
        "x86_64-linux"
        "aarch64-linux"
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

      # 生成 script は Blender 同梱の Python (3.13) で動作する。bpy に依存しない
      # 部分の unit test と lint には、同じ major.minor の python3 と ruff を使う。
      toolsFor = pkgs: [
        pkgs.blender
        pkgs.python313
        pkgs.ruff
        pkgs.gnumake
      ];
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShellNoCC {
          packages = toolsFor pkgs;
          shellHook = ''
            echo "sd-avatar dev shell: blender ${pkgs.blender.version}, python ${pkgs.python313.version}"
            echo "  make help: 利用可能な操作の一覧"
          '';
        };
      });

      packages = forAllSystems (pkgs: {
        default = pkgs.buildEnv {
          name = "sd-avatar-toolchain";
          paths = toolsFor pkgs;
        };
      });

      checks = forAllSystems (pkgs: {
        # 幾何生成の unit test と lint。Blender を起動する統合検査は make check が行う。
        unit =
          pkgs.runCommand "sd-avatar-unit"
            {
              nativeBuildInputs = [
                pkgs.python313
                pkgs.ruff
              ];
            }
            ''
              cd ${self}
              # sandbox 内の source は読み取り専用のため cache を書かない。
              ruff check --no-cache .
              ruff format --check --no-cache .
              python3 -m unittest discover -s tests -v
              touch $out
            '';
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
