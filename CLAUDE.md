
# SmileCoach 開発ルール
## 1. プロジェクト概要
- SmileCoachは接客練習を録音・録画し、AIによる分析・評価を行うRailsアプリケーション。
- Ruby on Rails、PostgreSQL、Docker、Minitestを使用する。
- 既存の録音・録画・分析・認証機能を壊さないこと。
- 既存コードを調査し、現在の実装に合わせて開発すること。
- ユーザーへの説明・報告は日本語で行うこと。
## 2. 基本方針
- これまでのSmileCoachの開発手順を、11章の開発自動化と承認の方針に沿って維持する。
- Issueの受け入れ条件を満たすために必要な変更だけを行う。
- Issueの範囲外のリファクタリングや機能追加を勝手に行わない。
- 仕様が不明な場合は、実装前に確認する。
- 原則として1つのIssueにつき1つの作業ブランチとし、複数のPRが必要な場合は計画で明示したうえで個別の作業ブランチを使用できる。
- ファイルの変更は、ユーザー（プロダクトオーナー）が承認したIssueと実装計画の範囲内で行う（11章の段階2）。
- 承認範囲内の作業は途中で個別の承認を求めずにまとめて実行し、最後に結果をまとめて報告する。11章の作業停止条件に当たった場合は止めて報告する。
## 3. Claude Codeの担当範囲
- 既存コードの調査
- 実装方針と変更予定ファイルの提示
- 承認後のコード作成・修正
- テストの追加・修正・実行
- RuboCop・Brakeman・importmap audit・Zeitwerkなどの品質確認
- 差分と変更ファイルの確認
- 承認範囲内のステージング・コミット・作業ブランチへのPush・Pull Request作成・CI確認・CI失敗の修正
- 個別承認後のPRマージ、Issueの完了処理、ブランチ削除（11章の段階3）
- 実装結果とテスト結果の報告
## 4. 実装前の確認
- 現在のブランチを確認する。
- 関連するモデル、コントローラ、サービス、ビュー、テストを調査する。
- 修正予定ファイルと変更理由を提示する。
- 既存機能への影響と必要なテストを説明する。
- ユーザーの承認があるまで実装しない。
## 5. Git運用ルール
- mainブランチで直接実装しない。
- mainの最新化、作業ブランチの作成、コミット、作業ブランチへのPush、Pull Request作成は、承認済みIssueの範囲内でClaude Codeが行う（11章の段階2）。
- PRマージとブランチ削除は、ユーザーの個別承認後にClaude Codeが行う（11章の段階3）。
- Claude Codeは、承認済みIssueの範囲外ではGitの書き込み操作を行わない。
- 作業ブランチ名は feature/・fix/・docs/・chore/ のいずれかで始める。
- mainへの直接Pushと強制Pushは行わない。
- git add . や git add -A は使用しない。
- ステージングするファイルは必ず個別に指定する。
- git reset --hard、git clean、強制Pushなどの破壊的操作を行わない。
- 既存の変更や未追跡ファイルを勝手に破棄しない。
## 6. バックアップと機密情報の保護
- .bakファイルを変更・削除・ステージングしない。
- .sql、.tar.gzなどのバックアップを変更・削除・ステージングしない。
- 録音・録画データやユーザー生成ファイルを勝手に削除しない。
- データベースのリセットやデータ削除を勝手に実行しない。
- APIキー、認証情報、環境変数の秘密値を表示・記録・コミットしない。
- 既存のバックアップファイルはそのまま保持する。
## 7. テスト・品質確認
- 変更内容に応じてMinitestを追加・修正する。
- 関連テストを実行し、必要に応じて全テストを実行する。
- Docker環境でのテスト実行を基本とする。
- テストコマンド（外部API通信を防ぐ形。11章の「テスト時の外部API通信の防止」を参照）：docker compose -f docker-compose.yml run --rm -e RAILS_ENV=test -e GROQ_API_KEY= -e http_proxy=http://127.0.0.1:9 -e https_proxy=http://127.0.0.1:9 -e no_proxy=db,localhost,127.0.0.1 web bin/rails test
- RuboCopを実行する。
- git diff --checkを実行する。
- git statusで変更ファイルを確認する。
- テスト失敗やRuboCop違反がある場合は原因と対応内容を報告する。
- 実際に確認していない結果を成功と報告しない。
## 8. いつもの開発手順
承認は原則3回（①実装計画、②PRマージ、③完了処理）を目標とする。3回は目標で上限ではない（11章）。
1. Issueの選定（プロダクトオーナー）
2. Issue内容と受け入れ条件を確認し、既存コードを調査して実装計画を提示（Claude Code、段階1）
3. 要件・設計・計画のレビュー（ChatGPT）
4. 実装計画の一括承認（プロダクトオーナー、承認①）
5. mainを最新化し、作業ブランチを作成（Claude Code、段階2）
6. 実装し、テストを追加・修正して実行（Claude Code、段階2）
7. RuboCop・Brakeman・importmap audit・Zeitwerk・git diff --checkを実行し、git statusと変更内容を確認（Claude Code、段階2）
8. 変更ファイルを個別にステージングしてコミットし、作業ブランチをPushしてPull Requestを作成（Claude Code、段階2）
9. CIのlint、scan_js、scan_ruby、testを確認し、承認範囲内で失敗を修正（Claude Code、段階2）
10. 実装結果とマージ判断の材料をまとめて報告（Claude Code）
11. 実装結果・品質のレビュー（ChatGPT）
12. PRマージの個別承認（プロダクトオーナー、承認②。対象ブランチ名と条件を明示すればブランチ削除も同時に承認できる）
13. HEADコミットの一致を条件にマージし、ローカルmainを最新化してmain CIを確認（Claude Code）
14. 本番動作確認（プロダクトオーナー。Claude Codeは/upの確認と確認項目の一覧を用意する）
15. 完了条件を照合し、完了処理の承認を依頼（Claude Code）
16. 完了処理の承認（プロダクトオーナー、承認③）
17. 完了コメント・受け入れ条件のチェック・Issueのクローズ、CLAUDE.mdの完了記録PR、承認済みの作業ブランチの整理（Claude Code）
18. 今回のIssueの詳細な作業記録を作成（ChatGPT。Claude Codeは必要な実行結果を報告する）
## 9. Issue完了後の作業記録
- Pull Requestをマージし、ローカルmainを最新化した後、今回のIssueの作業記録を作成する。
- ユーザーがこれまで使用してきた「いつもの手順」の形式に合わせる。
- 全内容を1回でコピーできるよう、1つのMarkdownコードブロックにまとめる。
- コードブロック内に空行を入れない。
- 各工程を省略せず、実際に行った順番で記載する。
- Issue番号・タイトル・実装内容・完了条件を記載する。
- mainの最新化、ブランチ作成、実装、テスト、RuboCop、差分確認、ステージング、コミット、Push、PR、CI、マージ、main更新を記載する。
- 実際に使用したコマンド、ブランチ名、変更ファイル、コミットメッセージを記録する。
- テストのruns、assertions、failures、errors、skipsを実行結果に基づいて記載する。
- GitHub Actionsのlint、scan_js、scan_ruby、testの結果を記載する。
- 最後に【今回の完成内容】を記載する。
- 実行していない作業や未確認の結果を完了済みとして記載しない。
- ChatGPTが作業記録を作成できるよう、Claude Codeは必要な実行結果を報告する。
### 完了記録
- b2bananaman-pixel/smile_coach#78 管理者が商材情報を登録・編集できるようにする（CLOSED、チェックリスト88項目すべて完了）
  - PR：b2bananaman-pixel/SmileCoach-Projects#112、マージコミット a54107b
  - 実装：ProductCategory・Productのモデルと管理画面（一覧・登録・詳細・編集）、商材の公開・非公開、カテゴリの有効・無効の専用切り替え
  - テスト：541 runs、2587 assertions、0 failures、0 errors、0 skips
  - RuboCop：違反0件、Brakeman：警告0件、CI（lint・scan_js・scan_ruby・test）全4ジョブ成功
  - 本番：Renderデプロイ・DBマイグレーション・動作確認成功、既存AIロープレの会話・結果表示を確認
