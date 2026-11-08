require "test_helper"

class Admin::DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    @super_admin = users(:super_admin)
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

  test "最高管理者は管理画面を表示できる" do
    sign_in @super_admin

    get admin_root_path

    assert_response :success
    assert_select "[data-admin-dashboard] h1", text: "管理画面"
  end

  test "商材管理から商材一覧とカテゴリ管理へ移動できる" do
    sign_in @admin

    get admin_root_path

    assert_response :success
    assert_select "[data-admin-dashboard-section=products]" do
      assert_select "a[href='#{admin_products_path}']", text: "商材一覧"
      assert_select "a[href='#{admin_product_categories_path}']", text: "カテゴリ管理"
      assert_select ".badge", text: "準備中", count: 0
    end
  end

  test "管理画面には未実装の機能へのリンクを表示しない" do
    sign_in @admin

    get admin_root_path

    assert_response :success
    assert_select "[data-admin-dashboard] a", count: 2
    assert_select "[data-admin-dashboard-section=roleplay_scenarios] a", count: 0
    assert_select "[data-admin-dashboard] form", count: 0
    assert_select "[data-admin-dashboard-section=roleplay_scenarios] .badge", text: "準備中", count: 1
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

    @admin.change_role!(:user)

    get admin_root_path

    assert_response :not_found
  end

  test "一般ユーザーがadmin・roleパラメータを付けても管理画面にアクセスできない" do
    sign_in @user

    get admin_root_path, params: { admin: true, role: "super_admin", user: { admin: true, role: "super_admin" } }

    assert_response :not_found
    assert @user.reload.user?
  end
end
