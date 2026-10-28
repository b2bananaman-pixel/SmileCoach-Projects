require "test_helper"

class AdminAuthorizationTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
  end

  test "管理者にはナビゲーションに管理画面リンクを表示する" do
    @user.update!(admin: true)
    sign_in @user

    get root_path

    assert_response :success
    assert_select "nav a[data-admin-nav-link][href=?]", admin_root_path, text: "管理画面"
    assert_select "nav button", text: "ログアウト"
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
    @user.update!(admin: true)
    sign_in @user

    get practice_themes_path

    assert_response :success
    assert_select "nav a[href=?]", admin_root_path, text: "管理画面"
    assert_select "nav a[href=?]", root_path, text: "ホーム"
  end

  test "新規登録でadmin=trueを送信しても管理者にならない" do
    assert_difference("User.count", 1) do
      post user_registration_path, params: {
        user: {
          name: "新規ユーザー",
          email: "admin-attempt@example.com",
          password: "password",
          password_confirmation: "password",
          admin: true
        }
      }
    end

    user = User.find_by!(email: "admin-attempt@example.com")

    assert_equal "新規ユーザー", user.name
    assert_not user.admin?
  end

  test "アカウント更新でadmin=trueを送信しても管理者にならない" do
    sign_in @user

    put user_registration_path, params: {
      user: {
        email: "changed-email@example.com",
        current_password: "password",
        admin: true
      }
    }

    assert_redirected_to root_path

    @user.reload

    # 他の項目の更新は成功し、adminだけが無視されることを確認する
    assert_equal "changed-email@example.com", @user.email
    assert_not @user.admin?
  end

  test "管理者がアカウント更新でadmin=falseを送信しても権限は変わらない" do
    @user.update!(admin: true)
    sign_in @user

    put user_registration_path, params: {
      user: {
        email: @user.email,
        current_password: "password",
        admin: false
      }
    }

    assert_redirected_to root_path
    assert @user.reload.admin?
  end
end
