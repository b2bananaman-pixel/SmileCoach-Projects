require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "テストユーザーを作成できる" do
    user = create_test_user

    assert user.persisted?
    assert_equal "テストユーザー", user.name
    assert_equal "test@example.com", user.email
  end
end