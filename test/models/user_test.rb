require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "name is required" do
    user = User.new(
      email: "test@example.com",
      password: "password123"
    )

    assert_not user.valid?
    assert_includes user.errors[:name], "を入力してください"
  end
end