- b2bananaman-pixel/smile_coach#79 AIロープレで商材を選択・保存できるようにする（CLOSED 2026-11-14、受け入れ条件78項目すべて完了）
  - PR：b2bananaman-pixel/SmileCoach-Projects#114、マージコミット 8e44645abbce51a66f4bac02bcc53d82d6d03b66
  - 実装：AIロープレ開始時の商材の任意選択（公開中かつ有効カテゴリの商材のみ、非公開・無効カテゴリの商材IDは404）、商材IDと開始時点の商材情報スナップショットの保存、暗号化トークンによる開始時点の情報の保護
  - 既存動作：商材未選択時は従来どおり動作、AI会話生成・評価ロジックは変更なし
  - テスト：580 runs、2810 assertions、0 failures、0 errors、0 skips
  - RuboCop：147ファイル・違反0件、Brakeman：CI設定で警告0件、main CI（lint・scan_js・scan_ruby・test）全4ジョブ成功
  - 本番：Renderデプロイ・マイグレーション20261108110000成功、商材あり・なしのAIロープレ開始、商材名表示、保存、評価結果表示、非公開・無効カテゴリの404を確認
  - 注記：本番DBのproduct_id・product_snapshotは直接照会していない。テスト件数・RuboCop件数は過去の確認値で、記録作成時に再実行・CIログでの照合はしていない
- b2bananaman-pixel/smile_coach#80 GitHub ActionsのCI実行環境をubuntu-24.04に固定する（CLOSED 2026-11-14、受け入れ条件8項目すべて完了）
  - PR：b2bananaman-pixel/SmileCoach-Projects#116、マージコミット 525d631abfce9ef8288dbbcaacf7a2abd0b1eae5
  - 原因：ubuntu-latestがubuntu-26.04に切り替わり、Ruby 3.2.2をセットアップできず全4ジョブが失敗（Unavailable version 3.2.2 for ruby on ubuntu-26.04）
  - 実装：.github/workflows/ci.ymlの4ジョブ（scan_ruby・scan_js・lint・test）のruns-onをubuntu-latestからubuntu-24.04に変更（4行のみ）
  - 既存への影響：Rubyバージョン（.ruby-version：ruby-3.2.2）・Gemfile・Dockerfile・アプリケーションコードは変更なし
  - テスト：580 runs、2810 assertions、0 failures、0 errors、0 skips（CIのtestジョブ）
  - CI：PR #116（run 43567623528）・main（run 43567785994）・最新mainを取り込んだPR #115（run 43568118701）で、いずれもubuntu-24.04上でlint・scan_js・scan_ruby・test全4ジョブ成功、Brakeman警告0件、importmap audit脆弱性なし
- b2bananaman-pixel/smile_coach#81 AIロープレの会話に商材情報を反映する（CLOSED 2026-11-14、受け入れ条件53項目すべて完了）
  - PR：b2bananaman-pixel/SmileCoach-Projects#117、マージコミット 10d697b98bab439e9b6e8042da9424daddcd495e
  - 実装：検証済みトークンの開始時点スナップショットをお客様役AIへ渡す（DB再取得なし）、A案「一般的なお客様」のプロンプト（お客様設定・知識レベル・商材情報・応答ルールをメソッド分割）、渡す項目と文字数上限（カテゴリ50・商材名/メーカー100・概要/特徴/料金・契約条件/注意事項500）、提案ポイント・確認すべき事項・URL・ID等は渡さない
  - エラー処理：トークン不正（改ざん・期限切れ・別ユーザー・別練習テーマ）422、練習テーマIDの欠落・形式不正422、存在しない練習テーマ404
  - 既存動作：商材未選択時の送信内容・プロンプトは変更前とバイト単位で一致、評価ロジック・保存処理・DB構造は変更なし
  - テスト：601 runs、3089 assertions、0 failures、0 errors、0 skips
  - RuboCop：147ファイル・違反0件、Brakeman：警告0件、importmap audit：脆弱性なし、main CI（run 43572571382、lint・scan_js・scan_ruby・test）全4ジョブ成功
  - 本番：Renderデプロイ（10d697b）Live、ユーザーが本番ブラウザで8項目（商材あり会話、一般的なお客様の振る舞い、料金・契約条件への質問、存在しない特典を断定しない、商材なし会話、終了・保存・評価、音声認識・読み上げ・録画・録音、履歴・録画再生）を確認
