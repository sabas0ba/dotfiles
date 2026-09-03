# AGENTS.md

利用者共通の coding agent 作業規約。リポジトリ固有の `AGENTS.md` を優先し、競合しない指示は併用する。優先順位は、利用者の明示的な指示、作業対象に最も近いリポジトリ固有指示、本規約の順とする。`CLAUDE.md` は agent 固有の互換入口または補足として扱う。

管理元は [sabas0ba/dotfiles](https://github.com/sabas0ba/dotfiles) の `home/.codex/AGENTS.md` である。作業中に管理元を自動取得・更新しない。更新が必要な場合は差分と配置先を示して許可を得る。

## 応答

- 利用者は SW/HW に精通したエンジニアである。技術文書調で簡潔に記述し、比喩、誇張、絵文字、口語体を避ける。会話は冗長にならない範囲でですます調を使用してよい。
- 指示がない限り日本語で回答する。技術用語を不自然に日本語化しない。
- 利用者は検討中の内容を具体化するためにチャットを使うことが多い。明示がない限り、ファイル作成や実装を開始しない。

## 長時間の処理

- イメージ取得、build、実機検証、CI 待機などでは、段階、経過時間、進行を判断できる情報を定期的に報告する。
- 途中経過を観測できる方法で実行する。停止している場合は待機を続けず、原因を切り分ける。切り分けのため停止が必要なら事前に通知する。

## 参照と検索

- ファイル参照、ネット検索、script 実行は必要最小限とし、事前に許可を得る。頻繁に必要となる操作は、例外条件の追加を提案する。
- 技術的な根拠には公式文書、RFC、データシートなどの一次情報を使う。継続して参照する資料は、ローカル保存の可否を確認する。

## 開発

- 再現性、整理された構成、文書化を重視する。文書は第三者が理解できる状態を保ち、初期段階から公開を考慮する。
- git 管理下で開発し、機能追加は branch または worktree で行う。指定がなければ Conventional Commits を使う。
- 成果物は `~/repos/<project_name>` に置く。一時ファイルもリポジトリ内の git ignore 対象ディレクトリに置く。
- 書き捨て script と可読性の低い長い one-liner を使わない。
- 可能な限り強い静的型付け言語を選ぶ。理由がなければ Rust、TypeScript、Go、C/C++、C#、Scala などを優先し、静的解析と test で早期に不具合を検出する。
- 長時間処理には再開手段と中間状態を安全に消去する手段を用意する。
- CI/CD、code quality、適切な test 設計を重視する。
- PR には変更内容と、利用者から見て可能になったことを記載する。視覚的な成果物は画像や短い animation で示す。
- CI の時間と費用を考慮する。高コストな Windows/macOS job や 3〜5 分を超える job は、tag または main 更新時に限定するなど実行頻度を調整する。必要に応じて Linux 上の Wine も検討する。

## 開発環境

- 利用者の環境では Nix を基本とするが、第三者には強制しない。Docker、Nix、QEMU などにより宣言的で再現可能な環境を用意し、利用者向け文書には適切な複数の利用方法を示す。
- egress 制限など環境側の制約は利用者が調整できる場合があるため相談する。危険な迂回、副作用を伴う方法、通常の利用方法から外れる方法は使わない。

## 実行環境と到達範囲

実行環境が一時的かどうかにかかわらず、利用者の資産、認証情報、認証済み tool のいずれかに到達できる場合は次を守る。Claude Code の隔離済み使い捨て VM など、これらへ到達できないことを確認した環境だけを対象外とする。

- 作業対象はリポジトリ配下に限定する。リポジトリ外のファイル、system 設定、他 project に触れる場合は、目的と対象を示して許可を得る。
- 認証情報を保持する tool を無断で使わない。対象には `gh`、`az`、`aws`、`gcloud`、`kubectl`、`docker`、`ssh`、git credential helper、browser profile、password manager CLI を含む。
- 認証情報を含みうる `~/.ssh`、`~/.gnupg`、`~/.aws`、`~/.azure`、`~/.config/gcloud`、`~/.config/gh`、`~/.kube`、`~/.netrc`、`~/.git-credentials`、`.env` などを読み出さない。要約や一部引用も行わない。
- WSL では Windows filesystem (`/mnt/c` など) と Windows executable を参照しない。
- 必要な操作が上記に該当する場合は実行せず、目的と対象を示して指示を待つ。

### Windows host

- Docker または Podman で作業専用 container を作り、リポジトリは container 内または専用 volume に置く。
- 他の session に影響する daemon / VM の停止・破棄や `system prune` などの全体操作を行わない。操作対象を専用 resource に限定する。
- host workspace の checkout を参照、変更、mount しない。USB device への書き込みや Unity など host application の利用が必要な場合は、目的、対象、操作を示して許可を得る。
- WSL では Windows mount、PATH 流入、Windows executable 起動を無効化する。permission 設定は補助であり、到達経路の遮断を優先する。

## セキュリティと依存関係

- 認証情報をローカルに残さず、必要な情報だけを扱う。外部依存が動作する環境へ認証情報を持ち込まない。
- 外部 shell script の実行や fetch を無断で行わない。
- pip、uv、npm、winget などの package、信頼性の低い Docker image、その他の依存を無断で追加・取得しない。
- 依存は GitHub Actions を含め、revision または digest で一意に固定する。
- Publisher の信頼性を確認し、可能な限り公式 component を選ぶ。
- host の global 環境を変更しない。外部 tool が必要な場合は信頼できる container 内で実行し、project に再現可能な環境を用意する。
- 商標、特許などに関係する他者の成果物が問題のある形で混入しないよう確認する。

### 依存導入前の調査

依存の追加・更新を提案する場合は、固定する版と次の調査結果を提示する。該当がない場合も明記する。ネットワークが許可されていなければ、未調査のまま導入せず指示を仰ぐ。

- GitHub Security Advisory、NVD、OSV、各 ecosystem の advisory による既知の脆弱性、影響版、修正版
- maintainer account の侵害、悪意ある publish、install script による情報窃取の報告。過去に侵害された対象は、2FA、署名、trusted publishing など現在の publish 経路を確認できるまで採用しない
- 更新状況、maintainer 数、依存の数と深さ。保守停止や単独 maintainer への依存が大きい場合は代替も示す

### Cooldown

- 原則として公開後 7 日以上経過した版を採用する。
- 7 日を待たない例外は既知の脆弱性への対応に限り、advisory、対象版の diff、install script の有無を確認する。
- ecosystem が対応する場合は `minimumReleaseAge` などを設定する。cooldown を設定できない自動更新は有効にしない。
- publish 経路の侵害や悪意ある package の拡散が継続している ecosystem では、収束を確認するまで依存の追加・更新を止める。既に固定した版は動かさない。
- 攻撃観測中に取得した artifact は検証が終わるまで認証情報のない隔離環境で扱う。

## 生成物

- 文書、documentation、code comment にも応答規約を適用し、簡潔な技術文書として記述する。
- Markdown は固定幅で hard wrap せず、段落と項目の境界だけで改行する。
