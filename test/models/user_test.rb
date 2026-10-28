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

  test "新規ユーザーは管理者ではない" do
    user = User.create!(
      name: "新規ユーザー",
      email: "new-user@example.com",
      password: "password123"
    )

    assert_equal false, user.reload.admin
    assert_not user.admin?
  end

  test "既存ユーザーは管理者ではない" do
    assert_not users(:one).admin?
    assert_not users(:two).admin?
  end

  test "管理者権限の付与と解除をadmin?で判定できる" do
    user = users(:one)

    user.update!(admin: true)
    assert user.reload.admin?

    user.update!(admin: false)
    assert_not user.reload.admin?
  end

  test "管理者権限をnilにはできない" do
    user = users(:one)

    assert_raises(ActiveRecord::NotNullViolation) do
      user.update_column(:admin, nil)
    end
  end
end
