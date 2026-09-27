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

  test "録音動画文字起こしの保存期間と分析結果を保持する案内が表示される" do
    get home_index_url

    assert_response :success
    assert_select(
      "div.alert.alert-info",
      text: /録音・動画・文字起こしデータは、練習日から14日を過ぎると自動的に削除されます。練習履歴・分析結果は引き続き確認できます。/
    )
  end
end
