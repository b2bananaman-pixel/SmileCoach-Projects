require "test_helper"

class UserLoginTest < ActionDispatch::IntegrationTest
  test "登録済みユーザーがログインできる" do
    user = users(:one)

    post user_session_path, params: {
      user: {
        email: user.email,
        password: "password"
      }
    }

    assert_response :redirect
    assert_redirected_to root_path
  end

  test "間違ったパスワードではログインできない" do
    user = users(:one)

    post user_session_path, params: {
      user: {
        email: user.email,
        password: "wrong_password"
      }
    }

    assert_response :unprocessable_content
    assert_not_equal root_path, response.location
  end

  test "ログアウトできる" do
    user = users(:one)

    post user_session_path, params: {
      user: {
        email: user.email,
        password: "password"
      }
    }

    assert_response :redirect

    delete destroy_user_session_path

    assert_response :redirect
    assert_redirected_to root_path
  end
end
