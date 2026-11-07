require "test_helper"

class Admin::SuperAdmin::DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    @super_admin = users(:super_admin)
    @admin = users(:admin)
    @user = users(:two)
  end

  test "GET /admin/super_adminは最高管理者画面を表示する" do
    assert_recognizes({ controller: "admin/super_admin/dashboard", action: "show" }, "/admin/super_admin")
    assert_equal "/admin/super_admin", admin_super_admin_root_path
  end

  test "最高管理者は最高管理者画面を表示できる" do
    sign_in @super_admin

    get admin_super_admin_root_path

    assert_response :success
    assert_select "title", text: "最高管理者画面"
    assert_select "[data-super-admin-dashboard] h1", text: "最高管理者画面"
    assert_select "[data-super-admin-dashboard] a", count: 0
    assert_select "[data-super-admin-dashboard] form", count: 0
  end

  test "管理者が最高管理者画面にアクセスすると404を返す" do
    sign_in @admin

    get admin_super_admin_root_path

    assert_response :not_found
    assert_select "[data-super-admin-dashboard]", count: 0
    assert_not_includes response.body, "最高管理者画面"
  end

  test "一般ユーザーが最高管理者画面にアクセスすると404を返す" do
    sign_in @user

    get admin_super_admin_root_path

    assert_response :not_found
    assert_select "[data-super-admin-dashboard]", count: 0
  end

  test "未ログインで最高管理者画面にアクセスするとログイン画面へリダイレクトする" do
    get admin_super_admin_root_path

    assert_redirected_to new_user_session_path
  end

  test "最高管理者から降格されたユーザーは最高管理者画面にアクセスできない" do
    # 最後の最高管理者は降格できないため、別のユーザーを最高管理者にしてから降格する
    users(:one).change_role!(:super_admin)

    sign_in @super_admin
    get admin_super_admin_root_path
    assert_response :success

    @super_admin.change_role!(:admin)

    get admin_super_admin_root_path

    assert_response :not_found
  end

  test "管理者がroleパラメータを付けても最高管理者画面にアクセスできない" do
    sign_in @admin

    get admin_super_admin_root_path, params: { role: "super_admin", user: { role: "super_admin" } }

    assert_response :not_found
    assert @admin.reload.admin?
  end
end
