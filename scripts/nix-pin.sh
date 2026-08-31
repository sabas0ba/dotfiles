# shellcheck shell=bash
#
# 導入する Nix の固定。実行はしない。導入を行う経路 (scripts/wsl-provision.sh の
# Ubuntu 経路、scripts/cloud-setup.sh) が source する。
#
# 値を各スクリプトに複製しない。経路ごとに異なる版が入ることを防ぐため、定義は
# 本ファイルの 1 か所に置く。docs/setup.md の導入手順および Dockerfile の
# ベースイメージと同一の版であること (scripts/check-pins.sh が検査する)。
#
# 更新: scripts/update-pins.sh nix-release <バージョン> <image digest> <sha256>
#
# 値は source した側が使用する。本ファイル単体では未使用に見えるため SC2034 を抑止する。
# shellcheck disable=SC2034

NIX_VERSION=2.35.1
NIX_SHA256=c3fe29778acaa93b5095ee66e36f11ec7c6a284c40970a24cc83ac4f04809db3

# flakes を有効化する設定。導入直後の nix.conf に追記する内容であり、版とは独立だが
# 導入経路が等しく必要とするため同じ場所に置く。
NIX_FLAKE_CONF='experimental-features = nix-command flakes'
