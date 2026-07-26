# home-manager の設定。ホームディレクトリに配置する内容をここで宣言する。
#
# 配置機構は home-manager に一本化しており、生ファイルの配置 (home/ 以下) も
# home.file 経由で行う。
{
  username,
  homeDirectory,
  ...
}:

{
  home = {
    inherit username homeDirectory;

    # 設定の互換性の基準となる home-manager のリリース。
    # 追従したい場合を除いて変更しない。
    stateVersion = "26.05";

    # home/ 以下をホームディレクトリの構造に対応させる。
    #
    # recursive = true はディレクトリ自体ではなくその配下のファイルを個別に
    # symlink する。~/.claude のように home-manager の管理外のファイルが既に
    # 存在するディレクトリを、丸ごと置き換えてしまわないようにするため。
    file.".claude" = {
      source = ../home/.claude;
      recursive = true;
    };
  };

  # 26.05 で userName / userEmail / extraConfig は settings に統合された。
  # 旧名は警告付きで受理されるが、新しい名前を使用する。
  programs.git = {
    enable = true;

    settings = {
      user = {
        name = "sabas0ba";
        email = "sabas0ba@outlook.com";
      };

      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
    };
  };

  # home-manager 自身を home-manager で管理する。`home-manager` コマンドが
  # ホームディレクトリの profile に入る。
  programs.home-manager.enable = true;
}
