require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get home_index_url
    assert_response :success
  end

  test "logged in user can see practice theme link" do
    user = users(:one)

    post user_session_url, params: {
      user: {
        email: user.email,
        password: "password"
      }
    }

    get home_index_url
    assert_response :success
    assert_select "a[href='#{practice_themes_path}']", text: "練習テーマを選択する"
    assert_select "form[action='#{destroy_user_session_path}']"
  end

  test "新規登録とログインへのリンクが表示される" do
    get home_index_url

    assert_response :success
    assert_select "a", text: "新規登録"
    assert_select "a", text: "ログイン"
  end

  test "練習履歴の保存期間についての案内が表示される" do
    get home_index_url

    assert_response :success
    assert_select "div.alert.alert-info", text: /練習履歴・分析結果・録音データは、練習日から14日を過ぎると自動的に削除されます。/
  end
end
