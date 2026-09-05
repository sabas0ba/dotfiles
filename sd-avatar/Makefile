SHELL := bash
.SHELLFLAGS := -euo pipefail -c

BLENDER ?= blender
PYTHON ?= python3
BUILD_DIR ?= build

.DEFAULT_GOAL := help

.PHONY: help
help: ## 利用可能な操作を表示する
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-14s %s\n", $$1, $$2}'

.PHONY: build
build: ## モデルを生成する (build/avatar.blend, build/avatar.fbx, build/textures/)
	$(BLENDER) -b --python-exit-code 1 -P scripts/build.py -- --out $(BUILD_DIR)

.PHONY: render
render: ## 確認用の三面図と顔の render を生成する (build/render/)
	$(BLENDER) -b --python-exit-code 1 -P scripts/render.py -- --blend $(BUILD_DIR)/avatar.blend --out $(BUILD_DIR)/render

.PHONY: verify
verify: ## 生成した .blend の構成 (bone, shape key, 面数, weight) を検査する
	$(BLENDER) -b --python-exit-code 1 -P scripts/check_model.py -- --blend $(BUILD_DIR)/avatar.blend

.PHONY: test
test: ## bpy 非依存部の unit test を実行する
	$(PYTHON) -m unittest discover -s tests -v

.PHONY: lint
lint: ## 静的解析と整形の検査を実行する
	ruff check .
	ruff format --check .

.PHONY: fmt
fmt: ## Python を整形する
	ruff format .
	ruff check --fix .

.PHONY: check
check: lint test build verify ## lint, unit test, 生成, 構成検査をすべて実行する

.PHONY: clean
clean: ## 生成物を削除する
	rm -rf $(BUILD_DIR)
