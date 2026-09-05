# 素体の生成、検証、確認用描画の入り口。Blender は dotfiles の vrchat profile から取る。

SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

BLENDER ?= blender
BUILD_DIR ?= build
SUBDIVISION ?= 1
# --factory-startup で利用者設定の影響を除き、Python の例外を終了コードに反映する。
BLENDER_RUN = $(BLENDER) -b --factory-startup --python-exit-code 1 --python

.PHONY: help
help: ## 本ヘルプを表示する
	@printf '使用方法: make <target>\n\n'
	@pattern='^([a-zA-Z0-9_-]+):.*## (.*)$$'; \
	while IFS= read -r line; do \
		if [[ $$line =~ $$pattern ]]; then \
			printf '  \033[36m%-12s\033[0m %s\n' "$${BASH_REMATCH[1]}" "$${BASH_REMATCH[2]}"; \
		fi; \
	done < "$(firstword $(MAKEFILE_LIST))"

.PHONY: build
build: ## 素体を生成し FBX と .blend を書き出す
	$(BLENDER_RUN) scripts/build_avatar.py -- --out $(BUILD_DIR) --subdivision $(SUBDIVISION)

.PHONY: build-quest
build-quest: ## subdivision 無しの低 polygon 版を build/quest に生成する
	$(MAKE) build BUILD_DIR=$(BUILD_DIR)/quest SUBDIVISION=0

.PHONY: validate
validate: ## FBX を再読込し VRChat 向けの構造を検査する
	$(BLENDER_RUN) scripts/validate_fbx.py -- $(BUILD_DIR)/avatar.fbx

.PHONY: preview
preview: ## 確認用の画像を描画する (Cycles CPU)
	$(BLENDER_RUN) scripts/render_preview.py -- $(BUILD_DIR)/avatar.blend $(BUILD_DIR)/preview

DOC_IMAGES = front three_quarter face

.PHONY: docs-images
docs-images: preview ## 確認用の画像を docs/images に取り込む (README が参照する)
	mkdir -p docs/images
	for name in $(DOC_IMAGES); do cp $(BUILD_DIR)/preview/$$name.png docs/images/$$name.png; done

.PHONY: lint
lint: ## Python の構文を Blender 同梱の interpreter で検査する
	$(BLENDER) -b --factory-startup --python-exit-code 1 --python-expr \
		"import compileall, sys; sys.exit(0 if compileall.compile_dir('avatar', quiet=1) and compileall.compile_dir('scripts', quiet=1) else 1)"

.PHONY: check
check: lint build validate ## 生成と検査を通しで実行する

.PHONY: clean
clean: ## 生成物を削除する
	rm -rf $(BUILD_DIR) avatar/__pycache__ scripts/__pycache__
