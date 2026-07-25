# dotfiles の操作をまとめたエントリポイント。
# 「何ができるか」を探すときは `make help` を見れば済むようにしてある。

SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

DOCKER_IMAGE ?= dotfiles-dev
NIX ?= nix

.PHONY: help
help: ## このヘルプを表示する
	@echo "使い方: make <target>"
	@echo
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

# --- ホスト側の環境 ---------------------------------------------------------

.PHONY: shell
shell: ## 開発シェルに入る (direnv を使っていない場合)
	$(NIX) develop

.PHONY: lock
lock: ## flake.lock を生成する (未生成のときに一度だけ)
	$(NIX) flake lock

.PHONY: update
update: ## nixpkgs を flake.nix の rev に合わせて lock し直す
	$(NIX) flake update

.PHONY: bump
bump: ## nixpkgs のリビジョンを更新する (make bump REV=<40 桁の rev>)
	@test -n "$(REV)" || { \
		echo "使い方: make bump REV=<nixpkgs の rev>"; \
		echo "  最新の安定版 rev: curl -sL https://channels.nixos.org/nixos-26.05/git-revision"; \
		exit 1; \
	}
	sed -i.bak -E 's|github:NixOS/nixpkgs/[0-9a-f]{40}|github:NixOS/nixpkgs/$(REV)|' flake.nix
	rm -f flake.nix.bak
	$(NIX) flake update

.PHONY: check
check: ## すべての検査を走らせる (fmt / lint / 環境のスモークテスト)
	$(NIX) flake check
	scripts/check-env.sh

.PHONY: fmt
fmt: ## Nix とシェルスクリプトを整形する
	$(NIX) fmt
	shfmt --write --indent 2 --case-indent scripts/*.sh

.PHONY: lint
lint: ## 静的解析だけを走らせる (整形はしない)
	statix check .
	deadnix --fail .
	shellcheck scripts/*.sh
	shellcheck --shell=bash .envrc

.PHONY: env
env: ## 環境が揃っているかを確認する
	scripts/check-env.sh

.PHONY: gc
gc: ## 使われていない Nix の成果物を掃除する
	$(NIX) store gc

# --- コンテナ側の環境 -------------------------------------------------------

.PHONY: docker-build
docker-build: ## 同じ環境を持つコンテナイメージをビルドする
	docker build -t $(DOCKER_IMAGE) .

.PHONY: docker-shell
docker-shell: docker-build ## コンテナの中の開発シェルに入る
	docker run --rm -it -v "$(CURDIR):/workspace" $(DOCKER_IMAGE)

.PHONY: docker-check
docker-check: docker-build ## コンテナの中で環境のスモークテストを走らせる
	docker run --rm -v "$(CURDIR):/workspace" $(DOCKER_IMAGE) scripts/check-env.sh