- b2bananaman-pixel/smile_coach#82 トップ画面・ログイン画面をAIロープレ中心のデザインにリニューアルする（CLOSED 2026-11-14、受け入れ条件17項目すべて完了）
  - PR：b2bananaman-pixel/SmileCoach-Projects#120、マージコミット 25388323fe7a809a2d3402c9b6d348e17f626aad
  - 実装：トップ画面とDeviseログイン画面を共通パーシャル（shared/_auth_landing・shared/_login_form）で共通化し、ロゴ・見出し・接客スキル6項目（笑顔・話し方・傾聴力・ヒアリング力・提案力・クロージング力）・機能紹介3項目（AIロープレで実践練習・練習を重ねて成長・練習履歴・成長の確認）を表示、未ログイン時はログインフォーム・パスワード再設定・新規登録（無料）、ログイン済み時はAIロープレ開始・練習履歴への導線
  - 画像：ユーザー指定のキャラクター画像（smilecoach_characters.png）・スマイルアイコン（smilecoach_smile_icon.png）を無加工で使用（MD5一致を確認）、参考デザイン画像はコミットしない
  - 既存動作：Devise認証処理（送信先・パラメータ名）・新規登録・パスワード再設定画面、AIロープレの会話・評価・保存処理は変更なし、14日自動削除の案内は維持
  - レスポンシブ：PC・スマートフォン対応（スマートフォンではログインフォームを機能紹介より先に表示、スキルラベルを折り返し）
  - 追加修正：Bootstrap Iconsのフォントが404でアイコンが表示されていなかったため、config/initializers/assets.rbでアセットパイプラインから配信するよう修正
  - テスト：610 runs、3133 assertions、0 failures、0 errors、0 skips
  - RuboCop：148ファイル・違反0件、Brakeman：警告0件、importmap audit：脆弱性なし、main CI（run 43602329443、lint・scan_js・scan_ruby・test）全4ジョブ成功
  - 本番：ユーザーがlocalhostでPC・スマートフォン表示を確認、Renderデプロイ後の画面表示・動作を確認
- b2bananaman-pixel/smile_coach#83 ログイン後のマイページを新設し、AIロープレへの導線を整理する（CLOSED 2026-11-15、チェック項目59項目すべて完了）
  - PR：b2bananaman-pixel/SmileCoach-Projects#122、マージコミット 307edb1e8ab83a7a9df32a8d657171902bc4c8a2
  - 実装：ログイン前後の画面分離（config/routes.rbの`authenticated :user`でログイン済みの / をmypages#showに、未ログインはIssue #82のトップ画面のまま）、ログイン・ログアウト後の遷移先はDevise既定のroot_pathのまま
  - マイページ：current_user.nameをエスケープした「〇〇さん、おかえりなさい！」とスマイルアイコン、AIロープレ開始カード（「AIロープレ」を赤字、「AIロープレを始める」から既存の練習テーマ一覧へ）、練習履歴カード（「すべて見る」から既存の練習履歴へ）、アドリー博士からのひとこと
  - 最近の練習：AIロープレ（AiRoleplaySession）と通常録画（ai_roleplay_session_idがnilのPractice）のうち本人の最新1件を表示（作成日時が同じ場合はIDの大きいほう）、テーマ名・日本時間の日時、評価結果・分析結果への既存導線、記録がない場合の案内文、件数によらずクエリ数一定
  - キャラクター：ユーザー指定のムクムク（開始カード）・アドリー博士（ひとこと）を無加工で使用、スマイルアイコンはIssue #82の画像を再利用、smary.pngは未使用・未コミット
  - デザイン：Issue #82の青・白基調を継承、練習履歴は白と淡いグレー、ひとことは淡いクリーム色、カード枠線2px、フォントはBIZ UDPGothic（Webフォントは読み込まず、ない端末は日本語ゴシック体にフォールバック）、PC・スマートフォン対応
  - 既存動作：Devise認証処理、AIロープレの会話・評価・録画・保存処理、ログイン前トップ画面は変更なし、DBテーブルの追加なし
  - テスト：629 runs、3215 assertions、0 failures、0 errors、0 skips
  - Brakeman：警告0件、importmap audit：脆弱性なし、main CI（run 43610825131、lint・scan_js・scan_ruby・test）全4ジョブ成功
  - 本番：Renderデプロイ後、ユーザーが本番ブラウザでログイン前トップ画面、ログイン後マイページ、キャラクター表示、AIロープレへの導線、練習履歴、評価結果、ログアウト、スマートフォン表示を確認
