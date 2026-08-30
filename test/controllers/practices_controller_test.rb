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

  test "未ログインユーザーは練習履歴一覧にアクセスできない" do
    sign_out @user

    get practices_url

    assert_redirected_to new_user_session_url
  end
end
