require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "ユーザー登録ができる" do
    assert_difference("User.count", 1) do
      post user_registration_path, params: {
        user: {
          name: "新規ユーザー",
          email: "newuser@example.com",
          password: "password",
          password_confirmation: "password"
        }
      }
    end

    user = User.find_by(email: "newuser@example.com")

    assert user.present?
    assert_equal "新規ユーザー", user.name
  end
end