- b2bananaman-pixel/smile_coach#85 source-map-jsのHigh脆弱性を修正する（CLOSED 2026-11-17、チェック項目18項目すべて完了）
  - PR：b2bananaman-pixel/SmileCoach-Projects#124、マージコミット c37e633d2746e1050eb002bafcba0fc1847e4fff
  - 原因：Sass 1.77.8の間接依存source-map-js 1.2.1のHigh脆弱性 GHSA-68fv-2mgg-jv7q（調査はb2bananaman-pixel/smile_coach#84）
  - 実装：source-map-jsを1.2.1から1.2.2へ更新、Sass 1.77.8は維持、変更ファイルはpackage-lock.jsonのみ（version・resolved・integrityの3項目）、package.json・yarn.lockは変更なし
  - 注記：npm updateはyarn.lockも自動で書き換えるため、git restore -- yarn.lockで元に戻した
  - npm audit：High 1件から脆弱性0件、CSSビルド成功・更新前後のapplication.cssがSHA-256とcmpで完全一致
  - テスト：629 runs、3215 assertions、0 failures、0 errors、0 skips
  - RuboCop：150ファイル・違反0件、Brakeman：警告0件、importmap audit：脆弱性なし、main CI（run 43720812059、lint・scan_js・scan_ruby・test）全4ジョブ成功、CIのnpm ciでfound 0 vulnerabilities
  - 本番：Renderでc37e633がDeploy succeeded / Live、ビルドログでnpm ciのfound 0 vulnerabilitiesとDockerfileのassets:precompile実行を確認、ユーザーが本番画面5項目（トップ画面、マイページ、キャラクター画像、練習テーマ一覧、AIロープレ開始画面への導線）を確認
  - 未確認：Renderのnpm run build:css単体のログ（デプロイ全体とassets:precompileは成功）
- b2bananaman-pixel/smile_coach#86 練習カテゴリ・商材選択からAIロープレを開始し、PracticeTheme依存を段階的に解消する（CLOSED 2026-11-19、受け入れ条件43項目すべて完了）
  - PR：b2bananaman-pixel/SmileCoach-Projects#126、マージコミット a4dda7386963f1580a9c105fce4f298037516b6e
  - 方針：B案（PracticeThemeを段階的に廃止し、Product中心のAIロープレへ移行）の第1段階。PracticeThemeテーブル・既存カラム・通常録画・ゲスト機能は削除しない
  - 実装：カテゴリ選択（/practice_categories、ProductCategory.active.ordered、商材0件は「準備中」）、商材選択（/practice_categories/:id、Product.available_for_roleplay、0件は「現在、このカテゴリの練習は準備中です」、無効・不正なIDは404）、商材起点の開始（/products/:product_id/ai_roleplay、非公開・無効カテゴリは404）、旧/practice_themes/:id/ai_roleplayはカテゴリ選択へ302転送
  - 商材必須化：返答生成・保存とも商材情報のトークン必須（なしは422）、トークンから練習テーマを外しversion 2を追加、旧形式トークンは拒否
  - DB：マイグレーション20261119100000（ai_roleplay_sessions・practicesのpractice_theme_idのNULL許可、練習テーマか商材のどちらかを必須とするチェック制約）。練習テーマのない行の作成後はdownが失敗し、旧コードへ戻すと履歴・マイページ・評価画面がエラーになる
  - AI評価：product_snapshot（提案ポイント・確認すべき事項を含む）を区切ったデータとしてシナリオに使用、評価5項目は維持、商材のない過去のセッションは練習テーマを使用
  - 表示：AIロープレ・評価・履歴・マイページにカテゴリ名・商材名（過去のセッションは練習テーマ名）、評価画面から商材選択・カテゴリ選択へ戻る導線
  - テスト：655 runs、3337 assertions、0 failures、0 errors、0 skips（変更前629 runs、3215 assertions）
  - RuboCop：153ファイル・違反0件、Brakeman：警告0件、importmap audit：脆弱性なし、main CI（run 44535155626、lint・scan_js・scan_ruby・test）全4ジョブ成功
  - リリース前：Neon productionの手動スナップショット、pg_dumpバックアップ・SHA-256検証・隔離環境への復元テスト（docs/neon_backup_restore.md）、Render設定（Docker Command・Pre-Deploy Command空欄、Auto-Deploy On Commit）を確認
  - 本番：マージ後の新バージョンへの切り替えを確認、ユーザーが本番でカテゴリ・商材選択、AIロープレの会話、AI評価・音声分析・録画再生、マイページ・履歴の商材名、過去の履歴表示を確認
  - 今後の課題：通常録画・ゲスト録音分析の完全廃止（#66の更新を含む）、PracticeThemeテーブル・カラムの削除と過去データの整理、商材情報を活用したAI評価基準の高度化、不要になったProduct#roleplay_labelの整理
- b2bananaman-pixel/smile_coach#87 ゲスト録音分析機能を廃止し、AIロープレの音声認識を維持する（CLOSED 2026-11-21、受け入れ条件15項目すべて完了）
  - PR：b2bananaman-pixel/SmileCoach-Projects#129、マージコミット c344cbdb0d3ff2d38c2410861495c7b800f6e402
  - 方針：#66の調査で決めたA案（先にゲスト機能を廃止し、そのあと#66で通常録画の新規作成を停止。バーチャル背景・笑顔分析の統合は後回し、過去データは保護）
  - 実装：ログイン不要でGroq APIを呼び出せたゲスト録音分析機能を廃止。ゲスト用のルート3件（/guest/practice_themes、/:id、/:id/create_practice）、GuestPracticeThemesController、View 2件、ゲスト専用Service 4件（GuestAudioAnalysisService・GuestAnalysisResult・GuestVolumeAnalysis・GuestSpeechDurationAnalysis）とそのテストを削除
  - 維持：AIロープレの音声認識（POST /ai_roleplays/transcribe）でも使っていたGuestTranscriptionServiceを、AiRoleplayTranscriptionServiceに名前を変えて維持（処理は同じ。送信ファイル名だけai_roleplay_clerk_audio.webmに変更）
  - テスト追加：AiRoleplayTranscriptionServiceTest（リクエスト内容・失敗時の例外）、GuestFeatureRemovalTest（ルート・ヘルパー・クラスがないこと、ログインの有無によらず404、Groq・AIコメントを呼ばずデータも増えないこと）
  - 既存動作：Practice・Analysis・PracticeTheme・Active Storage、#66の範囲（practice_themes・CreatePracticeService・GroqTranscriptionService・VideoAudioExtractor・JS）、共通Serviceは変更なし。DBマイグレーションなし
  - テスト：662 runs、3368 assertions、0 failures、0 errors、0 skips（Ruby 3.4.13）
  - RuboCop：149ファイル・違反0件、Brakeman：警告0件（EOLRuby・EOLRailsは除外）、importmap audit：脆弱性なし、PR CI（run 44913210836）・main CI（run 44913637352、lint・scan_js・scan_ruby・test）全4ジョブ成功
  - 本番：8項目を確認（Renderでc344cbdがLive、ログイン、マイページ、AIロープレ開始、会話・音声認識、録画保存、AI評価・音声分析、過去の履歴・録画再生）。外部からのGETで/guest/practice_themes・/guest/practice_themes/1が404であることも確認
  - 注記：本番へのPOSTは実行していない（POSTが404になりGroqを呼ばないことは自動テストで確認）。#88のマージ後、Gemfile.lockの未コミット変更（mainと同じ内容）だけをrestoreし、--ff-onlyでmainへ追従した
  - 今後の課題：#66（通常録画の新規作成の停止）、笑顔分析のAIロープレへの統合（Issue未作成）
