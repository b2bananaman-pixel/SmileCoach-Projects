
# SmileCoach 開発ルール
## 1. プロジェクト概要
- SmileCoachは接客練習を録音・録画し、AIによる分析・評価を行うRailsアプリケーション。
- Ruby on Rails、PostgreSQL、Docker、Minitestを使用する。
- 既存の録音・録画・分析・認証機能を壊さないこと。
- 既存コードを調査し、現在の実装に合わせて開発すること。
- ユーザーへの説明・報告は日本語で行うこと。
## 2. 基本方針
- これまでのSmileCoachの開発手順を維持する。
- 1つのIssueにつき1つの作業ブランチを使用する。
- Issueの受け入れ条件を満たすために必要な変更だけを行う。
- Issueの範囲外のリファクタリングや機能追加を勝手に行わない。
- 仕様が不明な場合は、実装前に確認する。
- ユーザーの明示的な承認を得てからファイルを変更する。
- 原則として1ステップずつ進め、結果を報告する。
## 3. Claude Codeの担当範囲
- 既存コードの調査
- 実装方針と変更予定ファイルの提示
- 承認後のコード作成・修正
- テストの追加・修正・実行
- RuboCopの実行
- 差分と変更ファイルの確認
- 実装結果とテスト結果の報告
## 4. 実装前の確認
- 現在のブランチを確認する。
- 関連するモデル、コントローラ、サービス、ビュー、テストを調査する。
- 修正予定ファイルと変更理由を提示する。
- 既存機能への影響と必要なテストを説明する。
- ユーザーの承認があるまで実装しない。
## 5. Git運用ルール
- mainブランチで直接実装しない。
- mainの最新化と作業ブランチの作成は原則ユーザーが行う。
- コミット、Push、Pull Request作成、マージ、ブランチ削除はユーザーが行う。
- Claude Codeは明示的な依頼なしにGitの書き込み操作を行わない。
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
- テストコマンド例：docker compose run --rm -e RAILS_ENV=test web bin/rails test
- RuboCopを実行する。
- git diff --checkを実行する。
- git statusで変更ファイルを確認する。
- テスト失敗やRuboCop違反がある場合は原因と対応内容を報告する。
- 実際に確認していない結果を成功と報告しない。
## 8. いつもの開発手順
1. Issue内容と受け入れ条件を確認
2. mainを最新化
3. 作業ブランチを作成
4. 既存コードを調査して実装方針を提示
5. ユーザーの承認後に実装
6. テストを追加・修正して実行
7. RuboCopとgit diff --checkを実行
8. git statusと変更内容を確認
9. 変更ファイルを個別にステージング
10. コミット
11. GitHubへPush
12. Pull Requestを作成
13. CIのlint、scan_js、scan_ruby、testを確認
14. CI成功後にPull Requestをmainへマージ
15. ローカルmainを最新化
16. 作業ブランチを整理
17. 今回のIssueの詳細な作業記録を作成
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
## 10. 完了報告
- 変更したファイルと変更内容を報告する。
- 実行したテストコマンドと結果を報告する。
- RuboCopとgit diff --checkの結果を報告する。
- 未完了の作業や注意点を報告する。
- コミットやマージを勝手に実行せず、次の操作をユーザーに案内する。
