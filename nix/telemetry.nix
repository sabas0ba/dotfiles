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
# Codex CLI は telemetry を環境変数では制御できず、config.toml の analytics.enabled、
# feedback.enabled、otel.metrics_exporter のみが対象となる。本ファイルの対象外である。
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

  # --- GitHub CLI ---------------------------------------------------------------
  # cli/cli internal/telemetry/telemetry.go の ParseTelemetryState。
  # GH_TELEMETRY、DO_NOT_TRACK、gh config の telemetry の順に優先する。

  # gh 2.91.0 以降の利用状況 telemetry。false 相当の値で無効化する。
  GH_TELEMETRY = "false";

  # --- 共通 -------------------------------------------------------------------

  # 複数のツールが参照する opt-out の慣習。gh は "1" または "true" を無効化として
  # 扱い、Claude Code は設定されていれば session 品質の survey を無効化する。
  # 上記の個別指定が無いツールに対する補完として設定する。
  DO_NOT_TRACK = "1";
}