- b2bananaman-pixel/smile_coach#88 Ruby 3.2.2をセキュリティ修正版へ更新し、CVE-2026-132825に対応する（CLOSED 2026-11-21、受け入れ条件16項目すべて完了）
  - PR：b2bananaman-pixel/SmileCoach-Projects#128、マージコミット 55bdbc7a691b1fc7f423e50732e59ee8d501665e
  - 原因：#87の作業中にBrakemanを8.1.1へ更新したところ、新しいRuby2Shellチェックが警告を出した（Ruby 3.2.2、CVE-2026-132825）。Ruby公式では、2026-11-18公表の正規表現・文字列の大文字小文字変換に関する脆弱性7件（GHSA ID）。Ruby 3.2はEOLのため修正版がない
  - 選定：3.3.14（EOL 2027-03-31予定）と3.4.13（normal maintenance）を比較。Gem 135件の必要Rubyバージョン・Rails 7.2・Docker Hub・setup-rubyのいずれも問題ないため、サポート期間の長い3.4.13を採用
  - 実装：.ruby-versionを3.2.2→3.4.13、DockerfileのARG RUBY_VERSIONを3.2.3→3.4.13に変更。ベースイメージを-slim-bookwormに変えてDebian bookwormを維持（-slimはtrixie）。Gemfile.lockのbrakemanを8.1.0→8.1.1に更新（bin/brakemanの--ensure-latestを維持するため）。CI・Render設定・アプリコード・DBは変更なし
  - 作業方法：#87の未コミット変更を守るため、git worktree（~/Projects/smile_coach_app-issue-88）で作業した。Docker Composeのプロジェクト・DBボリュームは別になる
  - テスト：655 runs、3337 assertions、0 failures、0 errors、0 skips（-W:deprecatedでもRubyの警告0件）
  - RuboCop：153ファイル・違反0件、Brakeman：警告0件（EOLRuby・EOLRailsは除外）、importmap audit：脆弱性なし、PR CI（run 44907288429）・main CI（run 44909432961、lint・scan_js・scan_ruby・test）全4ジョブ成功（Ruby 3.4.13）
  - 本番：Renderデプロイ成功。ユーザーが本番で7項目（ログイン、マイページ表示、AIロープレ開始、会話・音声認識、録画・保存、AI評価結果表示、過去の練習履歴・録画表示）を確認
  - 注記：worktreeにはビルド済みCSSがないため、初回のテストで134件のエラー（application.cssがない）が出た。イメージ内でビルドしたCSSを、管理対象外のapp/assets/builds/へコピーして解消した
  - 今後の課題：Rails 7.2のサポート終了（Brakeman EOLRails、2026-08-09）への対応（Rails 8系への更新）を別Issueで行う
- b2bananaman-pixel/smile_coach#89 AIロープレの練習履歴から録画動画を手動削除できるようにする（CLOSED 2026-11-22）
  - PR：b2bananaman-pixel/SmileCoach-Projects#133、マージコミット aa822eaed256f57c68d4c63a5d189a89c8e8bd0a
  - 実装：DELETE /ai_roleplays/:id/videoでAiRoleplaySession#videoの添付だけを削除（セッションはdestroyしない）。current_user.ai_roleplay_sessionsから検索し他ユーザー・存在しないIDは404。評価画面の録画データカードに確認ダイアログ付きの「動画を削除」ボタン（フォームにdata-turbo-confirm）
  - 削除処理：AiRoleplayVideoDeletionServiceで同期的に削除（purge_laterは使わない）。添付情報の行だけをロックして14日間の自動削除とロック順をそろえ、GCSのファイルを先に削除してから添付情報・blobを削除。共有blobは関連付けだけを外し、削除済みは「すでに削除されています」と表示
  - 保持：AI評価・改善コメント・会話履歴・練習日時・Practice・Analysis・発話音声・文字起こし。既存の14日間自動削除（Service・rakeタスク・ワークフロー）、DB、JavaScriptは変更なし
  - テスト：691 runs、5677 assertions、0 failures、0 errors、0 skips（変更前664 runs、追加27件）
  - RuboCop：145ファイル・違反0件、Brakeman：警告0件（EOLRuby・EOLRailsは除外）、importmap audit：脆弱性なし、Zeitwerk：正常、PR CI（run 45000288850）・main CI（run 45000692589、lint・scan_js・scan_ruby・test）全4ジョブ成功
  - 本番：2026-11-22にユーザーが本番動作確認10項目すべての成功を報告。Claude Codeは外部からのGETで/up・/の200を確認（RenderのLiveはClaude Codeからは直接確認していない。本番へのDELETEは未実行）
  - 注記：本番のAI_ROLEPLAY_VIDEO_RETENTION_ENABLEDは、自動削除ワークフローのログでtrueであることを確認
