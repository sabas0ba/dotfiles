# telemetry とデータ収集を無効化する環境変数。
#
# 本ファイルが単一情報源であり、次の経路から参照する。
#   - nix/home.nix     home.sessionVariables (home-manager の対象ホスト)
#   - nix/wsl.nix      environment.sessionVariables (WSL 上の NixOS の全ユーザー)
#   - flake.nix        開発シェルと profile の環境 (nix develop、direnv、クラウド環境)
# home/.claude/settings.json の env は生ファイルのため値を複製しており、一致を
# nix/checks.nix の telemetry-env が検査する。シェルを経由せずに起動した Claude Code
# (IDE 拡張、desktop app 等) にも適用するためである。
#
# Codex CLI は telemetry を環境変数では制御できないため、etc/codex/config.toml で扱う。
{
  # --- Claude Code ------------------------------------------------------------
  # https://code.claude.com/docs/en/data-usage#telemetry-services

  # 利用状況の metrics。DISABLE_TELEMETRY は Remote Control が依存する feature flag の
  # 評価も無効化する。
  DISABLE_TELEMETRY = "1";

  # 内部エラーの stack trace 等を外部のエラー追跡サービスへ送る機能。
  DISABLE_ERROR_REPORTING = "1";

  # /feedback、/bug、/share による会話履歴の送信。
  DISABLE_FEEDBACK_COMMAND = "1";

  # セッション品質の survey と、その後の transcript 共有の確認。
  CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY = "1";

  # 上記を含む非必須通信の一括停止。自動更新、release notes、PR status badge、
  # fast mode 等の可用性確認、plugin command source の background 実行も止まり、
  # artifact の作成も無効になる。環境は Nix で固定し使い捨てるため、自動更新の停止は
  # 許容する。"0" でも有効になるため、戻す場合は変数ごと削除する。
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";

  # --- GitHub CLI ---------------------------------------------------------------
  # cli/cli internal/telemetry/telemetry.go の ParseTelemetryState。
  # GH_TELEMETRY、DO_NOT_TRACK、gh config の telemetry の順に優先する。

  # gh 2.91.0 以降の利用状況 telemetry。false 相当の値で無効化する。
  GH_TELEMETRY = "false";

  # --- GitHub Copilot CLI -------------------------------------------------------
  # https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/authenticate-copilot-cli

  # offline mode。telemetry を止めるが、GitHub への接続と認証も行わなくなり、BYOK
  # provider を使う動作に変わる。telemetry だけを止める公開設定は無い。Copilot は
  # GitHub の Web 上でのみ使い CLI は使わない前提のため、CLI の機能を失うことを許容する。
  # CLI を使う環境では当該変数を unset する。
  COPILOT_OFFLINE = "true";

  # --- 共通 -------------------------------------------------------------------

  # 複数のツールが参照する opt-out の慣習。gh は "1" または "true" を無効化として
  # 扱い、Claude Code は設定されていれば session 品質の survey を無効化する。
  # 上記の個別指定が無いツールに対する補完として設定する。
  DO_NOT_TRACK = "1";
}
