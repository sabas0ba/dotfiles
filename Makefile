# 本リポジトリに対する操作の入り口。利用可能な操作は `make help` で一覧する。

SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

DOCKER_IMAGE ?= dotfiles-dev
NIX ?= nix
# home-manager の適用対象。flake.nix の homeTargets に定義した名前を指定する。
# 既定は実行中のユーザー名。環境ごとに指定せずに済むようにするため。
HM_TARGET ?= $(shell id -un)

.PHONY: help
help: ## 本ヘルプを表示する
	@echo "使用方法: make <target>"
	@echo
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

# --- ホスト側の環境 ---------------------------------------------------------

.PHONY: shell
shell: ## 開発シェルに入る (direnv 未使用時)
	$(NIX) develop

.PHONY: lock
lock: ## flake.lock を生成する
	$(NIX) flake lock

.PHONY: update
update: ## flake.nix の rev に対して lock を再生成する
	$(NIX) flake update

.PHONY: bump
bump: ## nixpkgs の rev を更新する (make bump REV=<40 桁の rev>)
	@test -n "$(REV)" || { \
		echo "使用方法: make bump REV=<nixpkgs の rev>"; \
		echo "  安定版の rev: curl -sL https://channels.nixos.org/nixos-26.05/git-revision"; \
		exit 1; \
	}
	scripts/update-pins.sh nixpkgs $(REV)
	$(NIX) flake update

.PHONY: bump-wsl
bump-wsl: ## NixOS-WSL の rev を更新する (make bump-wsl REV=<40 桁の rev>)
	@test -n "$(REV)" || { \
		echo "使用方法: make bump-wsl REV=<NixOS-WSL の rev>"; \
		echo "  release-26.05 上のタグが指すコミット SHA を指定する"; \
		exit 1; \
	}
	scripts/update-pins.sh nixos-wsl $(REV)
	$(NIX) flake update

.PHONY: bump-hm
bump-hm: ## home-manager の rev を更新する (make bump-hm REV=<40 桁の rev>)
	@test -n "$(REV)" || { \
		echo "使用方法: make bump-hm REV=<home-manager の rev>"; \
		echo "  release-26.05 の HEAD を指定する"; \
		exit 1; \
	}
	scripts/update-pins.sh home-manager $(REV)
	$(NIX) flake update

# ベースイメージ、GitHub Actions、Nix インストーラの更新は flake.lock の再生成を
# 伴わないため、スクリプトを直接呼ぶ。対象と値の取得方法は --help に示す。
.PHONY: bump-help
bump-help: ## 固定の更新方法を表示する
	scripts/update-pins.sh --help

.PHONY: check
check: ## すべての検査を実行する (nix flake check + 環境のスモークテスト)
	$(NIX) flake check
	scripts/check-env.sh

.PHONY: fmt
fmt: ## Nix およびシェルスクリプトを整形する
	$(NIX) fmt
	shfmt --write --indent 2 --case-indent scripts/*.sh

.PHONY: lint
lint: ## 静的解析のみを実行する (整形は行わない)
	statix check .
	deadnix --fail .
	scripts/check-lock.sh
	scripts/check-pins.sh
	shellcheck scripts/*.sh
	shellcheck --shell=bash .envrc

.PHONY: env
env: ## 環境が構成されているかを確認する
	scripts/check-env.sh

.PHONY: gc
gc: ## 参照されていない Nix の成果物を削除する
	$(NIX) store gc

# --- ホームディレクトリの構成 (home-manager) --------------------------------

.PHONY: hm-build
hm-build: ## ホームの構成を構築する (配置は行わない)
	$(NIX) build --no-link --print-out-paths \
		'.#homeConfigurations.$(HM_TARGET).activationPackage'

# home-manager の activation script は USER を参照する。Claude Code のリモート実行
# 環境のように USER が設定されていない環境があるため、ここで補う。
HM_ACTIVATE_ENV = USER="$(HM_TARGET)"

.PHONY: hm-dry
hm-dry: ## 配置内容を表示する (実際には配置しない)
	@out="$$($(NIX) build --no-link --print-out-paths \
		'.#homeConfigurations.$(HM_TARGET).activationPackage')"; \
	$(HM_ACTIVATE_ENV) DRY_RUN=1 "$$out/activate"

.PHONY: hm-switch
hm-switch: ## ホームディレクトリへ配置する
	@echo "ホームディレクトリの既存ファイルを置き換える可能性がある。"
	@echo "先に make hm-dry で対象を確認すること。"
	@out="$$($(NIX) build --no-link --print-out-paths \
		'.#homeConfigurations.$(HM_TARGET).activationPackage')"; \
	$(HM_ACTIVATE_ENV) "$$out/activate"

# --- WSL 上の NixOS ---------------------------------------------------------
#
# WSL に NixOS を導入する経路でのみ使用する。Windows 側での登録は
# scripts/wsl-bootstrap.ps1 が行う。手順は README の「Windows (WSL)」を参照する。
#
# nixos-rebuild は system の profile を書き換えるため root 権限を要する。sudo を
# Makefile 側に書いているのは、対象が system であることを操作の名前から分かるように
# するためである。

WSL_TARGET ?= wsl

.PHONY: wsl-build
wsl-build: ## WSL 用の NixOS 構成を構築する (適用は行わない)
	$(NIX) build --no-link --print-out-paths \
		'.#nixosConfigurations.$(WSL_TARGET).config.system.build.toplevel'

.PHONY: wsl-dry
wsl-dry: ## 適用内容を表示する (実際には適用しない)
	sudo nixos-rebuild dry-activate --flake '.#$(WSL_TARGET)'

.PHONY: wsl-switch
wsl-switch: ## WSL 上の NixOS に構成を適用する
	@echo "system の構成を置き換える。先に make wsl-dry で内容を確認すること。"
	@echo "隔離の設定 (/etc/wsl.conf) は再起動後に反映される。Windows 側で"
	@echo "wsl.exe --terminate <ディストリビューション名> を実行すること。"
	sudo nixos-rebuild switch --flake '.#$(WSL_TARGET)'

.PHONY: wsl-isolation
wsl-isolation: ## WSL が Windows 側から隔離されていることを検査する
	scripts/check-wsl-isolation.sh

# --- コンテナ側の環境 -------------------------------------------------------

.PHONY: docker-build
docker-build: ## 同一の環境を持つコンテナイメージを構築する
	docker build -t $(DOCKER_IMAGE) .

.PHONY: docker-shell
docker-shell: docker-build ## コンテナ内の開発シェルに入る
	docker run --rm -it -v "$(CURDIR):/workspace" $(DOCKER_IMAGE)

.PHONY: docker-check
docker-check: docker-build ## コンテナ内で環境のスモークテストを実行する
	docker run --rm -v "$(CURDIR):/workspace" $(DOCKER_IMAGE) scripts/check-env.sh
