require "test_helper"

class Admin::DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:one)
    @admin.update!(admin: true)
    @user = users(:two)
  end

  test "GET /adminは管理画面のトップを表示する" do
    assert_recognizes({ controller: "admin/dashboard", action: "show" }, "/admin")
    assert_equal "/admin", admin_root_path
  end

  test "管理者は管理画面を表示できる" do
    sign_in @admin

    get admin_root_path

    assert_response :success
    assert_select "title", text: "管理画面"
    assert_select "[data-admin-dashboard]" do
      assert_select "h1", text: "管理画面"
      assert_select "[data-admin-dashboard-section=products] h2", text: "商材管理"
      assert_select "[data-admin-dashboard-section=roleplay_scenarios] h2", text: "ロープレシチュエーション管理"
    end
  end

  test "管理画面には未実装の機能へのリンクを表示しない" do
    sign_in @admin

    get admin_root_path

    assert_response :success
    assert_select "[data-admin-dashboard] a", count: 0
    assert_select "[data-admin-dashboard] form", count: 0
    assert_select "[data-admin-dashboard] .badge", text: "準備中", count: 2
  end

  test "一般ユーザーが管理画面にアクセスすると404を返す" do
    sign_in @user

    get admin_root_path

    assert_response :not_found
    assert_select "[data-admin-dashboard]", count: 0
    assert_not_includes response.body, "商材管理"
  end

  test "未ログインで管理画面にアクセスするとログイン画面へリダイレクトする" do
    get admin_root_path

    assert_redirected_to new_user_session_path
  end

  test "管理者権限を解除されたユーザーは管理画面にアクセスできない" do
    sign_in @admin
    get admin_root_path
    assert_response :success

    @admin.update!(admin: false)

    get admin_root_path

    assert_response :not_found
  end

  test "一般ユーザーがadminパラメータを付けても管理画面にアクセスできない" do
    sign_in @user

    get admin_root_path, params: { admin: true, user: { admin: true } }

    assert_response :not_found
    assert_not @user.reload.admin?
  end
end