- b2bananaman-pixel/smile_coach#90 新規ユーザー登録を管理者の招待制にする（CLOSED 2026-11-24、受け入れ条件19項目すべて完了）
  - 目的：URLを知っている人が自由に登録できる状態をやめ、録画の保存容量や外部AI APIの使用量が想定外に増えるのを防ぐため、管理者が招待した人だけが新規登録できるようにする
  - PR：b2bananaman-pixel/SmileCoach-Projects#135（招待の発行・一覧・取り消し、マージコミット b87e42ab57f51c333047bd4faa391fbad2a29000）、b2bananaman-pixel/SmileCoach-Projects#136（CSRFエラー修正、マージコミット 3c8b41be1e0275d18e5e7eaf90f39cf6dc9c6042）、b2bananaman-pixel/SmileCoach-Projects#137（新規登録の招待必須化、マージコミット 4d0917d1681228376f37bc4cbcab5c79a012b6f0）
  - 招待（PR #135）：invitationsテーブル・Invitationモデル（マイグレーション20261122100000）。管理者（admin・super_admin）だけが管理画面で招待先メールアドレスを指定して発行・一覧・取り消しでき、一般ユーザーは404。有効期限は発行から7日、1回限り。登録済みメールと、有効な招待があるメールへの発行は拒否（部分一意インデックス）。招待リンクは発行直後の画面に1回だけ表示し、メールの自動送信はしない
  - トークン：SecureRandom.urlsafe_base64(32)（256ビット）。DBにはSHA-256ダイジェストだけを保存し、セッションには招待IDだけを保存。filter_parametersの:tokenでRailsログは invitation_token=[FILTERED]
  - CSRF修正（PR #136）：招待発行完了画面のReferrer-Policy: no-referrerがTurboの画面移動後も文書に残り、次の通常のフォーム送信がOrigin: nullとなってCSRFのOrigin検証で422になっていた（本番で2回目の発行時に発生）。same-originに変更し、no-storeは維持
  - 登録（PR #137）：招待リンク（GET /users/sign_up?invitation_token=…）でトークンを検証し、招待IDだけをセッションに保存して、トークンを含まないURLへ303でリダイレクト。招待なし・無効・期限切れ・使用済み・取り消し済みは「招待リンクが無効か有効期限が切れています」でログイン画面へ。招待なしのPOST /usersも拒否
  - メールアドレス：送信値を使わず招待先メールアドレスに固定（登録フォームは読み取り専用）。登録後のメールアドレス変更は従来どおり可能
  - トランザクション：Invitation#accept_withで招待の行をロックして有効性を再確認し、ユーザーの作成とaccepted_at・accepted_user_idの設定を同じトランザクションで行う。入力エラー時はロールバックして招待は未使用のまま
  - 権限：role・adminはDeviseのsign_upの許可パラメータに含まれず、登録時は常に一般ユーザー
  - 既存への影響：PR #137のデプロイで本番の自由登録を停止。「新規登録（無料）」ボタンとDevise共通の新規登録リンクは「新規登録は管理者からの招待制です」に変更。既存ユーザーのログイン・パスワード再設定・アカウント編集・退会、AIロープレ・録画・評価・履歴は変更なし
  - テスト：731 runs、5942 assertions（PR #135）→ 734 runs、5963 assertions（PR #136）→ 762 runs、6212 assertions、0 failures、0 errors、0 skips（PR #137）。同時登録は、トランザクションを使わないテストで別々のDB接続の2スレッドから確認
  - RuboCop：151ファイル・違反0件、Brakeman：警告0件（EOLRuby・EOLRailsは除外）、importmap audit：脆弱性なし、Zeitwerk：正常。PR CI（run 45025649154・45034512192・45121577874）・main CI（run 45028901924・45037866057・45152175697、lint・scan_js・scan_ruby・test）全4ジョブ成功
  - 本番：PR #135後にNeonバックアップブランチを作成してマージ、PR 1の本番確認16項目を確認。PR #137前にもバックアップブランチを作成。2026-11-24にユーザーが4d0917dのLiveを確認し、本番動作確認13項目すべて合格（招待制の案内・自由登録の廃止、招待なし登録の拒否、招待発行、登録画面表示、メールアドレス変更不可、登録・自動ログイン、使用済みへの更新、使用済み・取り消し済みリンクの拒否、一般ユーザーの管理画面404、既存ユーザー・データ、AIロープレ関連画面、Renderログ）。Renderログで500・InvalidForeignKey・PG::Error・InvalidAuthenticityToken・RecordInvalid・FATAL・ERRORの該当なし
  - テストユーザー：本番DBをSELECTだけで確認したうえで、通常の退会機能で削除。退会後も招待はaccepted_user_idがNULLになるだけで、使用済みの状態・accepted_at・招待先メールアドレス・発行者は保持され、使用済みリンクは再利用できない
  - 本番で省略：期限切れの拒否・同時登録・権限パラメータ・トークンのログ出力は自動テストで確認。退会後の同じメールアドレスへの再招待とAIロープレ履歴を持つユーザーの退会は、ローカルの一時テストで確認（コミットしていない）
  - 既存の制約：招待リンクのURLはブラウザ履歴・外部（エッジ）アクセスログ・共有に使ったLINEやメールに残る可能性があり、リンクを知った第三者が先に登録できるリスクもある（1回限り・7日・取り消しで影響を抑える）
  - 今後の課題：b2bananaman-pixel/smile_coach#91 退会機能の安全性向上と日本語表示の改善（通常録画履歴があるユーザーの退会で外部キー制約違反の500、退会後の録音・録画ファイルの削除保証、退会の回帰テスト、退会完了メッセージのTranslation missing、退会ボタン・確認ダイアログの日本語化）
