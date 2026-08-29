require "test_helper"

class AnalysesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @analysis = analyses(:one)
  end

  test "ログインユーザー自身の分析結果を表示できる" do
    sign_in @user

    get analysis_path(@analysis)

    assert_response :success
    assert_select "body"
  end

  test "他ユーザーの分析結果は表示できない" do
    sign_in @user

    other_analysis = analyses(:two)

    get analysis_path(other_analysis)

    assert_response :not_found
  end

  test "未ログインの場合はログイン画面へリダイレクトされる" do
    get analysis_path(@analysis)

    assert_redirected_to new_user_session_path
  end
end
