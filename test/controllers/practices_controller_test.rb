require "test_helper"

class PracticesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)

    @practice_theme = PracticeTheme.create!(
      name: "家電の提案販売",
      description: "冷蔵庫の買い替えを検討しているお客様への接客練習"
    )

    sign_in @user
  end

  test "練習履歴が一覧表示される" do
    practice = Practice.create!(
      user: @user,
      practice_theme: @practice_theme
    )

    Analysis.create!(
      practice: practice,
      total_score: 85
    )

    get practices_url

    assert_response :success
    assert_select "h1", "練習履歴"
    assert_select "h2", "家電の提案販売"
    assert_select "p", /総合スコア：/
  end

  test "練習日時が表示される" do
    practice = Practice.create!(
      user: @user,
      practice_theme: @practice_theme,
      created_at: Time.zone.local(2026, 8, 30, 10, 30)
    )

    Analysis.create!(
      practice: practice,
      total_score: 85
    )

    get practices_url

    assert_response :success
    assert_select "span", "2026/08/30 10:30"
  end

  test "総合スコアが表示される" do
    practice = Practice.create!(
      user: @user,
      practice_theme: @practice_theme
    )

    Analysis.create!(
      practice: practice,
      total_score: 85
    )

    get practices_url

    assert_response :success
    assert_select "strong", "85点"
  end

  test "過去の分析結果詳細へのリンクが表示される" do
    practice = Practice.create!(
      user: @user,
      practice_theme: @practice_theme
    )

    analysis = Analysis.create!(
      practice: practice,
      total_score: 85
    )

    get practices_url

    assert_response :success
    assert_select(
      "a[href='#{analysis_path(analysis)}']",
      "分析結果を見る"
    )
  end

  test "他のユーザーの練習履歴は表示されない" do
    other_user = User.create!(
      name: "他のユーザー",
      email: "other-user@example.com",
      password: "password123"
    )

    own_practice = Practice.create!(
      user: @user,
      practice_theme: @practice_theme
    )

    Analysis.create!(
      practice: own_practice,
      total_score: 85
    )

    other_practice = Practice.create!(
      user: other_user,
      practice_theme: @practice_theme
    )

    Analysis.create!(
      practice: other_practice,
      total_score: 70
    )

    get practices_url

    assert_response :success

    assert_equal(
      1,
      css_select("strong").count do |element|
        element.text.strip == "85点"
      end
    )

    assert_equal(
      0,
      css_select("strong").count do |element|
        element.text.strip == "70点"
      end
    )
  end

  test "練習履歴が0件でも正常に表示される" do
    sign_out @user

    empty_user = User.create!(
      name: "履歴なしユーザー",
      email: "empty-history@example.com",
      password: "password123"
    )

    sign_in empty_user

    get practices_url

    assert_response :success
    assert_select "h1", "練習履歴"
    assert_select ".alert.alert-info", "まだ練習履歴がありません。"
  end

  test "録音動画文字起こしの保存期間と分析結果を保持する案内が表示される" do
    get practices_url

    assert_response :success
    assert_select(
      "div.alert.alert-info",
      text: /録音・動画・文字起こしデータは、練習日から14日を過ぎると自動的に削除されます。練習履歴・分析結果は引き続き確認できます。/
    )
  end

  test "未ログインユーザーは練習履歴一覧にアクセスできない" do
    sign_out @user

    get practices_url

    assert_redirected_to new_user_session_url
  end

  test "自分の練習に紐づく録音データを削除できる" do
    practice = Practice.create!(
      user: @user,
      practice_theme: @practice_theme
    )

    audio_file = fixture_file_upload(
      "test/fixtures/files/test_audio.webm",
      "audio/webm"
    )
    practice.audio.attach(audio_file)

    assert practice.audio.attached?

    delete audio_practice_path(practice)

    assert_redirected_to practices_path

    practice.reload
    assert_not practice.audio.attached?
  end

  test "録音データを削除しても練習履歴と分析結果が残る" do
    practice = Practice.create!(
      user: @user,
      practice_theme: @practice_theme
    )

    audio_file = fixture_file_upload(
      "test/fixtures/files/test_audio.webm",
      "audio/webm"
    )
    practice.audio.attach(audio_file)

    analysis = Analysis.create!(
      practice: practice,
      total_score: 85
    )

    delete audio_practice_path(practice)

    assert_redirected_to practices_path

    practice.reload
    assert_not practice.audio.attached?

    assert Practice.exists?(practice.id)
    assert Analysis.exists?(analysis.id)
    assert_equal 85, analysis.reload.total_score
  end

  test "他のユーザーの録音データは削除できない" do
    other_user = User.create!(
      name: "他のユーザー",
      email: "other-audio-user@example.com",
      password: "password123"
    )

    other_practice = Practice.create!(
      user: other_user,
      practice_theme: @practice_theme
    )

    audio_file = fixture_file_upload(
      "test/fixtures/files/test_audio.webm",
      "audio/webm"
    )
    other_practice.audio.attach(audio_file)

    assert other_practice.audio.attached?

    delete audio_practice_path(other_practice)

    assert_response :not_found

    other_practice.reload
    assert other_practice.audio.attached?
  end

  test "通常録画とAIロープレの履歴が種別付きで表示される" do
    user = sign_in_history_user

    practice = Practice.create!(user: user, practice_theme: @practice_theme)
    Analysis.create!(practice: practice, total_score: 85)

    ai_roleplay_session = AiRoleplaySession.create!(user: user, practice_theme: practice_themes(:one))

    get practices_url

    assert_response :success
    assert_select "[data-practice-history-item]", count: 2

    assert_select '[data-practice-history-item="practice"]' do
      assert_select "[data-practice-history-type]", text: "通常録画"
      assert_select "h2", text: "家電の提案販売"
      assert_select "strong", text: "85点"
    end

    assert_select "[data-ai-roleplay-session-id=\"#{ai_roleplay_session.id}\"]" do
      assert_select "[data-practice-history-type]", text: "AIロープレ"
      assert_select "h2", text: practice_themes(:one).name
    end
  end

  test "音声分析があるAIロープレは通常録画として表示せず1件だけ表示される" do
    user = sign_in_history_user

    ai_roleplay_session = AiRoleplaySession.create!(user: user, practice_theme: @practice_theme)
    voice_practice = Practice.create!(user: user, practice_theme: @practice_theme, ai_roleplay_session: ai_roleplay_session)
    voice_analysis = Analysis.create!(practice: voice_practice, total_score: 77)

    get practices_url

    assert_response :success
    assert_select "[data-practice-history-item]", count: 1
    assert_select '[data-practice-history-item="ai_roleplay"]', count: 1
    assert_select '[data-practice-history-item="practice"]', count: 0
    assert_select "[data-ai-roleplay-history-voice-analysis]", text: "分析済み"

    # 音声分析用のPracticeの総合スコアや通常録画の分析結果画面へのリンクを表示しない
    assert_select "strong", text: "77点", count: 0
    assert_select "a[href=?]", analysis_path(voice_analysis), count: 0
  end

  test "音声分析がないAIロープレも表示され評価の状態が分かる" do
    user = sign_in_history_user

    evaluated_session = AiRoleplaySession.create!(
      user: user,
      practice_theme: @practice_theme,
      created_at: 2.hours.ago
    )
    AiRoleplayEvaluation.create!(ai_roleplay_session: evaluated_session, hearing_score: 4)

    unevaluated_session = AiRoleplaySession.create!(
      user: user,
      practice_theme: @practice_theme,
      created_at: 1.hour.ago
    )

    get practices_url

    assert_response :success
    assert_select '[data-practice-history-item="ai_roleplay"]', count: 2

    assert_select "[data-ai-roleplay-session-id=\"#{evaluated_session.id}\"]" do
      assert_select "[data-ai-roleplay-history-evaluation]", text: "評価済み"
      assert_select "[data-ai-roleplay-history-voice-analysis]", text: "分析結果なし"
    end

    assert_select "[data-ai-roleplay-session-id=\"#{unevaluated_session.id}\"]" do
      assert_select "[data-ai-roleplay-history-evaluation]", text: "評価なし"
      assert_select "[data-ai-roleplay-history-voice-analysis]", text: "分析結果なし"
    end
  end

  test "音声分析に失敗してAnalysisがないAIロープレも履歴から消えない" do
    user = sign_in_history_user

    ai_roleplay_session = AiRoleplaySession.create!(user: user, practice_theme: @practice_theme)
    Practice.create!(user: user, practice_theme: @practice_theme, ai_roleplay_session: ai_roleplay_session)

    get practices_url

    assert_response :success
    assert_select "[data-practice-history-item]", count: 1
    assert_select "[data-ai-roleplay-session-id=\"#{ai_roleplay_session.id}\"]" do
      assert_select "[data-ai-roleplay-history-voice-analysis]", text: "分析結果なし"
      assert_select "a[href=?]", evaluation_ai_roleplay_path(ai_roleplay_session), text: "評価結果を見る"
    end
  end

  test "通常録画は従来どおり分析結果画面へリンクする" do
    user = sign_in_history_user

    practice = Practice.create!(user: user, practice_theme: @practice_theme)
    analysis = Analysis.create!(practice: practice, total_score: 85)

    get practices_url

    assert_response :success
    assert_select '[data-practice-history-item="practice"]' do
      assert_select "a[href=?]", analysis_path(analysis), text: "分析結果を見る"
      assert_select "a", text: "評価結果を見る", count: 0
    end
  end

  test "AIロープレは統合評価画面へリンクする" do
    user = sign_in_history_user

    ai_roleplay_session = AiRoleplaySession.create!(user: user, practice_theme: @practice_theme)
    voice_practice = Practice.create!(user: user, practice_theme: @practice_theme, ai_roleplay_session: ai_roleplay_session)
    Analysis.create!(practice: voice_practice, total_score: 77)

    get practices_url

    assert_response :success
    assert_select '[data-practice-history-item="ai_roleplay"]' do
      assert_select(
        "a[href=?]",
        "/ai_roleplays/#{ai_roleplay_session.id}/evaluation",
        text: "評価結果を見る"
      )
      assert_select "a", text: "分析結果を見る", count: 0
    end
  end

  test "通常録画とAIロープレが実施日時の新しい順に表示される" do
    user = sign_in_history_user

    oldest_practice = Practice.create!(
      user: user,
      practice_theme: @practice_theme,
      created_at: Time.zone.local(2026, 10, 20, 9, 0)
    )
    older_session = AiRoleplaySession.create!(
      user: user,
      practice_theme: @practice_theme,
      created_at: Time.zone.local(2026, 10, 21, 9, 0)
    )
    newer_practice = Practice.create!(
      user: user,
      practice_theme: @practice_theme,
      created_at: Time.zone.local(2026, 10, 22, 9, 0)
    )
    newest_session = AiRoleplaySession.create!(
      user: user,
      practice_theme: @practice_theme,
      created_at: Time.zone.local(2026, 10, 23, 9, 0)
    )

    # 音声分析用のPracticeは作成日時が新しくても、通常録画として並ばない
    Practice.create!(
      user: user,
      practice_theme: @practice_theme,
      ai_roleplay_session: older_session,
      created_at: Time.zone.local(2026, 10, 24, 9, 0)
    )

    get practices_url

    assert_response :success

    displayed_times = css_select("[data-practice-history-item] span:not([data-practice-history-type])").map do |element|
      element.text.strip
    end

    assert_equal(
      [ newest_session, newer_practice, older_session, oldest_practice ].map { |item| item.created_at.strftime("%Y/%m/%d %H:%M") },
      displayed_times
    )

    assert_equal(
      %w[ai_roleplay practice ai_roleplay practice],
      css_select("[data-practice-history-item]").map { |element| element["data-practice-history-item"] }
    )
  end

  test "AIロープレの実施日時が日本時間で表示される" do
    user = sign_in_history_user

    AiRoleplaySession.create!(
      user: user,
      practice_theme: @practice_theme,
      created_at: Time.utc(2026, 10, 25, 1, 30)
    )

    get practices_url

    assert_response :success
    assert_select '[data-practice-history-item="ai_roleplay"] span', text: "2026/10/25 10:30"
  end

  test "他のユーザーのAIロープレの履歴は表示されない" do
    user = sign_in_history_user

    own_session = AiRoleplaySession.create!(user: user, practice_theme: @practice_theme)

    other_session = ai_roleplay_sessions(:two)
    other_voice_practice = Practice.create!(
      user: other_session.user,
      practice_theme: other_session.practice_theme,
      ai_roleplay_session: other_session
    )
    Analysis.create!(practice: other_voice_practice, total_score: 70)

    get practices_url

    assert_response :success
    assert_select "[data-practice-history-item]", count: 1
    assert_select "[data-ai-roleplay-session-id=\"#{own_session.id}\"]", count: 1
    assert_select "[data-ai-roleplay-session-id=\"#{other_session.id}\"]", count: 0
    assert_select "a[href=?]", evaluation_ai_roleplay_path(other_session), count: 0
  end

  test "未ログインユーザーはAIロープレを含む練習履歴にアクセスできない" do
    sign_out @user

    assert AiRoleplaySession.exists?(user: @user)

    get practices_url

    assert_redirected_to new_user_session_url
  end

  test "履歴の件数が増えても関連データの取得クエリ数は増えない" do
    few_count = history_query_count(1)
    many_count = history_query_count(3)

    assert_equal few_count, many_count
  end

  private

  def sign_in_history_user
    sign_out @user

    user = User.create!(
      name: "履歴確認ユーザー#{User.count}",
      email: "history-#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )

    sign_in user

    user
  end

  def history_query_count(item_count)
    user = sign_in_history_user

    item_count.times do
      practice = Practice.create!(user: user, practice_theme: @practice_theme)
      Analysis.create!(practice: practice, total_score: 85)

      ai_roleplay_session = AiRoleplaySession.create!(user: user, practice_theme: @practice_theme)
      AiRoleplayEvaluation.create!(ai_roleplay_session: ai_roleplay_session, hearing_score: 4)
      voice_practice = Practice.create!(user: user, practice_theme: @practice_theme, ai_roleplay_session: ai_roleplay_session)
      Analysis.create!(practice: voice_practice, total_score: 77)
    end

    queries = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      queries << payload[:sql] unless payload[:name] == "SCHEMA"
    end

    begin
      get practices_url
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    assert_response :success
    assert_select "[data-practice-history-item]", count: item_count * 2

    queries.size
  end
end
