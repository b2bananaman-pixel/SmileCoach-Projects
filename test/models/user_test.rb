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

  test "新規ユーザーの権限は一般ユーザーになる" do
    user = User.create!(
      name: "新規ユーザー",
      email: "new-user@example.com",
      password: "password123"
    )

    assert user.reload.user?
    assert_equal 0, user.role_before_type_cast
    assert_not user.admin_access?
    assert_not user.super_admin?
  end

  test "既存ユーザーは一般ユーザーのまま利用できる" do
    assert users(:one).user?
    assert users(:two).user?
    assert_not users(:one).admin_access?
  end

  test "権限はuser=0・admin=1・super_admin=2で管理する" do
    assert_equal({ "user" => 0, "admin" => 1, "super_admin" => 2 }, User.roles)
  end

  test "管理者と最高管理者は管理者向け機能を利用できる" do
    assert users(:admin).admin_access?
    assert_not users(:admin).super_admin?

    assert users(:super_admin).admin_access?
    assert users(:super_admin).super_admin?
  end

  test "想定外の権限は保存できない" do
    user = users(:one)
    user.role = "owner"

    assert_not user.valid?
    assert user.errors.of_kind?(:role, :inclusion)
  end

  test "DBのCHECK制約により想定外の権限の値を保存できない" do
    assert_raises(ActiveRecord::StatementInvalid) do
      User.where(id: users(:one).id).update_all(role: 3)
    end
  end

  test "権限をnilにはできない" do
    assert_raises(ActiveRecord::NotNullViolation) do
      users(:one).update_column(:role, nil)
    end
  end

  test "旧adminカラムはモデルから読み書きしない" do
    assert_not_includes User.column_names, "admin"
    assert_not users(:admin).has_attribute?(:admin)
  end

  test "change_role!で権限を変更し、旧adminカラムも同期する" do
    user = users(:one)

    user.change_role!(:admin)
    assert user.reload.admin?
    assert_equal true, legacy_admin_column(user)

    user.change_role!(:super_admin)
    assert user.reload.super_admin?
    assert_equal true, legacy_admin_column(user)

    user.change_role!(:user)
    assert user.reload.user?
    assert_equal false, legacy_admin_column(user)
  end

  test "最高管理者が0人の場合も既存ユーザーを最初の最高管理者にできる" do
    User.where(role: :super_admin).update_all(role: User.roles[:admin])
    user = users(:one)

    user.change_role!(:super_admin)

    assert_equal [ user.id ], User.super_admin.pluck(:id)
  end

  test "最後の最高管理者は降格・解除できない" do
    super_admin = users(:super_admin)

    [ :admin, :user ].each do |role|
      assert_raises(ActiveRecord::RecordNotSaved) { super_admin.change_role!(role) }
      assert super_admin.reload.super_admin?
      assert_equal true, legacy_admin_column(super_admin)
    end

    assert_not super_admin.update(role: :user)
    assert_includes super_admin.errors[:base], User::LAST_SUPER_ADMIN_ERROR_MESSAGE
    assert super_admin.reload.super_admin?
  end

  test "最高管理者が複数いる場合は1人を降格できる" do
    other_super_admin = users(:one)
    other_super_admin.change_role!(:super_admin)

    users(:super_admin).change_role!(:admin)

    assert users(:super_admin).reload.admin?
    assert_equal [ other_super_admin.id ], User.super_admin.pluck(:id)
  end

  test "最後の最高管理者は削除できない" do
    super_admin = users(:super_admin)

    assert_no_difference("User.count") do
      assert_not super_admin.destroy
    end

    assert_includes super_admin.errors[:base], User::LAST_SUPER_ADMIN_ERROR_MESSAGE
  end

  test "最高管理者が複数いる場合は1人を削除できる" do
    users(:one).change_role!(:super_admin)

    assert_difference("User.count", -1) do
      assert users(:super_admin).destroy
    end
  end

  test "最高管理者以外のユーザーは削除できる" do
    assert_difference("User.count", -1) do
      assert users(:admin).destroy
    end
  end

  test "メモリ上の権限が古くてもDBの値で最後の最高管理者を判定する" do
    stale_super_admin = User.find(users(:super_admin).id)
    User.where(id: stale_super_admin.id).update_all(role: User.roles[:admin])

    # DBではすでに最高管理者ではないため、最後の最高管理者として扱わない
    assert stale_super_admin.destroy
  end

  private

  def legacy_admin_column(user)
    User.where(id: user.id).pick(:admin)
  end
end
