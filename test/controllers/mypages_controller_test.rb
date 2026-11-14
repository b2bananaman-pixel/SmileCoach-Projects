require "test_helper"

class MypagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
  end

  test "未ログイン時の / はログイン前のトップ画面を表示する" do
    get root_path

    assert_response :success
    assert_select "h1", text: /AIと楽しくロープレしながら/
    assert_select "form[action='#{user_session_path}']"
    assert_select "[data-mypage-welcome]", count: 0
  end

  test "ログイン後の / はユーザー名付きのマイページを表示する" do
    sign_in @user

    get root_path

    assert_response :success
    assert_select "h1[data-mypage-welcome]", text: "Fixture Userさん、おかえりなさい！"
    assert_select "p", text: "今日もAIロープレで接客スキルを磨きましょう。"
    assert_select "h2", text: "AIロープレで練習する"
    assert_select "p", text: "お客様との会話を実践的に練習しましょう。"
    assert_select "h2", text: /練習履歴/
    assert_select "form[action='#{user_session_path}']", count: 0
    assert_select ".auth-landing", count: 0
  end

  test "ウェルカムメッセージの右側にスマイルアイコンを表示する" do
    sign_in @user

    get root_path

    assert_response :success
    assert_select ".mypage-welcome-heading" do
      assert_select "h1[data-mypage-welcome] + img[data-mypage-smile-icon][src*='smilecoach_smile_icon'][alt='スマイルアイコン']"
    end
    assert_select "img[src*='characters/smary']", count: 0
  end

  test "開始カードの見出しはAIロープレだけを赤文字用のクラスで表示する" do
    sign_in @user

    get root_path

    assert_select "h2.mypage-start-title", text: "AIロープレで練習する" do
      assert_select "span.mypage-start-title-accent", count: 1, text: "AIロープレ"
    end
    accent = css_select("h2.mypage-start-title span.mypage-start-title-accent").first
    assert_equal "AIロープレ", accent.text
  end

  test "ムクムク・アドリー博士の画像とアドリー博士からのひとことを表示する" do
    sign_in @user

    get root_path

    assert_response :success
    assert_select ".mypage-start-card img[data-mypage-character='mukumuku'][src*='characters/mukumuku'][alt='ムクムク']"
    assert_select "[data-mypage-advice]" do
      assert_select "img[data-mypage-character='adory_professor'][src*='characters/adory_professor'][alt='アドリー博士']"
      assert_select "h2", text: "アドリー博士からのひとこと"
      assert_select "h2 i.bi-lightbulb[aria-hidden='true']"
      assert_select "[data-mypage-advice-message]", text: "今日の練習では、お客様の話を最後まで聴くことを意識してみよう！"
    end
  end

  test "マイページは外部のWebフォントを読み込まない" do
    sign_in @user

    get root_path

    assert_response :success
    assert_select "head link[href*='fonts.googleapis.com']", count: 0
    assert_select "head link[href*='fonts.gstatic.com']", count: 0
  end

  test "キャラクター画像はアセットパイプラインから配信される" do
    sign_in @user

    get root_path
    image_paths = css_select("img[data-mypage-character]").map { |image| image["src"] }

    image_paths << css_select("img[data-mypage-smile-icon]").first["src"]

    assert_equal 3, image_paths.size
    image_paths.each do |path|
      assert_match %r{\A/assets/(characters/)?[a-z_]+-[0-9a-f]+\.png\z}, path

      get path
      assert_response :success
      assert_equal "image/png", response.media_type
    end
  end

  test "ユーザー名はHTMLエスケープして表示する" do
    @user.update_column(:name, "<script>alert(1)</script>")
    sign_in @user

    get root_path

    assert_response :success
    assert_not_includes response.body, "<script>alert(1)</script>"
    assert_includes response.body, "&lt;script&gt;alert(1)&lt;/script&gt;さん、おかえりなさい！"
  end

  test "AIロープレを始めるボタンは練習テーマ一覧へ、すべて見るは練習履歴へ遷移する" do
    sign_in @user

    get root_path

    assert_select "a[data-start-practice-link][href='#{practice_themes_path}']", text: "AIロープレを始める"
    assert_select "a[data-practice-history-link][href='#{practices_path}']", text: /すべて見る/

    get practice_themes_path
    assert_response :success

    get practices_path
    assert_response :success
  end

  test "練習記録がない場合は案内文を表示する" do
    sign_in users(:admin)

    get root_path

    assert_response :success
    assert_select "[data-mypage-recent-empty]", text: "まだ練習履歴がありません。最初のAIロープレに挑戦しましょう！"
    assert_select "[data-mypage-recent-practice]", count: 0
  end

  test "AIロープレが最新の場合はテーマ名と日本時間の日時と評価結果へのリンクを表示する" do
    clear_records(@user)
    session = create_ai_roleplay_session(@user, created_at: Time.utc(2026, 11, 14, 1, 30))
    create_practice(@user, created_at: Time.utc(2026, 11, 13, 1, 30))
    sign_in @user

    get root_path

    assert_select "[data-mypage-recent-practice='ai_roleplay'][data-record-id='#{session.id}']"
    assert_select "[data-mypage-recent-theme]", text: practice_themes(:one).name
    assert_select "[data-mypage-recent-date]", text: "2026/11/14 10:30"
    assert_select "a[href='#{evaluation_ai_roleplay_path(session)}']", text: "評価結果を見る"
  end

  test "通常録画が最新の場合は通常録画を表示し、分析結果があれば分析結果へのリンクを表示する" do
    clear_records(@user)
    create_ai_roleplay_session(@user, created_at: Time.utc(2026, 11, 13, 1, 30))
    practice = create_practice(@user, created_at: Time.utc(2026, 11, 14, 2, 0), practice_theme: practice_themes(:two))
    analysis = Analysis.create!(practice: practice, total_score: 80)
    sign_in @user

    get root_path

    assert_select "[data-mypage-recent-practice='practice'][data-record-id='#{practice.id}']"
    assert_select "[data-mypage-recent-theme]", text: practice_themes(:two).name
    assert_select "[data-mypage-recent-date]", text: "2026/11/14 11:00"
    assert_select "a[href='#{analysis_path(analysis)}']", text: "分析結果を見る"
  end

  test "AIロープレの評価がなくてもエラーにならない" do
    clear_records(@user)
    session = create_ai_roleplay_session(@user, created_at: Time.current)
    sign_in @user

    get root_path

    assert_response :success
    assert_nil session.reload.ai_roleplay_evaluation
    assert_select "a[href='#{evaluation_ai_roleplay_path(session)}']"
  end

  test "通常録画の分析結果がない場合は詳細へのリンクを表示しない" do
    clear_records(@user)
    practice = create_practice(@user, created_at: Time.current)
    sign_in @user

    get root_path

    assert_response :success
    assert_select "[data-mypage-recent-practice='practice'][data-record-id='#{practice.id}']"
    assert_select "[data-mypage-recent-practice] a", count: 0
  end

  test "AIロープレの音声分析用Practiceは通常録画として扱わない" do
    clear_records(@user)
    session = create_ai_roleplay_session(@user, created_at: Time.utc(2026, 11, 13, 1, 0))
    create_practice(@user, created_at: Time.utc(2026, 11, 14, 1, 0), ai_roleplay_session: session)
    sign_in @user

    get root_path

    assert_select "[data-mypage-recent-practice='ai_roleplay'][data-record-id='#{session.id}']"
  end

  test "作成日時が同じ場合はIDの大きい記録を表示する" do
    clear_records(@user)
    created_at = Time.utc(2026, 11, 14, 1, 0)
    older = create_practice(@user, created_at: created_at)
    newer = create_practice(@user, created_at: created_at)
    assert_operator newer.id, :>, older.id
    sign_in @user

    get root_path

    assert_select "[data-mypage-recent-practice='practice'][data-record-id='#{newer.id}']"
  end

  test "他のユーザーの練習記録は表示しない" do
    clear_records(@user)
    other_user = users(:two)
    create_ai_roleplay_session(other_user, created_at: 1.minute.from_now, practice_theme: practice_themes(:two))
    create_practice(other_user, created_at: 1.minute.from_now, practice_theme: practice_themes(:two))
    sign_in @user

    get root_path

    assert_select "[data-mypage-recent-empty]"
    assert_select "[data-mypage-recent-practice]", count: 0
  end

  test "練習記録が増えても最近の練習の取得クエリ数は変わらない" do
    clear_records(@user)
    create_ai_roleplay_session(@user, created_at: 2.days.ago)
    create_practice(@user, created_at: 1.day.ago)
    sign_in @user

    get root_path
    few_count = count_queries { get root_path }

    5.times do |i|
      create_ai_roleplay_session(@user, created_at: (i + 3).days.ago)
      create_practice(@user, created_at: (i + 3).days.ago)
    end
    many_count = count_queries { get root_path }

    assert_equal few_count, many_count
  end

  test "ログイン成功後はマイページ、ログアウト後はログイン前のトップ画面へ戻る" do
    post user_session_path, params: { user: { email: @user.email, password: "password" } }

    assert_redirected_to root_path
    follow_redirect!
    assert_select "[data-mypage-welcome]"

    delete destroy_user_session_path

    assert_redirected_to root_path
    follow_redirect!
    assert_select "[data-mypage-welcome]", count: 0
    assert_select "form[action='#{user_session_path}']"
  end

  private

  def clear_records(user)
    Practice.where(user: user).find_each(&:destroy!)
    user.ai_roleplay_sessions.find_each(&:destroy!)
  end

  def create_ai_roleplay_session(user, created_at:, practice_theme: practice_themes(:one))
    AiRoleplaySession.create!(user: user, practice_theme: practice_theme, created_at: created_at)
  end

  def create_practice(user, created_at:, practice_theme: nil, ai_roleplay_session: nil)
    practice_theme ||= ai_roleplay_session&.practice_theme || practice_themes(:one)

    Practice.create!(
      user: user,
      practice_theme: practice_theme,
      ai_roleplay_session: ai_roleplay_session,
      created_at: created_at
    )
  end

  def count_queries(&block)
    # テストでは前のリクエストのクエリキャッシュが残るため、キャッシュから返ったものも含めて数える
    count = 0
    counter = lambda do |_name, _start, _finish, _id, payload|
      count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name])
    end

    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end
end
