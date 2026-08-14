require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get home_index_url
    assert_response :success
  end
  test "新規登録とログインへのリンクが表示される" do
    get home_index_url

    assert_response :success
    assert_select "a", text: "新規登録"
    assert_select "a", text: "ログイン"
  end

end
