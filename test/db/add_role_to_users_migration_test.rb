require "test_helper"
require Rails.root.join("db/migrate/20261107150000_add_role_to_users")

# roleを追加するマイグレーションのデータ移行とロールバックを確認する
#
# PostgreSQLではDDLもトランザクション内で実行されるため、テスト終了時のロールバックでスキーマも元に戻る。
# マイグレーション中はUserモデルのカラム情報と一致しないため、データの確認はSQLで行う。
class AddRoleToUsersMigrationTest < ActiveSupport::TestCase
  setup do
    @connection = ActiveRecord::Base.connection
  end

  teardown do
    # テスト中に変更したスキーマの情報を、ロールバック後に読み直す
    @connection.schema_cache.clear!
    User.reset_column_information
  end

  test "upで既存の管理者をrole=adminへ移行し、それ以外をrole=userにする" do
    migrate(:down)
    admin_id = insert_user("legacy-admin@example.com", admin: true)
    user_id = insert_user("legacy-user@example.com", admin: false)

    migrate(:up)

    assert_equal 1, role_of(admin_id)
    assert_equal 0, role_of(user_id)
    assert_equal 0, @connection.select_value("SELECT COUNT(*) FROM users WHERE role = 2")
  end

  test "upの後も旧adminカラムは変更されず、旧コードでも管理者として判定できる" do
    migrate(:down)
    admin_id = insert_user("legacy-admin@example.com", admin: true)
    user_id = insert_user("legacy-user@example.com", admin: false)

    migrate(:up)

    assert_equal true, admin_of(admin_id)
    assert_equal false, admin_of(user_id)
  end

  test "upの後に追加したユーザーはrole=user・admin=falseになる" do
    migrate(:down)
    migrate(:up)

    user_id = insert_user("new-user@example.com")

    assert_equal 0, role_of(user_id)
    assert_equal false, admin_of(user_id)
  end

  test "upでroleのCHECK制約とインデックスを追加する" do
    migrate(:down)
    migrate(:up)

    assert @connection.index_exists?(:users, :role)
    assert @connection.check_constraint_exists?(:users, name: "users_role_check")
  end

  test "downで管理者・最高管理者をadmin=trueに書き戻してからroleを削除する" do
    admin_id = insert_user("admin@example.com", admin: false, role: 1)
    super_admin_id = insert_user("super-admin@example.com", admin: false, role: 2)
    user_id = insert_user("user@example.com", admin: false, role: 0)

    migrate(:down)

    assert_not @connection.column_exists?(:users, :role)
    assert_not @connection.check_constraint_exists?(:users, name: "users_role_check")
    assert_equal true, admin_of(admin_id)
    assert_equal true, admin_of(super_admin_id)
    assert_equal false, admin_of(user_id)
  end

  test "downの後に再度upすると、最高管理者はadminになる（super_adminとadminの区別は失われる）" do
    super_admin_id = insert_user("super-admin@example.com", admin: true, role: 2)

    migrate(:down)
    migrate(:up)

    assert_equal 1, role_of(super_admin_id)
  end

  private

  def migrate(direction)
    ActiveRecord::Migration.suppress_messages { AddRoleToUsers.new.migrate(direction) }
  end

  def insert_user(email, admin: nil, role: nil)
    columns = { "name" => "移行テスト", "email" => email, "encrypted_password" => "x", "created_at" => Time.current, "updated_at" => Time.current }
    columns["admin"] = admin unless admin.nil?
    columns["role"] = role unless role.nil?

    @connection.select_value(<<~SQL.squish)
      INSERT INTO users (#{columns.keys.join(', ')})
      VALUES (#{columns.values.map { |value| @connection.quote(value) }.join(', ')})
      RETURNING id
    SQL
  end

  def role_of(user_id)
    @connection.select_value("SELECT role FROM users WHERE id = #{Integer(user_id)}")
  end

  def admin_of(user_id)
    @connection.select_value("SELECT admin FROM users WHERE id = #{Integer(user_id)}")
  end
end
