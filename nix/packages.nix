# 開発環境に導入するツールとコマンド契約の単一情報源。
#
# 各 tool は Nix package と、その package が提供する必須コマンドを対応付ける。
# flake.nix は profiles から次の出力を同じ名前で生成する。
#
#   - `nix develop .#<profile>` の開発シェル
#   - `nix build .#<profile>` の toolchain profile
#   - Docker イメージ (`DOTFILES_TOOLCHAIN_PROFILE` build arg)
#
# 大きい toolchain は既定環境へ含めず、用途別 profile で明示的に選択する。
{ pkgs }:

let
  inherit (pkgs) lib;

  linuxSystems = [
    "x86_64-linux"
    "aarch64-linux"
  ];

  packageAvailable =
    systems: package:
    (systems == null || lib.elem pkgs.stdenv.hostPlatform.system systems)
    && lib.meta.availableOn pkgs.stdenv.hostPlatform package
    && !(package.meta.broken or false);

  playwrightAvailable =
    packageAvailable linuxSystems pkgs.playwright-test
    && packageAvailable linuxSystems pkgs.playwright-driver.browsers;

  mkTool =
    {
      package,
      commands ? [ ],
      enabled ? true,
      env ? { },
      systems ? null,
    }:
    {
      inherit
        commands
        env
        package
        ;

      available = enabled && packageAvailable systems package;
    };

  groups = {
    base = [
      # 基本ユーティリティ
      (mkTool { package = pkgs.coreutils; })
      (mkTool { package = pkgs.findutils; })
      (mkTool { package = pkgs.gnugrep; })
      (mkTool { package = pkgs.gnused; })
      (mkTool { package = pkgs.gnutar; })
      (mkTool { package = pkgs.gzip; })
      (mkTool { package = pkgs.less; })
      (mkTool { package = pkgs.which; })

      # 検索・テキスト処理
      (mkTool {
        package = pkgs.ripgrep;
        commands = [ "rg" ];
      })
      (mkTool {
        package = pkgs.fd;
        commands = [ "fd" ];
      })
      (mkTool {
        package = pkgs.jq;
        commands = [ "jq" ];
      })
      (mkTool {
        package = pkgs.yq-go;
        commands = [ "yq" ];
      })
      (mkTool {
        package = pkgs.tree;
        commands = [ "tree" ];
      })

      # タスクランナー・バージョン管理
      (mkTool {
        package = pkgs.gnumake;
        commands = [ "make" ];
      })
      (mkTool {
        package = pkgs.git;
        commands = [ "git" ];
      })

      # 環境そのものを扱うツール
      (mkTool {
        package = pkgs.direnv;
        commands = [ "direnv" ];
      })
      (mkTool { package = pkgs.nix-direnv; })

      # Nix の開発支援
      (mkTool {
        package = pkgs.nixfmt;
        commands = [ "nixfmt" ];
      })
      (mkTool {
        package = pkgs.statix;
        commands = [ "statix" ];
      })
      (mkTool {
        package = pkgs.deadnix;
        commands = [ "deadnix" ];
      })
      (mkTool {
        package = pkgs.nil;
        commands = [ "nil" ];
      })

      # シェルスクリプトの開発支援
      (mkTool {
        package = pkgs.bashInteractive;
        commands = [ "bash" ];
      })
      (mkTool {
        package = pkgs.shellcheck;
        commands = [ "shellcheck" ];
      })
      (mkTool {
        package = pkgs.shfmt;
        commands = [ "shfmt" ];
      })
    ];

    c-cpp = [
      (mkTool {
        # Linux では GCC、Darwin では Clang の Nix wrapper を使用する。
        package = pkgs.stdenv.cc;
        commands = [
          "cc"
          "c++"
        ];
        env = {
          CC = "${pkgs.stdenv.cc}/bin/cc";
          CXX = "${pkgs.stdenv.cc}/bin/c++";
        };
      })
      (mkTool {
        package = pkgs.clang-tools;
        commands = [
          "clang-format"
          "clang-tidy"
          "clangd"
        ];
      })
      (mkTool {
        package = pkgs.cmake;
        commands = [ "cmake" ];
      })
      (mkTool {
        package = pkgs.ninja;
        commands = [ "ninja" ];
      })
    ];

    python = [
      (mkTool {
        package = pkgs.python3;
        commands = [ "python3" ];
      })
    ];

    rust = [
      (mkTool {
        package = pkgs.rustc;
        commands = [ "rustc" ];
      })
      (mkTool {
        package = pkgs.cargo;
        commands = [ "cargo" ];
      })
      (mkTool {
        package = pkgs.rustfmt;
        commands = [ "rustfmt" ];
      })
      (mkTool {
        package = pkgs.clippy;
        commands = [ "cargo-clippy" ];
      })
    ];

    zig = [
      (mkTool {
        package = pkgs.zig;
        commands = [ "zig" ];
      })
    ];

    typescript = [
      (mkTool {
        package = pkgs.nodejs;
        commands = [
          "node"
          "npm"
          "npx"
        ];
      })
      (mkTool {
        package = pkgs.typescript;
        commands = [
          "tsc"
          "tsserver"
        ];
      })
      (mkTool {
        package = pkgs.typescript-language-server;
        commands = [ "typescript-language-server" ];
      })
    ];

    containers = [
      # daemon はホスト側で管理する。profile には cross-platform な CLI を置く。
      (mkTool {
        package = pkgs.docker-client;
        commands = [ "docker" ];
      })

      # Podman の engine は Linux kernel の機能を使用する。
      (mkTool {
        package = pkgs.podman;
        commands = [ "podman" ];
        systems = linuxSystems;
      })

      (mkTool {
        package = pkgs.qemu;
        commands = [ "qemu-img" ];
      })
    ];

    hdl = [
      (mkTool {
        package = pkgs.veryl;
        commands = [ "veryl" ];
      })

      # Verible の Nix package は Linux 向けに提供される。
      (mkTool {
        package = pkgs.verible;
        commands = [
          "verible-verilog-format"
          "verible-verilog-lint"
          "verible-verilog-ls"
        ];
        systems = linuxSystems;
      })

      (mkTool {
        package = pkgs.verilator;
        commands = [ "verilator" ];
      })

      # Verilator が生成した simulator の trace support をリンクするために使う。
      (mkTool { package = pkgs.zlib.dev; })
      (mkTool { package = pkgs.lz4.dev; })
    ];

    browser = [
      # Browser closure は大きいため browser/full にだけ含める。
      # Nixpkgs の Playwright browser bundle は Linux 向けである。
      (mkTool {
        package = pkgs.playwright-test;
        commands = [ "playwright" ];
        enabled = playwrightAvailable;
        systems = linuxSystems;
      })
      (mkTool {
        package = pkgs.playwright-driver.browsers;
        enabled = playwrightAvailable;
        env = {
          PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
          PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
        };
        systems = linuxSystems;
      })
    ];
  };

  profileDefinitions = {
    default = {
      description = "dotfiles の保守に必要な軽量な既定環境";
      groups = [ "base" ];
    };
    software = {
      description = "Python、Rust、Zig、C/C++、TypeScript の開発環境";
      groups = [
        "base"
        "c-cpp"
        "python"
        "rust"
        "zig"
        "typescript"
      ];
    };
    containers = {
      description = "Docker、Podman、QEMU を含むコンテナ開発環境";
      groups = [
        "base"
        "containers"
      ];
    };
    hdl = {
      description = "Veryl、SystemVerilog、Verilator と C/C++ toolchain";
      groups = [
        "base"
        "c-cpp"
        "hdl"
      ];
    };
    browser = {
      description = "TypeScript と browser bundle 付き Playwright";
      groups = [
        "base"
        "typescript"
        "browser"
      ];
      available = playwrightAvailable;
      systems = linuxSystems;
    };
    full = {
      description = "利用可能な全 toolchain";
      groups = [
        "base"
        "c-cpp"
        "python"
        "rust"
        "zig"
        "typescript"
        "containers"
        "hdl"
        "browser"
      ];
    };
  };

  mkProfile =
    _name: definition:
    let
      profileSystems = definition.systems or null;
      profileAvailable =
        definition.available
          or (profileSystems == null || lib.elem pkgs.stdenv.hostPlatform.system profileSystems);
      selectedTools = lib.filter (tool: tool.available) (
        lib.concatMap (group: groups.${group}) definition.groups
      );
    in
    {
      inherit (definition) description;

      available = profileAvailable;
      packages = map (tool: tool.package) selectedTools;
      commands = lib.unique (lib.concatMap (tool: tool.commands) selectedTools);
      env = lib.foldl' (result: tool: result // tool.env) { } selectedTools;
    };

  allProfiles = lib.mapAttrs mkProfile profileDefinitions;
in
{
  profiles = lib.filterAttrs (_name: profile: profile.available) allProfiles;
}