## 10. 完了報告
- 変更したファイルと変更内容を報告する。
- 実行したテストコマンドと結果を報告する。
- RuboCopとgit diff --checkの結果を報告する。
- 未完了の作業や注意点を報告する。
- 承認範囲を超えるコミットやマージを実行せず、次に必要な承認と操作をユーザーに案内する。
- PRマージの承認を求める前に、11章の「PRマージの運用」の報告事項を報告する。
## 11. 開発自動化と承認（くらべるん光のD-060に準拠、b2bananaman-pixel/smile_coach#92）
- くらべるん光の開発自動化方針D-060に準拠する。SmileCoach固有の技術構成・既存ルール・データ保護の要件を優先する。新しいD番号の管理体系は作らず、方針はIssue番号で管理する。
### 基本方針
- 安全な作業は原則としてClaude Codeが自動で実行し、調査・実装・テスト・検証・CI確認をできるだけまとめて行う。
- プロダクトオーナーの手動操作と個別承認を最小限にする。ただし、承認の回数を減らすことを理由に必要な確認や安全性を省略しない。
- 機密情報を保存・表示・要求しない。品質とセキュリティを維持する。
- 自動化の仕組みは必要最小限とし、機能開発を優先する（フック・スクリプト・MCPは導入しない）。
### 段階1：自動で実行する（個別の作業承認は不要）
- 既存のコード・設定・開発資料の安全な読み取り（機密ファイルを除く）、Gitの状態の確認、GitHubのIssue・PR・CIの読み取り
- ローカルのテスト、RuboCop、Brakeman、importmap audit、Zeitwerk、npm audit、git diff --check、安全なローカルの動作確認
- テスト・CIが失敗した原因の調査
- 本番URLの/upへのGET（HTTPステータスが200であることだけを確認し、レスポンス本文は取得しない）
- 承認済みIssueへの進捗コメント（検証結果・合否・件数だけ）。これはGitHubへの書き込みであり、承認済みIssueへの限られた報告として許可する
- 本番DBへの接続と、利用者の情報・録音・録画・会話データの取得は、自動実行の対象にしない
### 段階2：Issueの範囲の承認でまとめて実行する
- プロダクトオーナーが、対象のIssue・実装計画の版または日付・受け入れ条件・変更範囲を明示して承認したときだけ実行できる。Issue番号が指定されただけでは承認とみなさない。
- 対象：mainの最新化、作業ブランチの作成、実装、テストの追加・修正、承認範囲内のローカルDBマイグレーション、テスト・静的解析、ファイルを個別に指定したステージング、コミット、作業ブランチへのPush、PR作成、対象Issueの自分の未マージPRの本文の更新、CI確認、承認範囲内のCI失敗の修正と再テスト・再Push・CIの再確認、マージ後のローカルmainの最新化、承認済みのCLAUDE.md完了記録PRの作成
- 計画にない重要な設計の変更、Gemの追加、ルーティングの変更、DBマイグレーション、本番の設定の変更が必要になった場合は停止する。
- CIを成功させるためにテストを削除・弱めたり、セキュリティ検査を無効にしたりしない。
### 段階3：操作ごとに承認する
- PRマージ、本番環境の設定の変更、本番への手動デプロイ・ロールバック、本番DBへの書き込み・削除・復元・リセット
- 認証情報・APIキー・環境変数の変更、本番の録音・録画データの削除、GCSの設定の変更、Neonのバックアップブランチの削除
- 有料契約・追加費用が発生する操作、外部AIサービスの実APIを使用する検証
- 重要な設計の変更、承認済みIssueの範囲を超える変更、開発ルール・権限設定の重要な変更、セキュリティ検査の除外設定の変更
- GitHub Actionsのワークフローの手動実行（本番の定期削除ワークフローの変更・無効化を含む）
- Issueの作成・本文の更新・クローズ、ブランチの削除、GitHubのブランチ保護・rulesetの変更、他プロジェクトへの操作
- 段階3の作業は、承認された対象・操作に限りClaude Codeが実行できる。本番DBのバックアップ、本番のテストユーザーの作成・削除、外部AIを使う本番の動作確認は、引き続きプロダクトオーナーが手動で行う。
### 恒久的に禁止する操作（段階3の承認でも実行しない）
- 強制Push、mainへの直接Push、git reset --hard、git clean、git filter-branch、git branch -D
- git add .・git add -A・git add --all、ディレクトリ単位の一括ステージング
- 管理者権限による保護ルールの迂回（gh pr merge --admin）
- db:drop・db:reset・db:purge などのDBの削除・リセット、Dockerのボリュームの削除
- 機密情報の表示・保存・要求
### 承認の回数と完了処理
- 1つのIssueにつき、承認①実装計画、承認②PRマージ、承認③完了処理の3回を目標とする。3回は目標で上限ではない。
- PRが複数ある場合はPRごとにマージの承認を取る。CLAUDE.mdの完了記録PRのマージにも承認を取る。
- ブランチの削除は、対象のブランチ名と条件を明示したうえで、マージの承認とまとめて承認できる。
- 完了コメント・受け入れ条件のチェック・クローズ・完了記録PRの作成は、完了条件を確かめたうえで1回の承認にまとめる。
- 本番DBのバックアップやデータの削除などは、必要に応じて別に承認する。
### ツールの実行許可と作業の承認の区別
- ツールの実行許可は、Claude Codeがコマンドを実行できる技術的な権限（.claude/settings.json）。作業の承認は、プロダクトオーナーが特定の作業を許可した状態。
- 実行が許可されていても、作業の承認がない段階2・段階3の操作は行わない。作業の承認があっても実行が許可されていない場合は、権限を迂回せず正規の確認の手順に従う。
- 対象を安全に限定できない操作（PR本文の更新、Issueへのコメント、/upへのGETなど）は、作業として承認済みでもaskのままにする。このときの実行確認は、作業の承認の重複ではない。
- 権限の規則はコマンドの文字列の照合であり、完全なセキュリティの境界ではない。mainのブランチ保護、機密情報を保持しないこと、マージ前の確認と承認を組み合わせて運用する。
- .claude/settings.jsonはプロジェクト共有の設定としてGit管理する。ユーザー共通の設定と.claude/settings.local.jsonは変更・作成しない。
- 設定ファイルの変更は実行中のセッションにも再読み込みされることがあるため、設定の変更作業中も承認範囲を守る。設定を変えたら新しいセッションの/permissionsで確認する。
### PRマージの運用
- マージの承認を求める前に、対象リポジトリ、Issue番号・PR番号・PRのURL、PRのHEADコミット、変更ファイルと変更内容、テストの結果、静的解析の結果、CI 4ジョブの結果、マージできるかどうかと競合の有無、DBマイグレーションの有無、本番データへの影響、Renderの自動デプロイ（起動時のdb:prepare）への影響、バックアップの必要性、切り戻しの方法を報告する。
- マージの承認は、確認したPRとHEADコミットに対する承認とする。承認後にHEADや重要な条件が変わった場合はマージせずに確認し直す。
- マージはHEADの一致を条件にして行う：gh pr merge <PR番号> -R b2bananaman-pixel/SmileCoach-Projects --merge --match-head-commit <HEADのSHA>
- CIの失敗・未完了、競合、保護ルールの違反がある場合はマージしない。--adminによる迂回は禁止する。
- mainへのマージでRenderが自動デプロイし、起動時のdb:prepareで本番DBのマイグレーションが実行される。DBマイグレーションを伴う場合は、事前にプロダクトオーナーがバックアップを完了したことを確認してからマージする。
### mainのブランチ保護（b2bananaman-pixel/SmileCoach-Projects）
- PR必須（必須レビュー人数は設定しない）、必須ステータスチェック lint・scan_js・scan_ruby・test、マージ前にブランチを最新にする、管理者にも適用、強制Push・削除の禁止。
- 設定の変更は段階3とし、管理者による迂回を通常の開発フローに含めない。
### SmileCoach固有のセキュリティ・データ保護
- 利用者の情報・メールアドレス・パスワード・招待トークン・セッション・管理者権限、AIロープレの会話・練習履歴・評価・録音・録画、外部AIサービスのAPIキー、本番DB・GCS・Render・Neon・GitHubの認証情報の値や内容・DBの行を、CLAUDE.md・開発資料・Issue・PR・コミット・報告に記載しない。
- .env・docker-compose.override.yml・config/master.key・認証情報・バックアップのファイルの中身は読まない。存在の有無と管理の方法だけを確認する。
- 本番の録音・録画・会話を取得せず、テストデータにも使わない。
- 本番DBに接続するのは、プロダクトオーナーが手動で行うバックアップの手順（docs/neon_backup_restore.md）だけとする。ローカルのDB操作はDocker Composeのdbだけを対象にする。
- 本番データの削除を伴うIssueは、dry-runの件数のプロダクトオーナーによる承認、事前のバックアップ、本番での実行を段階3とすることを受け入れ条件に含める。
- 最後のsuper_adminを守る仕組み、既存の未追跡ファイル・バックアップ・worktree、CI 4ジョブ、Brakemanの既存の除外設定、GitHubのシークレットスキャン・Push protectionを維持する。
### テスト時の外部API通信の防止
- ローカルのテストは、7章のテストコマンドの形で実行する。
  - -f docker-compose.yml：Git管理外のdocker-compose.override.yml（Googleの認証情報をマウントする）を読み込まない
  - -e GROQ_API_KEY=：GroqのAPIキーを空にする
  - http_proxy・https_proxyを到達しない127.0.0.1:9に向け、no_proxyでテストDB（db）とローカルだけを除外する：Net::HTTP・Faradayからの外部へのHTTPS通信を接続拒否にする
