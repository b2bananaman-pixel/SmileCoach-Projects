require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  SKILL_LABELS = %w[笑顔 話し方 傾聴力 ヒアリング力 提案力 クロージング力].freeze
  FEATURE_TITLES = %w[AIロープレで実践練習 練習を重ねて成長 練習履歴・成長の確認].freeze

  test "should get index" do
    get home_index_url
    assert_response :success
  end

  test "logged in user can see practice theme link" do
    sign_in_as(users(:one))

    get home_index_url
    assert_response :success
    assert_select "a[href='#{practice_themes_path}'][data-start-practice-link]", text: "AIロープレを始める"
    assert_select "a[href='#{practices_path}']", text: "練習履歴を見る"
    assert_select "form[action='#{destroy_user_session_path}']"
  end

  test "ログイン済みの場合はログインフォームと新規登録ボタンを表示しない" do
    sign_in_as(users(:one))

    get root_path

    assert_response :success
    assert_select "form[action='#{user_session_path}']", count: 0
    assert_select "a[href='#{new_user_registration_path}']", count: 0
  end

  test "新規登録とログインへのリンクが表示される" do
    get home_index_url

    assert_response :success
    assert_select "a[href='#{new_user_registration_path}']", text: "新規登録（無料）"
    assert_select "a[href='#{new_user_password_path}']", text: "パスワードをお忘れの方はこちら"
    assert_select "form[action='#{user_session_path}'] button[type='submit']", text: "ログイン"
  end

  test "未ログイン時はトップ画面にログインフォームが表示される" do
    get root_path

    assert_response :success
    assert_select "h2", text: "ログイン"
    assert_select "p", text: /SmileCoachにログインして、\s*AIロープレの練習を始めましょう。/
    assert_select "form[action='#{user_session_path}'][method='post']" do
      assert_select "input[type='email'][name='user[email]']"
      assert_select "input[type='password'][name='user[password]']"
    end
    assert_select "a[data-start-practice-link]", count: 0
  end

  test "見出しと6つの接客スキルと3つの機能紹介が表示される" do
    get root_path

    assert_response :success
    assert_select "h1", text: /AIと楽しくロープレしながら\s*お客様満足度の高い提案スキルを身につけましょう/
    assert_select "h1 .auth-headline-accent", text: "満足度の高い提案スキル"
    assert_equal SKILL_LABELS, css_select("[data-auth-skills] li").map { |node| node.text.strip }
    assert_equal FEATURE_TITLES, css_select("[data-auth-features] h3").map { |node| node.text.strip }
  end

  test "指定のスマイルアイコンとキャラクター画像が表示される" do
    get root_path

    assert_response :success
    assert_select "img[data-brand-smile-icon][src*='smilecoach_smile_icon'][alt]"
    assert_select "img[data-brand-characters][src*='smilecoach_characters'][alt='スマリー・ムクムク・アドリー博士']"
  end

  test "録音動画文字起こしの保存期間と分析結果を保持する案内が表示される" do
    get home_index_url

    assert_response :success
    assert_select(
      "div.alert.alert-info",
      text: /録音・動画・文字起こしデータは、練習日から14日を過ぎると自動的に削除されます。練習履歴・分析結果は引き続き確認できます。/
    )
  end

  private

  def sign_in_as(user)
    post user_session_url, params: {
      user: {
        email: user.email,
        password: "password"
      }
    }
  end
end
