require "test_helper"

class AdminAuthorizationTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
  end

  test "管理者にはナビゲーションに管理画面リンクを表示する" do
    sign_in users(:admin)

    get root_path

    assert_response :success
    assert_select "nav a[data-admin-nav-link][href=?]", admin_root_path, text: "管理画面"
    assert_select "nav button", text: "ログアウト"
  end

  test "最高管理者にはナビゲーションに管理画面リンクを表示する" do
    sign_in users(:super_admin)

    get root_path

    assert_response :success
    assert_select "nav a[data-admin-nav-link][href=?]", admin_root_path, text: "管理画面"
  end

  test "一般ユーザーにはナビゲーションに管理画面リンクを表示しない" do
    sign_in @user

    get root_path

    assert_response :success
    assert_select "nav a[href=?]", admin_root_path, count: 0
    assert_select "nav button", text: "ログアウト"
  end

  test "未ログインユーザーにはナビゲーションに管理画面リンクを表示しない" do
    get root_path

    assert_response :success
    assert_select "nav a[href=?]", admin_root_path, count: 0
  end

  test "管理画面リンクは管理者の他の画面のナビゲーションにも表示する" do
    sign_in users(:admin)

    get practice_themes_path

    assert_response :success
    assert_select "nav a[href=?]", admin_root_path, text: "管理画面"
    assert_select "nav a[href=?]", root_path, text: "ホーム"
  end

  test "新規登録でadmin・roleを送信しても一般ユーザーとして登録される" do
    assert_difference("User.count", 1) do
      post user_registration_path, params: {
        user: {
          name: "新規ユーザー",
          email: "admin-attempt@example.com",
          password: "password",
          password_confirmation: "password",
          admin: true,
          role: "super_admin"
        }
      }
    end

    user = User.find_by!(email: "admin-attempt@example.com")

    assert_equal "新規ユーザー", user.name
    assert user.user?
    assert_equal false, User.where(id: user.id).pick(:admin)
  end

  test "アカウント更新でadmin・roleを送信しても権限は変わらない" do
    sign_in @user

    put user_registration_path, params: {
      user: {
        email: "changed-email@example.com",
        current_password: "password",
        admin: true,
        role: "super_admin"
      }
    }

    assert_redirected_to root_path

    @user.reload

    # 他の項目の更新は成功し、admin・roleだけが無視されることを確認する
    assert_equal "changed-email@example.com", @user.email
    assert @user.user?
  end

  test "管理者がアカウント更新でroleを送信しても権限は変わらない" do
    admin = users(:admin)
    sign_in admin

    put user_registration_path, params: {
      user: {
        email: admin.email,
        current_password: "password",
        admin: false,
        role: "user"
      }
    }

    assert_redirected_to root_path
    assert admin.reload.admin?
  end

  test "最後の最高管理者はアカウントを削除できず、ログイン状態のまま編集画面へ戻る" do
    super_admin = users(:super_admin)
    sign_in super_admin

    assert_no_difference("User.count") do
      delete user_registration_path
    end

    assert_redirected_to edit_user_registration_path
    assert_equal User::LAST_SUPER_ADMIN_ERROR_MESSAGE, flash[:alert]
    assert super_admin.reload.super_admin?

    # ログアウトしていないことを確認する
    get admin_super_admin_root_path
    assert_response :success
  end

  test "最高管理者が複数いる場合は最高管理者もアカウントを削除できる" do
    @user.change_role!(:super_admin)
    sign_in users(:super_admin)

    assert_difference("User.count", -1) do
      delete user_registration_path
    end

    assert_redirected_to root_path
  end

  test "一般ユーザーはこれまでどおりアカウントを削除できる" do
    # 練習履歴のあるユーザーは外部キー制約により削除できない（既存の動作）ため、練習履歴のないユーザーで確認する
    user = User.create!(name: "削除するユーザー", email: "delete-me@example.com", password: "password")
    sign_in user

    assert_difference("User.count", -1) do
      delete user_registration_path
    end

    assert_redirected_to root_path
    assert_not User.exists?(user.id)
  end
end
