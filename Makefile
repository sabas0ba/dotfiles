# 本リポジトリに対する操作の入り口。利用可能な操作は `make help` で一覧する。

SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

DOCKER_IMAGE ?= dotfiles-dev
NIX ?= nix
# home-manager の適用対象。flake.nix の homeTargets に定義した名前を指定する。
HM_TARGET ?= sabas0ba

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
	sed -i.bak -E 's|github:NixOS/nixpkgs/[0-9a-f]{40}|github:NixOS/nixpkgs/$(REV)|' flake.nix
	rm -f flake.nix.bak
	$(NIX) flake update

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

.PHONY: hm-dry
hm-dry: ## 配置内容を表示する (実際には配置しない)
	@out="$$($(NIX) build --no-link --print-out-paths \
		'.#homeConfigurations.$(HM_TARGET).activationPackage')"; \
	DRY_RUN=1 "$$out/activate"

.PHONY: hm-switch
hm-switch: ## ホームディレクトリへ配置する
	@echo "ホームディレクトリの既存ファイルを置き換える可能性がある。"
	@echo "先に make hm-dry で対象を確認すること。"
	@out="$$($(NIX) build --no-link --print-out-paths \
		'.#homeConfigurations.$(HM_TARGET).activationPackage')"; \
	"$$out/activate"

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