- APIキーを空にするだけで外部通信が完全に遮断されるとは判断しない。プロキシの設定もHTTPクライアント以外の通信は防げないため、外部サービスはテストでstubする。
- テスト環境の確認は、値を表示せず真偽値だけで行う（RAILS_ENVがtest、接続先がdbのapp_test、DATABASE_URLなし、GROQ_API_KEYが空、Googleの認証情報なし、Active StorageがDisk）。
- 外部通信を防げることを確認できないテストは実行せず、安全な実行方法を報告する。
### GitHubリポジトリの使い分け
- Issueの操作は -R b2bananaman-pixel/smile_coach、PR・CIの操作は -R b2bananaman-pixel/SmileCoach-Projects を必ず明示する。
- 報告では、Issue・PRの番号をリポジトリ名付きで記載する（例：smile_coach#91、SmileCoach-Projects#138）。
- PR本文には関連Issueの完全なURLを記載する。Closesなどの自動クローズのキーワードは使わず、Issueのクローズは個別承認後に行う。
- GitHubへの書き込みの前に、対象のリポジトリ・番号・タイトルを確認する。コード管理リポジトリのIssue機能と過去のIssueは変更しない。
### 作業停止条件
- 承認済みIssueの範囲を超える変更、または重要な設計の変更が必要になった。
- 本番への書き込み・本番データの削除・認証情報の変更が必要になった、または新たな費用が発生する。
- 機密情報の漏えいのリスクを見つけた。
- 未追跡ファイル・既存worktreeとの競合、想定外のGitの変更を見つけた。対象のリポジトリが想定と異なる。
- テストを弱める必要や、セキュリティ検査を無効にする必要が出た。既存機能への重大な影響を見つけた。
- 承認の状態がはっきりしない、または安全な実行方法を確認できない。
- PRのHEADがマージ承認の時から変わった。
- 通常の実装の誤りや承認範囲内のテストの失敗は、停止せずに修正して再検証する。
- CIの修正は、同じ原因への修正を2回まで、PRあたりのCI修正のPushを合計3回までとする。上限に達しても解決できない場合や、CIの環境そのものの問題など承認範囲内で解決できない場合は、上限まで繰り返さずに停止する。
